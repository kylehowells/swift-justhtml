// ArenaNode.swift - Experimental arena-based node storage to reduce ARC overhead

import Foundation

// MARK: - NodeHandle

/// Handle to a node in the arena (replaces pointers with indices)
public struct NodeHandle: Hashable, Sendable, Equatable {
	public let index: UInt32

	public static let invalid = NodeHandle(index: UInt32.max)

	@inline(__always)
	public var isValid: Bool { index != UInt32.max }

	public init(index: UInt32) {
		self.index = index
	}
}

// MARK: - ArenaNodeData

/// Struct-based node data (no ARC overhead for relationships)
public struct ArenaNodeData {
	// Identity
	public var name: String
	public var tagId: TagID
	public var namespace: Namespace?

	// Attributes
	public var attrs: [String: String]

	// Content for text/comment/doctype nodes
	public var textContent: String?
	public var doctypeData: Doctype?

	// Tree structure (indices, not pointers - no ARC!)
	public var parent: NodeHandle = .invalid
	public var firstChild: NodeHandle = .invalid
	public var lastChild: NodeHandle = .invalid  // Track last child for O(1) append
	public var nextSibling: NodeHandle = .invalid

	// For template elements
	public var templateContent: NodeHandle = .invalid

	public init(
		name: String,
		tagId: TagID,
		namespace: Namespace?,
		attrs: [String: String] = [:],
		textContent: String? = nil,
		doctypeData: Doctype? = nil
	) {
		self.name = name
		self.tagId = tagId
		self.namespace = namespace
		self.attrs = attrs
		self.textContent = textContent
		self.doctypeData = doctypeData
	}
}

// MARK: - NodeArena

/// Arena that owns all nodes - eliminates per-node ARC overhead
public final class NodeArena {
	/// All nodes stored contiguously
	public private(set) var nodes: ContiguousArray<ArenaNodeData> = []

	/// Pre-allocate capacity
	public init(estimatedNodeCount: Int = 1000) {
		nodes.reserveCapacity(estimatedNodeCount)
	}

	// MARK: - Node Creation

	/// Create a new node and return its handle
	@inline(__always)
	public func createNode(
		name: String,
		namespace: Namespace? = nil,
		attrs: [String: String] = [:]
	) -> NodeHandle {
		let tagId = TagID.from(name)
		let handle = NodeHandle(index: UInt32(nodes.count))

		var node = ArenaNodeData(
			name: name,
			tagId: tagId,
			namespace: namespace,
			attrs: attrs
		)

		// Auto-create template content for template elements
		if tagId == .template, namespace == nil || namespace == .html {
			let templateHandle = createNode(name: "#document-fragment")
			node.templateContent = templateHandle
		}

		nodes.append(node)
		return handle
	}

	/// Create a text node
	@inline(__always)
	public func createTextNode(_ text: String) -> NodeHandle {
		let handle = NodeHandle(index: UInt32(nodes.count))
		let node = ArenaNodeData(
			name: "#text",
			tagId: .text,
			namespace: nil,
			textContent: text
		)
		nodes.append(node)
		return handle
	}

	/// Create a comment node
	@inline(__always)
	public func createCommentNode(_ text: String) -> NodeHandle {
		let handle = NodeHandle(index: UInt32(nodes.count))
		let node = ArenaNodeData(
			name: "#comment",
			tagId: .comment,
			namespace: nil,
			textContent: text
		)
		nodes.append(node)
		return handle
	}

	/// Create a doctype node
	@inline(__always)
	public func createDoctypeNode(_ doctype: Doctype) -> NodeHandle {
		let handle = NodeHandle(index: UInt32(nodes.count))
		let node = ArenaNodeData(
			name: "!doctype",
			tagId: .doctype,
			namespace: nil,
			doctypeData: doctype
		)
		nodes.append(node)
		return handle
	}

	// MARK: - Node Access

	/// Get node data by handle
	@inline(__always)
	public subscript(_ handle: NodeHandle) -> ArenaNodeData {
		get { nodes[Int(handle.index)] }
		set { nodes[Int(handle.index)] = newValue }
	}

	// MARK: - Tree Manipulation

	/// Append a child to a parent node - O(1) operation
	@inline(__always)
	public func appendChild(parent: NodeHandle, child: NodeHandle) {
		nodes[Int(child.index)].parent = parent

		let lastChild = nodes[Int(parent.index)].lastChild
		if !lastChild.isValid {
			// No children yet
			nodes[Int(parent.index)].firstChild = child
		} else {
			// Link to last child
			nodes[Int(lastChild.index)].nextSibling = child
		}
		nodes[Int(parent.index)].lastChild = child
	}

	/// Insert child before reference node
	public func insertBefore(parent: NodeHandle, child: NodeHandle, reference: NodeHandle?) {
		guard let ref = reference, ref.isValid else {
			appendChild(parent: parent, child: child)
			return
		}

		nodes[Int(child.index)].parent = parent

		let firstChild = nodes[Int(parent.index)].firstChild
		if firstChild == ref {
			// Insert at beginning
			nodes[Int(child.index)].nextSibling = firstChild
			nodes[Int(parent.index)].firstChild = child
		} else {
			// Find node before reference
			var prev = firstChild
			while prev.isValid {
				let next = nodes[Int(prev.index)].nextSibling
				if next == ref {
					nodes[Int(prev.index)].nextSibling = child
					nodes[Int(child.index)].nextSibling = ref
					break
				}
				prev = next
			}
		}
	}

	/// Remove child from parent
	public func removeChild(parent: NodeHandle, child: NodeHandle) {
		let firstChild = nodes[Int(parent.index)].firstChild

		if firstChild == child {
			// Remove first child
			nodes[Int(parent.index)].firstChild = nodes[Int(child.index)].nextSibling
		} else {
			// Find and unlink
			var prev = firstChild
			while prev.isValid {
				let next = nodes[Int(prev.index)].nextSibling
				if next == child {
					nodes[Int(prev.index)].nextSibling = nodes[Int(child.index)].nextSibling
					break
				}
				prev = next
			}
		}

		nodes[Int(child.index)].parent = .invalid
		nodes[Int(child.index)].nextSibling = .invalid
	}

	// MARK: - Tree Queries

	/// Get children of a node
	public func children(of handle: NodeHandle) -> [NodeHandle] {
		var result: [NodeHandle] = []
		var current = nodes[Int(handle.index)].firstChild
		while current.isValid {
			result.append(current)
			current = nodes[Int(current.index)].nextSibling
		}
		return result
	}

	/// Check if node has children
	@inline(__always)
	public func hasChildren(_ handle: NodeHandle) -> Bool {
		nodes[Int(handle.index)].firstChild.isValid
	}

	/// Get last child - O(1) operation
	@inline(__always)
	public func lastChild(of handle: NodeHandle) -> NodeHandle {
		return nodes[Int(handle.index)].lastChild
	}

	// MARK: - Text Operations

	/// Append text to a text node
	@inline(__always)
	public func appendText(to handle: NodeHandle, text: String) {
		if var existing = nodes[Int(handle.index)].textContent {
			existing.append(text)
			nodes[Int(handle.index)].textContent = existing
		} else {
			nodes[Int(handle.index)].textContent = text
		}
	}

	// MARK: - Conversion to Node tree

	/// Convert arena to traditional Node tree (for API compatibility)
	public func toNodeTree(root: NodeHandle) -> Node {
		return convertToNode(handle: root)
	}

	private func convertToNode(handle: NodeHandle) -> Node {
		let data = nodes[Int(handle.index)]

		// Create node with appropriate data
		let nodeData: NodeData?
		if let text = data.textContent {
			if data.tagId == .text {
				nodeData = .text(text)
			} else if data.tagId == .comment {
				nodeData = .comment(text)
			} else {
				nodeData = nil
			}
		} else if let doctype = data.doctypeData {
			nodeData = .doctype(doctype)
		} else {
			nodeData = nil
		}

		let node = Node(
			name: data.name,
			namespace: data.namespace,
			attrs: data.attrs,
			data: nodeData
		)

		// Convert children
		var childHandle = data.firstChild
		while childHandle.isValid {
			let childNode = convertToNode(handle: childHandle)
			node.appendChild(childNode)
			childHandle = nodes[Int(childHandle.index)].nextSibling
		}

		// Convert template content
		if data.templateContent.isValid {
			node.templateContent = convertToNode(handle: data.templateContent)
		}

		return node
	}
}

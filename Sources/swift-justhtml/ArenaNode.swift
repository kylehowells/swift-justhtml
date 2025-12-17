// ArenaNode.swift - Experimental arena-based node storage to reduce ARC overhead

import Foundation

// MARK: - NodeHandle

/// Handle to a node in the arena (replaces pointers with indices)
public struct NodeHandle: Hashable, Sendable, Equatable {
	public let index: UInt32

	public static let invalid = NodeHandle(index: UInt32.max)

	@inline(__always)
	public var isValid: Bool { self.index != UInt32.max }

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
	public var namespace: Namespace? = nil

	/// Attributes
	public var attrs: [String: String]

	// Content for text/comment/doctype nodes
	public var textContent: String? = nil
	public var doctypeData: Doctype? = nil

	// Tree structure (indices, not pointers - no ARC!)
	public var parent: NodeHandle = .invalid
	public var firstChild: NodeHandle = .invalid
	public var lastChild: NodeHandle = .invalid // Track last child for O(1) append
	public var nextSibling: NodeHandle = .invalid

	/// For template elements
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
		self.nodes.reserveCapacity(estimatedNodeCount)
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
			let templateHandle = self.createNode(name: "#document-fragment")
			node.templateContent = templateHandle
		}

		self.nodes.append(node)
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
		self.nodes.append(node)
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
		self.nodes.append(node)
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
		self.nodes.append(node)
		return handle
	}

	// MARK: - Node Access

	/// Get node data by handle
	@inline(__always)
	public subscript(_ handle: NodeHandle) -> ArenaNodeData {
		get { self.nodes[Int(handle.index)] }
		set { self.nodes[Int(handle.index)] = newValue }
	}

	// MARK: - Tree Manipulation

	/// Append a child to a parent node - O(1) operation
	@inline(__always)
	public func appendChild(parent: NodeHandle, child: NodeHandle) {
		self.nodes[Int(child.index)].parent = parent

		let lastChild = self.nodes[Int(parent.index)].lastChild
		if !lastChild.isValid {
			// No children yet
			self.nodes[Int(parent.index)].firstChild = child
		}
		else {
			// Link to last child
			self.nodes[Int(lastChild.index)].nextSibling = child
		}
		self.nodes[Int(parent.index)].lastChild = child
	}

	/// Insert child before reference node
	public func insertBefore(parent: NodeHandle, child: NodeHandle, reference: NodeHandle?) {
		guard let ref = reference, ref.isValid else {
			self.appendChild(parent: parent, child: child)
			return
		}

		self.nodes[Int(child.index)].parent = parent

		let firstChild = self.nodes[Int(parent.index)].firstChild
		if firstChild == ref {
			// Insert at beginning
			self.nodes[Int(child.index)].nextSibling = firstChild
			self.nodes[Int(parent.index)].firstChild = child
		}
		else {
			// Find node before reference
			var prev = firstChild
			while prev.isValid {
				let next = self.nodes[Int(prev.index)].nextSibling
				if next == ref {
					self.nodes[Int(prev.index)].nextSibling = child
					self.nodes[Int(child.index)].nextSibling = ref
					break
				}
				prev = next
			}
		}
	}

	/// Remove child from parent
	public func removeChild(parent: NodeHandle, child: NodeHandle) {
		let firstChild = self.nodes[Int(parent.index)].firstChild

		if firstChild == child {
			// Remove first child
			self.nodes[Int(parent.index)].firstChild = self.nodes[Int(child.index)].nextSibling
		}
		else {
			// Find and unlink
			var prev = firstChild
			while prev.isValid {
				let next = self.nodes[Int(prev.index)].nextSibling
				if next == child {
					self.nodes[Int(prev.index)].nextSibling = self.nodes[Int(child.index)].nextSibling
					break
				}
				prev = next
			}
		}

		self.nodes[Int(child.index)].parent = .invalid
		self.nodes[Int(child.index)].nextSibling = .invalid
	}

	// MARK: - Tree Queries

	/// Get children of a node
	public func children(of handle: NodeHandle) -> [NodeHandle] {
		var result: [NodeHandle] = []
		var current = self.nodes[Int(handle.index)].firstChild
		while current.isValid {
			result.append(current)
			current = self.nodes[Int(current.index)].nextSibling
		}
		return result
	}

	/// Check if node has children
	@inline(__always)
	public func hasChildren(_ handle: NodeHandle) -> Bool {
		self.nodes[Int(handle.index)].firstChild.isValid
	}

	/// Get last child - O(1) operation
	@inline(__always)
	public func lastChild(of handle: NodeHandle) -> NodeHandle {
		return self.nodes[Int(handle.index)].lastChild
	}

	// MARK: - Text Operations

	/// Append text to a text node
	@inline(__always)
	public func appendText(to handle: NodeHandle, text: String) {
		if var existing = nodes[Int(handle.index)].textContent {
			existing.append(text)
			self.nodes[Int(handle.index)].textContent = existing
		}
		else {
			self.nodes[Int(handle.index)].textContent = text
		}
	}

	// MARK: - Conversion to Node tree

	/// Convert arena to traditional Node tree (for API compatibility)
	public func toNodeTree(root: NodeHandle) -> Node {
		return self.convertToNode(handle: root)
	}

	private func convertToNode(handle: NodeHandle) -> Node {
		let data = self.nodes[Int(handle.index)]

		// Create node with appropriate data
		let nodeData: NodeData?
		if let text = data.textContent {
			if data.tagId == .text {
				nodeData = .text(text)
			}
			else if data.tagId == .comment {
				nodeData = .comment(text)
			}
			else {
				nodeData = nil
			}
		}
		else if let doctype = data.doctypeData {
			nodeData = .doctype(doctype)
		}
		else {
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
			let childNode = self.convertToNode(handle: childHandle)
			node.appendChild(childNode)
			childHandle = self.nodes[Int(childHandle.index)].nextSibling
		}

		// Convert template content
		if data.templateContent.isValid {
			node.templateContent = self.convertToNode(handle: data.templateContent)
		}

		return node
	}
}

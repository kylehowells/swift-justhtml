// Node.swift - Simple DOM node for HTML parsing

import Foundation

/// Namespace for HTML elements
public enum Namespace: String, Sendable {
    case html
    case svg
    case math
}

/// Data payload for special node types
public enum NodeData {
    case text(String)
    case comment(String)
    case doctype(Doctype)
}

/// DOCTYPE information
public struct Doctype: Sendable {
    public let name: String?
    public let publicId: String?
    public let systemId: String?
    public let forceQuirks: Bool

    public init(name: String? = nil, publicId: String? = nil, systemId: String? = nil, forceQuirks: Bool = false) {
        self.name = name
        self.publicId = publicId
        self.systemId = systemId
        self.forceQuirks = forceQuirks
    }
}

/// A simple DOM node
public final class Node {
    /// Node type/name: "#document", "#document-fragment", "#text", "#comment", "!doctype", or tag name
    public let name: String

    /// Namespace: .html, .svg, .math, or nil for non-elements
    public let namespace: Namespace?

    /// Parent node (weak to avoid cycles)
    public weak var parent: Node?

    /// Child nodes
    public private(set) var children: [Node] = []

    /// Attributes (empty for non-elements)
    public var attrs: [String: String]

    /// Data for text/comment/doctype nodes
    public var data: NodeData?

    /// Template content (for <template> elements)
    public var templateContent: Node?

    public init(name: String, namespace: Namespace? = nil, attrs: [String: String] = [:], data: NodeData? = nil) {
        self.name = name
        self.attrs = attrs
        self.data = data

        // Determine namespace
        if name.hasPrefix("#") || name == "!doctype" {
            self.namespace = nil
        } else {
            self.namespace = namespace ?? .html
        }

        // Create template content for template elements
        if name == "template", namespace == nil || namespace == .html {
            self.templateContent = Node(name: "#document-fragment")
        }
    }

    // MARK: - DOM Manipulation

    public func appendChild(_ node: Node) {
        self.children.append(node)
        node.parent = self
    }

    public func removeChild(_ node: Node) {
        if let idx = children.firstIndex(where: { $0 === node }) {
            self.children.remove(at: idx)
            node.parent = nil
        }
    }

    public func insertBefore(_ node: Node, reference: Node?) {
        guard let reference = reference else {
            self.appendChild(node)
            return
        }
        if let idx = children.firstIndex(where: { $0 === reference }) {
            self.children.insert(node, at: idx)
            node.parent = self
        }
    }

    public func replaceChild(_ newNode: Node, oldNode: Node) -> Node? {
        if let idx = children.firstIndex(where: { $0 === oldNode }) {
            self.children[idx] = newNode
            oldNode.parent = nil
            newNode.parent = self
            return oldNode
        }
        return nil
    }

    public func cloneNode(deep: Bool = false) -> Node {
        let clone = Node(name: name, namespace: namespace, attrs: attrs, data: data)
        if let templateContent = templateContent {
            clone.templateContent = templateContent.cloneNode(deep: deep)
        }
        if deep {
            for child in self.children {
                clone.appendChild(child.cloneNode(deep: true))
            }
        }
        return clone
    }

    // MARK: - Properties

    public var hasChildNodes: Bool {
        !self.children.isEmpty
    }

    /// Direct text content of this node only (for #text nodes)
    public var text: String {
        if case let .text(s) = data {
            return s
        }
        return ""
    }

    // MARK: - Serialization

    /// Extract all text content
    public func toText(separator: String = " ", strip: Bool = true) -> String {
        var parts: [String] = []
        self.collectText(into: &parts, strip: strip)
        return parts.joined(separator: separator)
    }

    private func collectText(into parts: inout [String], strip: Bool) {
        if case let .text(s) = data {
            let text = strip ? s.trimmingCharacters(in: .whitespacesAndNewlines) : s
            if !text.isEmpty {
                parts.append(text)
            }
            return
        }

        for child in self.children {
            child.collectText(into: &parts, strip: strip)
        }
        // Note: templateContent is intentionally NOT included
        // Template contents are inert and should not be part of text extraction
    }

    /// Serialize to HTML
    public func toHTML(pretty: Bool = true, indentSize: Int = 2) -> String {
        return Serialize.toHTML(self, pretty: pretty, indentSize: indentSize)
    }

    /// Serialize to html5lib test format
    public func toTestFormat() -> String {
        return Serialize.toTestFormat(self)
    }

    /// Serialize to Markdown (GitHub-Flavored Markdown subset)
    public func toMarkdown() -> String {
        return Serialize.toMarkdown(self)
    }

    /// Query using CSS selector
    public func query(_ selector: String) throws -> [Node] {
        return try swift_justhtml.query(self, selector: selector)
    }
}

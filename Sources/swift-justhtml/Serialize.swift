// Serialize.swift - HTML serialization utilities

import Foundation

public enum Serialize {
    // MARK: - Test Format (html5lib-tests)

    /// Serialize node to html5lib test format
    public static func toTestFormat(_ node: Node) -> String {
        if node.name == "#document" || node.name == "#document-fragment" {
            return node.children.map { nodeToTestFormat($0, indent: 0) }.joined(separator: "\n")
        }
        return nodeToTestFormat(node, indent: 0)
    }

    private static func nodeToTestFormat(_ node: Node, indent: Int) -> String {
        let padding = String(repeating: " ", count: indent)

        switch node.name {
        case "#comment":
            if case .comment(let text) = node.data {
                return "| \(padding)<!-- \(text) -->"
            }
            return "| \(padding)<!-- -->"

        case "!doctype":
            return doctypeToTestFormat(node)

        case "#text":
            if case .text(let text) = node.data {
                return "| \(padding)\"\(text)\""
            }
            return "| \(padding)\"\""

        default:
            return elementToTestFormat(node, indent: indent)
        }
    }

    private static func doctypeToTestFormat(_ node: Node) -> String {
        guard case .doctype(let doctype) = node.data else {
            return "| <!DOCTYPE >"
        }

        var parts = ["| <!DOCTYPE"]

        if let name = doctype.name, !name.isEmpty {
            parts.append(" \(name)")
        } else {
            parts.append(" ")
        }

        if doctype.publicId != nil || doctype.systemId != nil {
            let pub = doctype.publicId ?? ""
            let sys = doctype.systemId ?? ""
            parts.append(" \"\(pub)\"")
            parts.append(" \"\(sys)\"")
        }

        parts.append(">")
        return parts.joined()
    }

    private static func elementToTestFormat(_ node: Node, indent: Int) -> String {
        let padding = String(repeating: " ", count: indent)
        let qualifiedName = self.qualifiedName(node)
        var lines = ["| \(padding)<\(qualifiedName)>"]

        // Attributes (sorted)
        let sortedAttrs = node.attrs.sorted { $0.key < $1.key }
        for (name, value) in sortedAttrs {
            var displayName = name
            // Handle foreign attributes with namespace prefix
            if let ns = node.namespace, ns != .html {
                if let adjusted = FOREIGN_ATTRIBUTE_ADJUSTMENTS[name.lowercased()] {
                    displayName = name.replacingOccurrences(of: ":", with: " ")
                }
            }
            let attrPadding = String(repeating: " ", count: indent + 2)
            lines.append("| \(attrPadding)\(displayName)=\"\(value)\"")
        }

        // Template content
        if node.name == "template" && (node.namespace == nil || node.namespace == .html),
           let templateContent = node.templateContent {
            let contentPadding = String(repeating: " ", count: indent + 2)
            lines.append("| \(contentPadding)content")
            for child in templateContent.children {
                lines.append(nodeToTestFormat(child, indent: indent + 4))
            }
        } else {
            // Regular children
            for child in node.children {
                lines.append(nodeToTestFormat(child, indent: indent + 2))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func qualifiedName(_ node: Node) -> String {
        if let ns = node.namespace, ns != .html {
            return "\(ns.rawValue) \(node.name)"
        }
        return node.name
    }

    // MARK: - HTML Serialization

    /// Serialize node to HTML
    public static func toHTML(_ node: Node, pretty: Bool = true, indentSize: Int = 2) -> String {
        return nodeToHTML(node, indent: 0, indentSize: indentSize, pretty: pretty)
    }

    private static func nodeToHTML(_ node: Node, indent: Int, indentSize: Int, pretty: Bool) -> String {
        let prefix = pretty ? String(repeating: " ", count: indent * indentSize) : ""
        let newline = pretty ? "\n" : ""

        switch node.name {
        case "#text":
            if case .text(let text) = node.data {
                if pretty {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { return "" }
                    return "\(prefix)\(escapeText(trimmed))"
                }
                return escapeText(text)
            }
            return ""

        case "#comment":
            if case .comment(let text) = node.data {
                return "\(prefix)<!--\(text)-->"
            }
            return "\(prefix)<!---->"

        case "!doctype":
            return "\(prefix)<!DOCTYPE html>"

        case "#document", "#document-fragment":
            let parts = node.children.compactMap { child -> String? in
                let html = nodeToHTML(child, indent: indent, indentSize: indentSize, pretty: pretty)
                return html.isEmpty ? nil : html
            }
            return pretty ? parts.joined(separator: newline) : parts.joined()

        default:
            return elementToHTML(node, indent: indent, indentSize: indentSize, pretty: pretty)
        }
    }

    private static func elementToHTML(_ node: Node, indent: Int, indentSize: Int, pretty: Bool) -> String {
        let prefix = pretty ? String(repeating: " ", count: indent * indentSize) : ""
        let newline = pretty ? "\n" : ""

        let openTag = serializeStartTag(node.name, attrs: node.attrs)

        if VOID_ELEMENTS.contains(node.name) {
            return "\(prefix)\(openTag)"
        }

        // Get children (or template content for template elements)
        let children: [Node]
        if node.name == "template" && (node.namespace == nil || node.namespace == .html),
           let templateContent = node.templateContent {
            children = templateContent.children
        } else {
            children = node.children
        }

        if children.isEmpty {
            return "\(prefix)\(openTag)</\(node.name)>"
        }

        // Check if all children are text
        let allText = children.allSatisfy { $0.name == "#text" }
        if allText && pretty {
            let text = node.toText(separator: "", strip: false)
            return "\(prefix)\(openTag)\(escapeText(text))</\(node.name)>"
        }

        var parts = ["\(prefix)\(openTag)"]
        for child in children {
            let childHTML = nodeToHTML(child, indent: indent + 1, indentSize: indentSize, pretty: pretty)
            if !childHTML.isEmpty {
                parts.append(childHTML)
            }
        }
        parts.append("\(prefix)</\(node.name)>")

        return pretty ? parts.joined(separator: newline) : parts.joined()
    }

    private static func serializeStartTag(_ name: String, attrs: [String: String]) -> String {
        var parts = ["<", name]

        for (key, value) in attrs.sorted(by: { $0.key < $1.key }) {
            if value.isEmpty {
                parts.append(" \(key)")
            } else if canUnquoteAttrValue(value) {
                parts.append(" \(key)=\(escapeAttr(value))")
            } else {
                let quote = chooseAttrQuote(value)
                let escaped = escapeAttrValue(value, quote: quote)
                parts.append(" \(key)=\(quote)\(escaped)\(quote)")
            }
        }

        parts.append(">")
        return parts.joined()
    }

    private static func escapeText(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }

    private static func escapeAttr(_ value: String) -> String {
        return value.replacingOccurrences(of: "&", with: "&amp;")
    }

    private static func escapeAttrValue(_ value: String, quote: Character) -> String {
        var result = value.replacingOccurrences(of: "&", with: "&amp;")
        if quote == "\"" {
            result = result.replacingOccurrences(of: "\"", with: "&quot;")
        } else {
            result = result.replacingOccurrences(of: "'", with: "&#39;")
        }
        return result
    }

    private static func chooseAttrQuote(_ value: String) -> Character {
        if value.contains("\"") && !value.contains("'") {
            return "'"
        }
        return "\""
    }

    private static func canUnquoteAttrValue(_ value: String) -> Bool {
        for ch in value {
            if ch == ">" || ch == "\"" || ch == "'" || ch == "=" {
                return false
            }
            if ch == " " || ch == "\t" || ch == "\n" || ch == "\u{0C}" || ch == "\r" {
                return false
            }
        }
        return true
    }
}

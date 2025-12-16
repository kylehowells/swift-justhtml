// Serialize.swift - HTML serialization utilities

import Foundation

public enum Serialize {
    // MARK: - Test Format (html5lib-tests)

    /// Serialize node to html5lib test format
    public static func toTestFormat(_ node: Node) -> String {
        if node.name == "#document" {
            return node.children.map { nodeToTestFormat($0, indent: 0) }.joined(separator: "\n")
        }
        if node.name == "#document-fragment" {
            // For fragment parsing, the html element is a wrapper - output its children
            if let htmlElement = node.children.first(where: { $0.name == "html" }) {
                return htmlElement.children.map { nodeToTestFormat($0, indent: 0) }.joined(separator: "\n")
            }
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
        // Note: Foreign attributes are already adjusted during parsing (e.g., xml:lang -> xml lang)
        let sortedAttrs = node.attrs.sorted { $0.key < $1.key }
        for (name, value) in sortedAttrs {
            let attrPadding = String(repeating: " ", count: indent + 2)
            lines.append("| \(attrPadding)\(name)=\"\(value)\"")
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

    // MARK: - Markdown Serialization

    /// Serialize node to Markdown (GitHub-Flavored Markdown subset)
    public static func toMarkdown(_ node: Node) -> String {
        var context = MarkdownContext()
        collectMarkdown(node, context: &context)
        return context.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct MarkdownContext {
        var output: String = ""
        var inPreformatted: Bool = false
        var listStack: [ListInfo] = []
        var pendingNewlines: Int = 0

        struct ListInfo {
            var ordered: Bool
            var index: Int = 1
        }

        mutating func addText(_ text: String) {
            if pendingNewlines > 0 && !output.isEmpty {
                output += String(repeating: "\n", count: pendingNewlines)
                pendingNewlines = 0
            }
            output += text
        }

        mutating func addNewlines(_ count: Int) {
            pendingNewlines = max(pendingNewlines, count)
        }

        mutating func flushNewlines() {
            if pendingNewlines > 0 && !output.isEmpty {
                output += String(repeating: "\n", count: pendingNewlines)
            }
            pendingNewlines = 0  // Always reset, even if we didn't flush
        }
    }

    private static func collectMarkdown(_ node: Node, context: inout MarkdownContext) {
        switch node.name {
        case "#document", "#document-fragment":
            for child in node.children {
                collectMarkdown(child, context: &context)
            }

        case "#text":
            if case .text(let text) = node.data {
                if context.inPreformatted {
                    context.addText(text)
                } else {
                    // Collapse whitespace
                    let collapsed = collapseWhitespace(text)
                    if !collapsed.isEmpty {
                        context.addText(collapsed)
                    }
                }
            }

        case "#comment":
            // Comments are ignored in markdown
            break

        case "!doctype":
            // Doctype is ignored
            break

        case "html", "head", "body":
            for child in node.children {
                collectMarkdown(child, context: &context)
            }

        case "title", "style", "script", "noscript", "template":
            // Skip these elements
            break

        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(node.name.dropFirst()))!
            context.addNewlines(2)
            context.flushNewlines()
            context.addText(String(repeating: "#", count: level) + " ")
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addNewlines(2)

        case "p":
            context.addNewlines(2)
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addNewlines(2)

        case "br":
            context.addText("  \n")

        case "hr":
            context.addNewlines(2)
            context.flushNewlines()
            context.addText("---")
            context.addNewlines(2)

        case "strong", "b":
            context.addText("**")
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addText("**")

        case "em", "i":
            context.addText("*")
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addText("*")

        case "code":
            if !context.inPreformatted {
                context.addText("`")
                for child in node.children {
                    collectMarkdown(child, context: &context)
                }
                context.addText("`")
            } else {
                for child in node.children {
                    collectMarkdown(child, context: &context)
                }
            }

        case "pre":
            context.addNewlines(2)
            context.flushNewlines()
            context.addText("```\n")
            let wasPreformatted = context.inPreformatted
            context.inPreformatted = true
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.inPreformatted = wasPreformatted
            if !context.output.hasSuffix("\n") {
                context.addText("\n")
            }
            context.addText("```")
            context.addNewlines(2)

        case "blockquote":
            context.addNewlines(2)
            // Process children and prefix each line with >
            var innerContext = MarkdownContext()
            for child in node.children {
                collectMarkdown(child, context: &innerContext)
            }
            let inner = innerContext.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let quoted = inner.split(separator: "\n", omittingEmptySubsequences: false)
                .map { "> \($0)" }
                .joined(separator: "\n")
            context.flushNewlines()
            context.addText(quoted)
            context.addNewlines(2)

        case "a":
            let href = node.attrs["href"] ?? ""
            context.addText("[")
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addText("](\(href))")

        case "img":
            let src = node.attrs["src"] ?? ""
            let alt = node.attrs["alt"] ?? ""
            context.addText("![\(alt)](\(src))")

        case "ul":
            context.addNewlines(2)
            context.listStack.append(MarkdownContext.ListInfo(ordered: false))
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.listStack.removeLast()
            context.addNewlines(2)

        case "ol":
            context.addNewlines(2)
            context.listStack.append(MarkdownContext.ListInfo(ordered: true))
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.listStack.removeLast()
            context.addNewlines(2)

        case "li":
            context.addNewlines(1)
            context.flushNewlines()
            let indent = String(repeating: "  ", count: max(0, context.listStack.count - 1))
            if var listInfo = context.listStack.last {
                if listInfo.ordered {
                    context.addText("\(indent)\(listInfo.index). ")
                    listInfo.index += 1
                    context.listStack[context.listStack.count - 1] = listInfo
                } else {
                    context.addText("\(indent)- ")
                }
            } else {
                context.addText("- ")
            }
            for child in node.children {
                collectMarkdown(child, context: &context)
            }

        case "table":
            context.addNewlines(2)
            convertTable(node, context: &context)
            context.addNewlines(2)

        case "div", "section", "article", "main", "header", "footer", "nav", "aside":
            context.addNewlines(2)
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addNewlines(2)

        case "span":
            for child in node.children {
                collectMarkdown(child, context: &context)
            }

        case "del", "s", "strike":
            context.addText("~~")
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
            context.addText("~~")

        default:
            // Unknown element - just process children
            for child in node.children {
                collectMarkdown(child, context: &context)
            }
        }
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result = ""
        var lastWasWhitespace = false
        for ch in text {
            if ch.isWhitespace {
                if !lastWasWhitespace && !result.isEmpty {
                    result.append(" ")
                    lastWasWhitespace = true
                }
            } else {
                result.append(ch)
                lastWasWhitespace = false
            }
        }
        return result
    }

    private static func convertTable(_ table: Node, context: inout MarkdownContext) {
        var rows: [[String]] = []

        // Find rows (handle thead, tbody, tr directly under table)
        func findRows(_ node: Node) {
            for child in node.children {
                if child.name == "tr" {
                    var cells: [String] = []
                    for cell in child.children {
                        if cell.name == "td" || cell.name == "th" {
                            var cellContext = MarkdownContext()
                            for cellChild in cell.children {
                                collectMarkdown(cellChild, context: &cellContext)
                            }
                            cells.append(cellContext.output.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                    if !cells.isEmpty {
                        rows.append(cells)
                    }
                } else if child.name == "thead" || child.name == "tbody" || child.name == "tfoot" {
                    findRows(child)
                }
            }
        }

        findRows(table)

        guard !rows.isEmpty else { return }

        // Determine column count
        let columnCount = rows.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return }

        // Normalize rows to have same column count
        let normalizedRows = rows.map { row -> [String] in
            var r = row
            while r.count < columnCount {
                r.append("")
            }
            return r
        }

        // Calculate column widths
        var colWidths = Array(repeating: 3, count: columnCount)  // minimum width of 3 for ---
        for row in normalizedRows {
            for (i, cell) in row.enumerated() {
                colWidths[i] = max(colWidths[i], cell.count)
            }
        }

        context.flushNewlines()

        // Output header row (first row)
        let headerRow = normalizedRows[0]
        context.addText("| ")
        context.addText(headerRow.enumerated().map { (i, cell) in
            cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
        }.joined(separator: " | "))
        context.addText(" |")
        context.addNewlines(1)
        context.flushNewlines()

        // Output separator row
        context.addText("| ")
        context.addText(colWidths.map { String(repeating: "-", count: $0) }.joined(separator: " | "))
        context.addText(" |")
        context.addNewlines(1)

        // Output data rows
        for row in normalizedRows.dropFirst() {
            context.flushNewlines()
            context.addText("| ")
            context.addText(row.enumerated().map { (i, cell) in
                cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
            }.joined(separator: " | "))
            context.addText(" |")
            context.addNewlines(1)
        }
    }
}

// TreeBuilder.swift - HTML5 tree construction algorithm

import Foundation

/// Fragment context for parsing HTML fragments
public struct FragmentContext {
    public let tagName: String
    public let namespace: Namespace?

    public init(_ tagName: String, namespace: Namespace? = nil) {
        self.tagName = tagName
        self.namespace = namespace
    }
}

/// Insertion modes for the tree builder
public enum InsertionMode {
    case initial
    case beforeHtml
    case beforeHead
    case inHead
    case inHeadNoscript
    case afterHead
    case inBody
    case text
    case inTable
    case inTableText
    case inCaption
    case inColumnGroup
    case inTableBody
    case inRow
    case inCell
    case inSelect
    case inSelectInTable
    case inTemplate
    case afterBody
    case inFrameset
    case afterFrameset
    case afterAfterBody
    case afterAfterFrameset
}

/// Tree builder that constructs DOM from tokens
public final class TreeBuilder: TokenSink {
    // Document root
    private var document: Node

    // Stack of open elements
    private var openElements: [Node] = []

    // Active formatting elements
    private var activeFormattingElements: [Node?] = []  // nil = marker

    // Current insertion mode
    private var insertionMode: InsertionMode = .initial
    private var originalInsertionMode: InsertionMode = .initial

    // Template insertion mode stack
    private var templateInsertionModes: [InsertionMode] = []

    // Head and body element references
    private var headElement: Node?
    private var bodyElement: Node?

    // Form element pointer
    private var formElement: Node?

    // Fragment context
    private let fragmentContext: FragmentContext?
    private var contextElement: Node?

    // Flags
    private var framesetOk: Bool = true
    private var skipNextNewline: Bool = false  // For pre/listing/textarea leading newline
    private var scripting: Bool = false
    private var iframeSrcdoc: Bool = false
    private var fosterParentingEnabled: Bool = false

    // Pending table character tokens
    private var pendingTableCharacterTokens: String = ""

    // Error collection
    public var errors: [ParseError] = []
    private var collectErrors: Bool

    // Reference to tokenizer for switching states
    public weak var tokenizer: Tokenizer?

    /// Current namespace of the current element (for tokenizer state switching)
    public var currentNamespace: Namespace? {
        guard let currentNode = openElements.last else { return nil }
        return currentNode.namespace
    }

    public init(
        fragmentContext: FragmentContext? = nil,
        iframeSrcdoc: Bool = false,
        collectErrors: Bool = false,
        scripting: Bool = false
    ) {
        self.fragmentContext = fragmentContext
        self.iframeSrcdoc = iframeSrcdoc
        self.collectErrors = collectErrors
        self.scripting = scripting

        if fragmentContext != nil {
            self.document = Node(name: "#document-fragment")
        } else {
            self.document = Node(name: "#document")
        }

        // Set up fragment parsing context per WHATWG spec
        if let ctx = fragmentContext {
            // Create context element (virtual, not part of the tree)
            let ctxElement = Node(name: ctx.tagName, namespace: ctx.namespace ?? .html)
            self.contextElement = ctxElement

            // Create root html element and push onto stack (step 5-7 of fragment algorithm)
            let htmlElement = Node(name: "html", namespace: .html)
            document.appendChild(htmlElement)
            openElements.append(htmlElement)

            // For template context, push inTemplate onto template insertion modes
            if ctx.tagName == "template" {
                templateInsertionModes.append(.inTemplate)
            }

            // Reset insertion mode based on context element
            resetInsertionModeForFragment()
        }
    }

    /// Reset insertion mode specifically for fragment parsing (empty open elements stack)
    private func resetInsertionModeForFragment() {
        guard let ctx = contextElement else {
            insertionMode = .inBody
            return
        }

        switch ctx.name {
        case "select":
            insertionMode = .inSelect
        case "td", "th":
            insertionMode = .inBody  // For fragment parsing, treat as inBody
        case "tr":
            insertionMode = .inRow
        case "tbody", "thead", "tfoot":
            insertionMode = .inTableBody
        case "caption":
            insertionMode = .inCaption
        case "colgroup":
            insertionMode = .inColumnGroup
        case "table":
            insertionMode = .inTable
        case "template":
            insertionMode = .inTemplate
        case "head":
            insertionMode = .inBody  // For fragment parsing, treat as inBody
        case "body":
            insertionMode = .inBody
        case "frameset":
            insertionMode = .inFrameset
        case "html":
            insertionMode = .beforeHead
        default:
            insertionMode = .inBody
        }
    }

    /// Finish parsing and return the root
    public func finish() -> Node {
        return document
    }

    // MARK: - TokenSink

    public func processToken(_ token: Token) {
        switch token {
        case .character(let text):
            processCharacters(text)
        case .startTag(let name, let attrs, let selfClosing):
            processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
        case .endTag(let name):
            processEndTag(name: name)
        case .comment(let text):
            processComment(text)
        case .doctype(let doctype):
            processDoctype(doctype)
        case .eof:
            processEOF()
        }
    }

    // MARK: - Token Processing

    private func processCharacters(_ text: String) {
        for ch in text {
            processCharacter(ch)
        }
    }

    private func processCharacter(_ ch: Character) {
        // Skip first newline after pre/listing/textarea
        if skipNextNewline {
            skipNextNewline = false
            if ch == "\n" {
                return
            }
        }

        // HTML integration points (MathML text integration points and SVG HTML integration points)
        // process characters as HTML but should NOT foster-parent (insert directly into the element)
        // Check this BEFORE foreign content check since shouldProcessInForeignContent returns true for math namespace
        if isInMathMLTextIntegrationPoint() || isInSVGHtmlIntegrationPoint() {
            if ch == "\0" {
                emitError("unexpected-null-character")
            } else if isWhitespace(ch) {
                reconstructActiveFormattingElements()
                insertCharacter(ch)
            } else {
                reconstructActiveFormattingElements()
                insertCharacter(ch)
                framesetOk = false
            }
            return
        }

        // Check for foreign content - process characters according to foreign content rules
        if shouldProcessInForeignContent() {
            if ch == "\0" {
                emitError("unexpected-null-character")
                insertCharacter("\u{FFFD}")
            } else {
                insertCharacter(ch)
                if !isWhitespace(ch) {
                    framesetOk = false
                }
            }
            return
        }

        switch insertionMode {
        case .initial:
            if isWhitespace(ch) {
                // Ignore
            } else {
                insertionMode = .beforeHtml
                processCharacter(ch)
            }

        case .beforeHtml:
            if isWhitespace(ch) {
                // Ignore
            } else {
                insertHtmlElement()
                insertionMode = .beforeHead
                processCharacter(ch)
            }

        case .beforeHead:
            if isWhitespace(ch) {
                // Ignore
            } else {
                insertHeadElement()
                insertionMode = .inHead
                processCharacter(ch)
            }

        case .inHead:
            if isWhitespace(ch) {
                insertCharacter(ch)
            } else {
                // Act as if </head> was seen
                popCurrentElement()  // head
                insertionMode = .afterHead
                processCharacter(ch)
            }

        case .inHeadNoscript:
            if isWhitespace(ch) {
                insertCharacter(ch)
            } else {
                // Pop noscript and reprocess
                emitError("unexpected-char")
                popCurrentElement()
                insertionMode = .inHead
                processCharacter(ch)
            }

        case .afterHead:
            if isWhitespace(ch) {
                insertCharacter(ch)
            } else {
                insertBodyElement()
                insertionMode = .inBody
                processCharacter(ch)
            }

        case .inBody:
            if ch == "\0" {
                emitError("unexpected-null-character")
            } else if isWhitespace(ch) {
                reconstructActiveFormattingElements()
                insertCharacter(ch)
            } else {
                reconstructActiveFormattingElements()
                insertCharacter(ch)
                framesetOk = false
            }

        case .text:
            insertCharacter(ch)

        case .afterBody:
            if isWhitespace(ch) {
                // Process as in body
                insertCharacter(ch)
            } else {
                emitError("unexpected-char-after-body")
                insertionMode = .inBody
                processCharacter(ch)
            }

        case .afterAfterBody:
            if isWhitespace(ch) {
                // Process as in body
                insertCharacter(ch)
            } else {
                emitError("unexpected-char-after-body")
                insertionMode = .inBody
                processCharacter(ch)
            }

        case .inFrameset:
            if isWhitespace(ch) {
                insertCharacter(ch)
            } else if ch == "\0" {
                emitError("unexpected-null-character")
            } else {
                emitError("unexpected-char-in-frameset")
                // Ignore
            }

        case .afterFrameset:
            if isWhitespace(ch) {
                insertCharacter(ch)
            } else if ch == "\0" {
                emitError("unexpected-null-character")
            } else {
                emitError("unexpected-char-after-frameset")
                // Ignore
            }

        case .afterAfterFrameset:
            if isWhitespace(ch) {
                // Process as in body
                insertCharacter(ch)
            } else if ch == "\0" {
                emitError("unexpected-null-character")
            } else {
                emitError("unexpected-char-after-frameset")
                // Ignore
            }

        case .inColumnGroup:
            if isWhitespace(ch) {
                insertCharacter(ch)
            } else {
                // Non-whitespace: pop colgroup and reprocess in inTable
                if currentNode?.name == "colgroup" {
                    popCurrentElement()
                    insertionMode = .inTable
                    processCharacter(ch)
                } else {
                    emitError("unexpected-char-in-column-group")
                }
            }

        case .inTable, .inTableBody, .inRow:
            if ch == "\0" {
                emitError("unexpected-null-character")
            } else if isWhitespace(ch) {
                // Whitespace in table context: insert into current node
                insertCharacter(ch)
            } else {
                // Non-whitespace in table context: foster parent
                emitError("unexpected-char-in-table")
                fosterParentingEnabled = true
                // Process using inBody rules with foster parenting
                reconstructActiveFormattingElements()
                insertCharacter(ch)
                framesetOk = false
                fosterParentingEnabled = false
            }

        case .inCell, .inCaption:
            // Process using inBody rules
            if ch == "\0" {
                emitError("unexpected-null-character")
            } else if isWhitespace(ch) {
                reconstructActiveFormattingElements()
                insertCharacter(ch)
            } else {
                reconstructActiveFormattingElements()
                insertCharacter(ch)
                framesetOk = false
            }

        case .inSelect, .inSelectInTable:
            // Characters in select go directly into the select
            if ch == "\0" {
                emitError("unexpected-null-character")
            } else {
                insertCharacter(ch)
            }

        default:
            insertCharacter(ch)
        }
    }

    private func processStartTag(name: String, attrs: [String: String], selfClosing: Bool) {
        // Check for foreign content processing
        if shouldProcessInForeignContent() {
            if processForeignContentStartTag(name: name, attrs: attrs, selfClosing: selfClosing) {
                return  // Handled by foreign content rules
            }
            // Fall through to normal processing if breakout element
        }

        switch insertionMode {
        case .initial:
            insertionMode = .beforeHtml
            processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)

        case .beforeHtml:
            if name == "html" {
                let element = createElement(name: name, namespace: .html, attrs: attrs)
                document.appendChild(element)
                openElements.append(element)
                insertionMode = .beforeHead
            } else {
                insertHtmlElement()
                insertionMode = .beforeHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .beforeHead:
            if name == "html" {
                // Merge attributes
                if let html = openElements.first {
                    for (key, value) in attrs where html.attrs[key] == nil {
                        html.attrs[key] = value
                    }
                }
            } else if name == "head" {
                let element = insertElement(name: name, attrs: attrs)
                headElement = element
                insertionMode = .inHead
            } else {
                insertHeadElement()
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inHead:
            if name == "html" {
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if ["base", "basefont", "bgsound", "link", "meta"].contains(name) {
                _ = insertElement(name: name, attrs: attrs)
                popCurrentElement()
            } else if name == "title" {
                parseRCDATA(name: name, attrs: attrs)
            } else if name == "noscript" {
                if scripting {
                    parseRawtext(name: name, attrs: attrs)
                } else {
                    _ = insertElement(name: name, attrs: attrs)
                    insertionMode = .inHeadNoscript
                }
            } else if ["noframes", "style"].contains(name) {
                parseRawtext(name: name, attrs: attrs)
            } else if name == "script" {
                parseRawtext(name: name, attrs: attrs)
            } else if name == "template" {
                // Insert template element
                let element = insertElement(name: name, attrs: attrs)
                // Create content document fragment
                element.templateContent = Node(name: "#document-fragment")
                // Push onto template modes stack
                templateInsertionModes.append(.inTemplate)
                insertionMode = .inTemplate
            } else if name == "head" {
                emitError("unexpected-start-tag")
            } else {
                popCurrentElement()  // head
                insertionMode = .afterHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inHeadNoscript:
            if name == "html" {
                // Process using in body rules (merge attributes)
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if ["basefont", "bgsound", "link", "meta", "noframes", "style"].contains(name) {
                // Process using in head rules
                let savedMode = insertionMode
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                // If parseRawtext switched to text mode, update originalInsertionMode
                if insertionMode == .text {
                    originalInsertionMode = savedMode
                } else {
                    insertionMode = savedMode
                }
            } else if ["head", "noscript"].contains(name) {
                emitError("unexpected-start-tag")
            } else {
                // Pop noscript and reprocess
                emitError("unexpected-start-tag")
                popCurrentElement()
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .afterHead:
            if name == "html" {
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if name == "body" {
                let element = insertElement(name: name, attrs: attrs)
                bodyElement = element
                framesetOk = false
                insertionMode = .inBody
            } else if name == "frameset" {
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inFrameset
            } else if ["base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"].contains(name) {
                emitError("unexpected-start-tag")
                if let head = headElement {
                    openElements.append(head)
                }
                // Process using "in head" rules
                let savedMode = insertionMode
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                // If parseRawtext/parseRCDATA switched to .text mode, update originalInsertionMode
                // so the end tag returns to afterHead, not inHead
                // Also don't reset if template set us to inTemplate mode
                if insertionMode == .text {
                    originalInsertionMode = savedMode
                } else if insertionMode != .inTemplate {
                    insertionMode = savedMode
                }
                if let idx = openElements.lastIndex(where: { $0 === headElement }) {
                    openElements.remove(at: idx)
                }
            } else if name == "head" {
                emitError("unexpected-start-tag")
            } else {
                insertBodyElement()
                insertionMode = .inBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inBody:
            processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)

        case .text:
            // Should not happen
            break

        case .afterBody:
            if name == "html" {
                // Merge attributes
                if let html = openElements.first {
                    for (key, value) in attrs where html.attrs[key] == nil {
                        html.attrs[key] = value
                    }
                }
            } else {
                emitError("unexpected-start-tag-after-body")
                insertionMode = .inBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .afterAfterBody:
            if name == "html" {
                // Merge attributes
                if let html = openElements.first {
                    for (key, value) in attrs where html.attrs[key] == nil {
                        html.attrs[key] = value
                    }
                }
            } else {
                emitError("unexpected-start-tag-after-body")
                insertionMode = .inBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inTable:
            if name == "caption" {
                clearStackBackToTableContext()
                insertMarker()
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inCaption
            } else if name == "colgroup" {
                clearStackBackToTableContext()
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inColumnGroup
            } else if name == "col" {
                clearStackBackToTableContext()
                _ = insertElement(name: "colgroup", attrs: [:])
                insertionMode = .inColumnGroup
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if ["tbody", "tfoot", "thead"].contains(name) {
                clearStackBackToTableContext()
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inTableBody
            } else if ["td", "th", "tr"].contains(name) {
                clearStackBackToTableContext()
                _ = insertElement(name: "tbody", attrs: [:])
                insertionMode = .inTableBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if name == "table" {
                emitError("unexpected-start-tag-implies-end-tag")
                if hasElementInTableScope("table") {
                    popUntil("table")
                    resetInsertionMode()
                    processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                }
            } else if ["style", "script", "template"].contains(name) {
                // Process using "in head" rules
                let savedMode = insertionMode
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .text {
                    originalInsertionMode = savedMode
                } else if insertionMode != .inTemplate {
                    // Don't restore if we're now in template mode
                    insertionMode = savedMode
                }
            } else if name == "input" {
                if attrs["type"]?.lowercased() == "hidden" {
                    emitError("unexpected-hidden-input-in-table")
                    _ = insertElement(name: name, attrs: attrs)
                    popCurrentElement()
                } else {
                    // Foster parenting - insert in body instead
                    emitError("unexpected-start-tag-in-table")
                    fosterParentingEnabled = true
                    processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
                    fosterParentingEnabled = false
                }
            } else if name == "form" {
                emitError("unexpected-start-tag-in-table")
                if formElement == nil && !hasElementInScope("template") {
                    let element = insertElement(name: name, attrs: attrs)
                    formElement = element
                    popCurrentElement()
                }
            } else {
                // Foster parenting - process using "in body" rules
                emitError("unexpected-start-tag-in-table")
                fosterParentingEnabled = true
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
                fosterParentingEnabled = false
            }

        case .inTableBody:
            if name == "tr" {
                clearStackBackToTableBodyContext()
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inRow
            } else if ["th", "td"].contains(name) {
                emitError("unexpected-cell-in-table-body")
                clearStackBackToTableBodyContext()
                _ = insertElement(name: "tr", attrs: [:])
                insertionMode = .inRow
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if ["caption", "col", "colgroup", "tbody", "tfoot", "thead"].contains(name) {
                if !hasElementInTableScope("tbody") && !hasElementInTableScope("thead") && !hasElementInTableScope("tfoot") {
                    emitError("unexpected-start-tag")
                    return
                }
                clearStackBackToTableBodyContext()
                popCurrentElement()
                insertionMode = .inTable
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else {
                // Process using "in table" rules
                let savedMode = insertionMode
                insertionMode = .inTable
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .inTable {
                    insertionMode = savedMode
                }
            }

        case .inRow:
            if ["th", "td"].contains(name) {
                clearStackBackToTableRowContext()
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inCell
                insertMarker()
            } else if ["caption", "col", "colgroup", "tbody", "tfoot", "thead", "tr"].contains(name) {
                if !hasElementInTableScope("tr") {
                    emitError("unexpected-start-tag")
                    return
                }
                clearStackBackToTableRowContext()
                popCurrentElement()
                insertionMode = .inTableBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else {
                // Process using "in table" rules
                let savedMode = insertionMode
                insertionMode = .inTable
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .inTable {
                    insertionMode = savedMode
                }
            }

        case .inCell:
            if ["caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"].contains(name) {
                if !hasElementInTableScope("td") && !hasElementInTableScope("th") {
                    emitError("unexpected-start-tag")
                    return
                }
                closeCell()
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else {
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inColumnGroup:
            if name == "html" {
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if name == "col" {
                _ = insertElement(name: name, attrs: attrs)
                popCurrentElement()
            } else if name == "template" {
                // Process using "in head" rules
                let savedMode = insertionMode
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .text {
                    originalInsertionMode = savedMode
                } else if insertionMode != .inTemplate {
                    insertionMode = savedMode
                }
            } else {
                // Close colgroup and reprocess
                if currentNode?.name == "colgroup" {
                    popCurrentElement()
                    insertionMode = .inTable
                    processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                } else {
                    emitError("unexpected-start-tag")
                }
            }

        case .inCaption:
            // Table structure tags close the caption
            if ["caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"].contains(name) {
                if !hasElementInTableScope("caption") {
                    emitError("unexpected-start-tag")
                    return
                }
                generateImpliedEndTags()
                if currentNode?.name != "caption" {
                    emitError("end-tag-too-early")
                }
                popUntil("caption")
                clearActiveFormattingElementsToLastMarker()
                insertionMode = .inTable
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else {
                // Process using inBody rules
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inFrameset:
            if name == "html" {
                // Merge attributes with existing html element
                if let html = openElements.first {
                    for (key, value) in attrs where html.attrs[key] == nil {
                        html.attrs[key] = value
                    }
                }
            } else if name == "frameset" {
                _ = insertElement(name: name, attrs: attrs)
            } else if name == "frame" {
                _ = insertElement(name: name, attrs: attrs)
                popCurrentElement()
            } else if name == "noframes" {
                parseRawtext(name: name, attrs: attrs)
            } else {
                emitError("unexpected-start-tag-in-frameset")
            }

        case .afterFrameset:
            if name == "html" {
                // Merge attributes
                if let html = openElements.first {
                    for (key, value) in attrs where html.attrs[key] == nil {
                        html.attrs[key] = value
                    }
                }
            } else if name == "noframes" {
                parseRawtext(name: name, attrs: attrs)
            } else {
                emitError("unexpected-start-tag-after-frameset")
            }

        case .afterAfterFrameset:
            if name == "html" {
                // Merge attributes
                if let html = openElements.first {
                    for (key, value) in attrs where html.attrs[key] == nil {
                        html.attrs[key] = value
                    }
                }
            } else if name == "noframes" {
                parseRawtext(name: name, attrs: attrs)
            } else {
                emitError("unexpected-start-tag-after-frameset")
            }

        case .inTemplate:
            // Handle start tags in "in template" insertion mode
            if ["base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"].contains(name) {
                // Process using "in head" rules
                let savedMode = insertionMode
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .text {
                    originalInsertionMode = savedMode
                } else {
                    insertionMode = savedMode
                }
            } else if ["caption", "colgroup", "tbody", "tfoot", "thead"].contains(name) {
                // Pop template mode and push inTable
                if !templateInsertionModes.isEmpty {
                    templateInsertionModes.removeLast()
                }
                templateInsertionModes.append(.inTable)
                insertionMode = .inTable
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if name == "col" {
                // Pop template mode and push inColumnGroup
                if !templateInsertionModes.isEmpty {
                    templateInsertionModes.removeLast()
                }
                templateInsertionModes.append(.inColumnGroup)
                insertionMode = .inColumnGroup
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if name == "tr" {
                // Pop template mode and push inTableBody
                if !templateInsertionModes.isEmpty {
                    templateInsertionModes.removeLast()
                }
                templateInsertionModes.append(.inTableBody)
                insertionMode = .inTableBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if ["td", "th"].contains(name) {
                // Pop template mode and push inRow
                if !templateInsertionModes.isEmpty {
                    templateInsertionModes.removeLast()
                }
                templateInsertionModes.append(.inRow)
                insertionMode = .inRow
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else {
                // Pop template mode and push inBody
                if !templateInsertionModes.isEmpty {
                    templateInsertionModes.removeLast()
                }
                templateInsertionModes.append(.inBody)
                insertionMode = .inBody
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            }

        case .inSelect:
            if name == "html" {
                // Process using "in body" rules
                processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if name == "option" {
                if let current = currentNode, current.name == "option" {
                    popCurrentElement()
                }
                _ = insertElement(name: name, attrs: attrs)
            } else if name == "optgroup" {
                if let current = currentNode, current.name == "option" {
                    popCurrentElement()
                }
                if let current = currentNode, current.name == "optgroup" {
                    popCurrentElement()
                }
                _ = insertElement(name: name, attrs: attrs)
            } else if name == "hr" {
                if let current = currentNode, current.name == "option" {
                    popCurrentElement()
                }
                if let current = currentNode, current.name == "optgroup" {
                    popCurrentElement()
                }
                _ = insertElement(name: name, attrs: attrs)
                popCurrentElement()
            } else if name == "select" {
                emitError("unexpected-start-tag-in-select")
                if hasElementInSelectScope("select") {
                    popUntil("select")
                    resetInsertionMode()
                }
            } else if ["input", "keygen", "textarea"].contains(name) {
                emitError("unexpected-start-tag-in-select")
                if !hasElementInSelectScope("select") {
                    // Ignore the token
                    return
                }
                // In fragment parsing, if select is only the context element,
                // we conceptually close it by clearing the context and going to inBody
                let selectIsContextOnly = contextElement?.name == "select" &&
                                         !openElements.contains { $0.name == "select" }
                if selectIsContextOnly {
                    contextElement = nil
                    // Go directly to inBody without creating implicit head/body
                    insertionMode = .inBody
                } else {
                    popUntil("select")
                    resetInsertionMode()
                }
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else if ["script", "template"].contains(name) {
                // Process using "in head" rules
                let savedMode = insertionMode
                insertionMode = .inHead
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .text {
                    // Script processing set up text mode, update originalInsertionMode to return to select
                    originalInsertionMode = savedMode
                } else if insertionMode != .inTemplate {
                    // Restore unless template took us to inTemplate mode
                    insertionMode = savedMode
                }
            } else if name == "svg" {
                // Insert SVG element in SVG namespace
                let adjustedAttrs = adjustForeignAttributes(attrs, namespace: .svg)
                _ = insertElement(name: name, namespace: .svg, attrs: adjustedAttrs)
                if selfClosing {
                    popCurrentElement()
                }
            } else if name == "math" {
                // Insert MathML element in MathML namespace
                let adjustedAttrs = adjustForeignAttributes(attrs, namespace: .math)
                _ = insertElement(name: name, namespace: .math, attrs: adjustedAttrs)
                if selfClosing {
                    popCurrentElement()
                }
            } else {
                emitError("unexpected-start-tag-in-select")
            }

        case .inSelectInTable:
            // Table-related start tags close the select and reprocess
            if ["caption", "table", "tbody", "tfoot", "thead", "tr", "td", "th"].contains(name) {
                emitError("unexpected-start-tag-in-select")
                popUntil("select")
                resetInsertionMode()
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            } else {
                // Process using "in select" rules
                let savedMode = insertionMode
                insertionMode = .inSelect
                processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
                if insertionMode == .inSelect {
                    insertionMode = savedMode
                }
            }

        default:
            processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
        }
    }

    private func processStartTagInBody(name: String, attrs: [String: String], selfClosing: Bool) {
        if name == "html" {
            emitError("unexpected-start-tag")
            // Don't merge attributes if inside a template
            if templateInsertionModes.isEmpty, let html = openElements.first {
                for (key, value) in attrs where html.attrs[key] == nil {
                    html.attrs[key] = value
                }
            }
        } else if ["base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template", "title"].contains(name) {
            // Process using "in head" rules
            let savedMode = insertionMode
            insertionMode = .inHead
            processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
            // If parseRawtext/parseRCDATA switched to .text mode, update originalInsertionMode
            if insertionMode == .text {
                originalInsertionMode = savedMode
            } else if insertionMode != .inTemplate {
                // Don't restore if we're now in template mode
                insertionMode = savedMode
            }
        } else if name == "body" {
            emitError("unexpected-start-tag")
            // Don't merge attributes if inside a template
            if templateInsertionModes.isEmpty,
               openElements.count >= 2, openElements[1].name == "body" {
                framesetOk = false
                for (key, value) in attrs where openElements[1].attrs[key] == nil {
                    openElements[1].attrs[key] = value
                }
            }
        } else if name == "frameset" {
            emitError("unexpected-start-tag")
            // Check conditions for allowing frameset
            if openElements.count > 1 && openElements[1].name == "body" && framesetOk {
                // Remove the body element from its parent
                if let body = openElements.count > 1 ? openElements[1] : nil {
                    body.parent?.removeChild(body)
                }
                // Pop all nodes except html
                while openElements.count > 1 {
                    popCurrentElement()
                }
                // Insert frameset
                _ = insertElement(name: name, attrs: attrs)
                insertionMode = .inFrameset
            }
            // Otherwise ignore
        } else if ["address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "main", "menu", "nav", "ol", "p", "search", "section", "summary", "ul"].contains(name) {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(name) {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            if let current = currentNode, ["h1", "h2", "h3", "h4", "h5", "h6"].contains(current.name) {
                emitError("unexpected-start-tag")
                popCurrentElement()
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if ["pre", "listing"].contains(name) {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
            framesetOk = false
            skipNextNewline = true  // Ignore first newline after pre/listing
        } else if name == "form" {
            if formElement != nil {
                emitError("unexpected-start-tag")
            } else {
                if hasElementInButtonScope("p") {
                    closePElement()
                }
                let element = insertElement(name: name, attrs: attrs)
                formElement = element
            }
        } else if name == "li" {
            framesetOk = false
            // Close any open li elements in list item scope
            for node in openElements.reversed() {
                if node.name == "li" {
                    generateImpliedEndTags(except: "li")
                    if currentNode?.name != "li" {
                        emitError("end-tag-too-early")
                    }
                    popUntil("li")
                    break
                }
                // Stop at list item scope boundary elements
                if LIST_ITEM_SCOPE_ELEMENTS.contains(node.name) {
                    break
                }
            }
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if ["dd", "dt"].contains(name) {
            framesetOk = false
            // Close any open dd or dt elements in scope
            for node in openElements.reversed() {
                if node.name == "dd" || node.name == "dt" {
                    generateImpliedEndTags(except: node.name)
                    if currentNode?.name != node.name {
                        emitError("end-tag-too-early")
                    }
                    popUntil(node.name)
                    break
                }
                // Stop at scope boundary elements
                if SCOPE_ELEMENTS.contains(node.name) ||
                   SPECIAL_ELEMENTS.contains(node.name) {
                    break
                }
            }
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if name == "plaintext" {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
            // Switch tokenizer to PLAINTEXT state
        } else if name == "button" {
            if hasElementInScope("button") {
                emitError("unexpected-start-tag")
                generateImpliedEndTags()
                popUntil("button")
            }
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
            framesetOk = false
        } else if name == "a" {
            // Check for active 'a' element and run adoption agency if found
            if hasActiveFormattingEntry("a") {
                emitError("unexpected-start-tag")
                adoptionAgency(name: "a")
                // Also remove from active formatting elements and open elements
                // (adoption agency may have already done this, but be safe)
                for i in stride(from: activeFormattingElements.count - 1, through: 0, by: -1) {
                    if let elem = activeFormattingElements[i], elem.name == "a" {
                        activeFormattingElements.remove(at: i)
                        openElements.removeAll { $0 === elem }
                        break
                    }
                }
            }
            reconstructActiveFormattingElements()
            let element = insertElement(name: name, attrs: attrs)
            pushFormattingElement(element)
        } else if name == "nobr" {
            // Special handling for nobr - must check scope BEFORE other formatting elements logic
            if hasElementInScope("nobr") {
                emitError("unexpected-start-tag-implies-end-tag")
                // Run adoption agency to close the existing nobr
                adoptionAgency(name: "nobr")
                // Explicitly remove nobr from active formatting and open elements
                for i in stride(from: activeFormattingElements.count - 1, through: 0, by: -1) {
                    if let elem = activeFormattingElements[i], elem.name == "nobr" {
                        activeFormattingElements.remove(at: i)
                        openElements.removeAll { $0 === elem }
                        break
                    }
                }
            }
            reconstructActiveFormattingElements()
            let element = insertElement(name: name, attrs: attrs)
            pushFormattingElement(element)
        } else if FORMATTING_ELEMENTS.contains(name) {
            reconstructActiveFormattingElements()
            let element = insertElement(name: name, attrs: attrs)
            pushFormattingElement(element)
        } else if ["applet", "marquee", "object"].contains(name) {
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
            insertMarker()
            framesetOk = false
        } else if name == "table" {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
            framesetOk = false
            insertionMode = .inTable
        } else if ["area", "br", "embed", "img", "keygen", "wbr"].contains(name) {
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
            popCurrentElement()
            framesetOk = false
        } else if name == "input" {
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
            popCurrentElement()
            if attrs["type"]?.lowercased() != "hidden" {
                framesetOk = false
            }
        } else if ["param", "source", "track"].contains(name) {
            _ = insertElement(name: name, attrs: attrs)
            popCurrentElement()
        } else if name == "hr" {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
            popCurrentElement()
            framesetOk = false
        } else if name == "image" {
            emitError("unexpected-start-tag")
            // Treat as "img"
            processStartTag(name: "img", attrs: attrs, selfClosing: selfClosing)
        } else if name == "textarea" {
            _ = insertElement(name: name, attrs: attrs)
            skipNextNewline = true  // Ignore first newline after textarea
            framesetOk = false
            originalInsertionMode = insertionMode
            insertionMode = .text
        } else if name == "xmp" {
            if hasElementInButtonScope("p") {
                closePElement()
            }
            reconstructActiveFormattingElements()
            framesetOk = false
            parseRawtext(name: name, attrs: attrs)
        } else if name == "iframe" {
            framesetOk = false
            parseRawtext(name: name, attrs: attrs)
        } else if name == "noembed" {
            parseRawtext(name: name, attrs: attrs)
        } else if name == "select" {
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
            framesetOk = false
            // Check if we're in a table context
            if insertionMode == .inTable || insertionMode == .inTableBody ||
               insertionMode == .inRow || insertionMode == .inCell ||
               insertionMode == .inCaption {
                insertionMode = .inSelectInTable
            } else {
                insertionMode = .inSelect
            }
        } else if ["optgroup", "option"].contains(name) {
            if currentNode?.name == "option" {
                popCurrentElement()
            }
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
        } else if ["rb", "rtc"].contains(name) {
            if hasElementInScope("ruby") {
                generateImpliedEndTags()
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if ["rp", "rt"].contains(name) {
            if hasElementInScope("ruby") {
                generateImpliedEndTags(except: "rtc")
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if name == "math" {
            reconstructActiveFormattingElements()
            let adjustedAttrs = adjustForeignAttributes(attrs, namespace: .math)
            let element = insertElement(name: name, namespace: .math, attrs: adjustedAttrs)
            if selfClosing {
                popCurrentElement()
            }
        } else if name == "svg" {
            reconstructActiveFormattingElements()
            let adjustedAttrs = adjustForeignAttributes(attrs, namespace: .svg)
            let element = insertElement(name: name, namespace: .svg, attrs: adjustedAttrs)
            if selfClosing {
                popCurrentElement()
            }
        } else if ["caption", "col", "colgroup", "frame", "head", "tbody", "td", "tfoot", "th", "thead", "tr"].contains(name) {
            emitError("unexpected-start-tag")
            // Ignore
        } else {
            reconstructActiveFormattingElements()
            _ = insertElement(name: name, attrs: attrs)
        }
    }

    private func processEndTag(name: String) {
        // Check for foreign content processing first
        // Note: For end tags, we should try to close foreign elements even when inside
        // an HTML integration point (unlike start tags which get processed as HTML)
        if hasForeignElementInStack() {
            if processForeignContentEndTag(name: name) {
                return  // Handled by foreign content rules
            }
            // Fall through to normal processing if not handled
        }

        switch insertionMode {
        case .initial:
            insertionMode = .beforeHtml
            processEndTag(name: name)

        case .beforeHtml:
            if ["head", "body", "html", "br"].contains(name) {
                insertHtmlElement()
                insertionMode = .beforeHead
                processEndTag(name: name)
            } else {
                emitError("unexpected-end-tag")
            }

        case .beforeHead:
            if ["head", "body", "html", "br"].contains(name) {
                insertHeadElement()
                insertionMode = .inHead
                processEndTag(name: name)
            } else {
                emitError("unexpected-end-tag")
            }

        case .inHead:
            if name == "head" {
                popCurrentElement()
                insertionMode = .afterHead
            } else if ["body", "html", "br"].contains(name) {
                popCurrentElement()  // head
                insertionMode = .afterHead
                processEndTag(name: name)
            } else if name == "template" {
                // Process template end tag using in body rules
                processEndTagInBody(name: name)
            } else {
                emitError("unexpected-end-tag")
            }

        case .inHeadNoscript:
            if name == "noscript" {
                popCurrentElement()
                insertionMode = .inHead
            } else if name == "br" {
                emitError("unexpected-end-tag")
                popCurrentElement()
                insertionMode = .inHead
                processEndTag(name: name)
            } else {
                emitError("unexpected-end-tag")
            }

        case .afterHead:
            if name == "body" || name == "html" || name == "br" {
                insertBodyElement()
                insertionMode = .inBody
                processEndTag(name: name)
            } else if name == "template" {
                // Process template end tag using in body rules
                processEndTagInBody(name: name)
            } else {
                emitError("unexpected-end-tag")
            }

        case .inBody:
            processEndTagInBody(name: name)

        case .text:
            if name == "script" {
                popCurrentElement()
                insertionMode = originalInsertionMode
            } else {
                popCurrentElement()
                insertionMode = originalInsertionMode
            }

        case .afterBody:
            if name == "html" {
                insertionMode = .afterAfterBody
            } else {
                emitError("unexpected-end-tag-after-body")
                insertionMode = .inBody
                processEndTag(name: name)
            }

        case .afterAfterBody:
            emitError("unexpected-end-tag-after-body")
            insertionMode = .inBody
            processEndTag(name: name)

        case .inCell:
            if ["td", "th"].contains(name) {
                if !hasElementInTableScope(name) {
                    emitError("unexpected-end-tag")
                    return
                }
                generateImpliedEndTags()
                if currentNode?.name != name {
                    emitError("end-tag-too-early")
                }
                popUntil(name)
                clearActiveFormattingElementsToLastMarker()
                insertionMode = .inRow
            } else if ["body", "caption", "col", "colgroup", "html"].contains(name) {
                emitError("unexpected-end-tag")
                // Ignore
            } else if ["table", "tbody", "tfoot", "thead", "tr"].contains(name) {
                if !hasElementInTableScope(name) {
                    emitError("unexpected-end-tag")
                    return
                }
                closeCell()
                processEndTag(name: name)
            } else {
                processEndTagInBody(name: name)
            }

        case .inRow:
            if name == "tr" {
                if !hasElementInTableScope("tr") {
                    emitError("unexpected-end-tag")
                    return
                }
                clearStackBackToTableRowContext()
                popCurrentElement()
                insertionMode = .inTableBody
            } else if name == "table" {
                if !hasElementInTableScope("tr") {
                    emitError("unexpected-end-tag")
                    return
                }
                clearStackBackToTableRowContext()
                popCurrentElement()
                insertionMode = .inTableBody
                processEndTag(name: name)
            } else if ["tbody", "tfoot", "thead"].contains(name) {
                if !hasElementInTableScope(name) {
                    emitError("unexpected-end-tag")
                    return
                }
                if !hasElementInTableScope("tr") {
                    return
                }
                clearStackBackToTableRowContext()
                popCurrentElement()
                insertionMode = .inTableBody
                processEndTag(name: name)
            } else if ["body", "caption", "col", "colgroup", "html", "td", "th"].contains(name) {
                emitError("unexpected-end-tag")
                // Ignore
            } else {
                // Process using "in table" rules
                let savedMode = insertionMode
                insertionMode = .inTable
                processEndTag(name: name)
                if insertionMode == .inTable {
                    insertionMode = savedMode
                }
            }

        case .inTableBody:
            if ["tbody", "tfoot", "thead"].contains(name) {
                if !hasElementInTableScope(name) {
                    emitError("unexpected-end-tag")
                    return
                }
                clearStackBackToTableBodyContext()
                popCurrentElement()
                insertionMode = .inTable
            } else if name == "table" {
                if !hasElementInTableScope("tbody") && !hasElementInTableScope("thead") && !hasElementInTableScope("tfoot") {
                    emitError("unexpected-end-tag")
                    return
                }
                clearStackBackToTableBodyContext()
                popCurrentElement()
                insertionMode = .inTable
                processEndTag(name: name)
            } else if ["body", "caption", "col", "colgroup", "html", "td", "th", "tr"].contains(name) {
                emitError("unexpected-end-tag")
                // Ignore
            } else {
                // Process using "in table" rules
                let savedMode = insertionMode
                insertionMode = .inTable
                processEndTag(name: name)
                if insertionMode == .inTable {
                    insertionMode = savedMode
                }
            }

        case .inColumnGroup:
            if name == "colgroup" {
                if currentNode?.name == "colgroup" {
                    popCurrentElement()
                    insertionMode = .inTable
                } else {
                    emitError("unexpected-end-tag")
                }
            } else if name == "col" {
                emitError("unexpected-end-tag")
                // Ignore
            } else if name == "template" {
                processEndTagInBody(name: name)
            } else {
                // Close colgroup and reprocess
                if currentNode?.name == "colgroup" {
                    popCurrentElement()
                    insertionMode = .inTable
                    processEndTag(name: name)
                } else {
                    emitError("unexpected-end-tag")
                }
            }

        case .inTable:
            if name == "table" {
                if !hasElementInTableScope("table") {
                    emitError("unexpected-end-tag")
                    return
                }
                popUntil("table")
                resetInsertionMode()
            } else if ["body", "caption", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr"].contains(name) {
                emitError("unexpected-end-tag")
                // Ignore
            } else if name == "template" {
                processEndTagInBody(name: name)
            } else {
                // Foster parent: process using in body rules
                emitError("unexpected-end-tag")
                fosterParentingEnabled = true
                processEndTagInBody(name: name)
                fosterParentingEnabled = false
            }

        case .inCaption:
            if name == "caption" {
                if !hasElementInTableScope("caption") {
                    emitError("unexpected-end-tag")
                    return
                }
                generateImpliedEndTags()
                if currentNode?.name != "caption" {
                    emitError("end-tag-too-early")
                }
                popUntil("caption")
                clearActiveFormattingElementsToLastMarker()
                insertionMode = .inTable
            } else if name == "table" {
                if !hasElementInTableScope("caption") {
                    emitError("unexpected-end-tag")
                    return
                }
                generateImpliedEndTags()
                if currentNode?.name != "caption" {
                    emitError("end-tag-too-early")
                }
                popUntil("caption")
                clearActiveFormattingElementsToLastMarker()
                insertionMode = .inTable
                processEndTag(name: name)
            } else if ["body", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr"].contains(name) {
                emitError("unexpected-end-tag")
                // Ignore
            } else {
                processEndTagInBody(name: name)
            }

        case .inFrameset:
            if name == "frameset" {
                if currentNode?.name == "html" {
                    emitError("unexpected-end-tag")
                    return
                }
                popCurrentElement()
                if currentNode?.name != "frameset" {
                    insertionMode = .afterFrameset
                }
            } else {
                emitError("unexpected-end-tag-in-frameset")
            }

        case .afterFrameset:
            if name == "html" {
                insertionMode = .afterAfterFrameset
            } else {
                emitError("unexpected-end-tag-after-frameset")
            }

        case .afterAfterFrameset:
            emitError("unexpected-end-tag-after-frameset")
            // Ignore

        case .inTemplate:
            // In template mode, only template end tag is processed
            if name == "template" {
                // Process using in body rules
                processEndTagInBody(name: name)
            } else {
                // All other end tags are parse errors and ignored
                emitError("unexpected-end-tag-in-template")
            }

        case .inSelect:
            if name == "optgroup" {
                // If current node is option and previous is optgroup, pop option first
                if let current = currentNode, current.name == "option",
                   openElements.count >= 2, openElements[openElements.count - 2].name == "optgroup" {
                    popCurrentElement()
                }
                if let current = currentNode, current.name == "optgroup" {
                    popCurrentElement()
                } else {
                    emitError("unexpected-end-tag")
                }
            } else if name == "option" {
                if let current = currentNode, current.name == "option" {
                    popCurrentElement()
                } else {
                    emitError("unexpected-end-tag")
                }
            } else if name == "select" {
                if !hasElementInSelectScope("select") {
                    emitError("unexpected-end-tag")
                    return
                }
                popUntil("select")
                resetInsertionMode()
            } else if name == "template" {
                processEndTagInBody(name: name)
            } else {
                emitError("unexpected-end-tag")
            }

        case .inSelectInTable:
            // Table-related end tags close the select and reprocess
            if ["caption", "table", "tbody", "tfoot", "thead", "tr", "td", "th"].contains(name) {
                emitError("unexpected-end-tag-in-select")
                if !hasElementInTableScope(name) {
                    // Ignore the token
                    return
                }
                // Close the select
                popUntil("select")
                resetInsertionMode()
                // Reprocess the end tag
                processEndTag(name: name)
            } else {
                // Process using "in select" rules
                let savedMode = insertionMode
                insertionMode = .inSelect
                processEndTag(name: name)
                if insertionMode == .inSelect {
                    insertionMode = savedMode
                }
            }

        default:
            processEndTagInBody(name: name)
        }
    }

    private func processEndTagInBody(name: String) {
        if name == "body" {
            if !hasElementInScope("body") {
                emitError("unexpected-end-tag")
                return
            }
            insertionMode = .afterBody
        } else if name == "html" {
            if !hasElementInScope("body") {
                emitError("unexpected-end-tag")
                return
            }
            insertionMode = .afterBody
            processEndTag(name: name)
        } else if ["address", "article", "aside", "blockquote", "button", "center", "details", "dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "listing", "main", "menu", "nav", "ol", "pre", "search", "section", "summary", "ul"].contains(name) {
            if !hasElementInScope(name) {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags()
            if currentNode?.name != name {
                emitError("end-tag-too-early")
            }
            popUntil(name)
        } else if name == "form" {
            let node = formElement
            formElement = nil
            if node == nil || !hasElementInScope("form") {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags()
            if currentNode !== node {
                emitError("end-tag-too-early")
            }
            if let node = node, let idx = openElements.firstIndex(where: { $0 === node }) {
                openElements.remove(at: idx)
            }
        } else if name == "p" {
            if !hasElementInButtonScope("p") {
                emitError("unexpected-end-tag")
                _ = insertElement(name: "p", attrs: [:])
            }
            closePElement()
        } else if name == "li" {
            if !hasElementInListItemScope("li") {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags(except: "li")
            if currentNode?.name != "li" {
                emitError("end-tag-too-early")
            }
            popUntil("li")
        } else if ["dd", "dt"].contains(name) {
            if !hasElementInScope(name) {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags(except: name)
            if currentNode?.name != name {
                emitError("end-tag-too-early")
            }
            popUntil(name)
        } else if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(name) {
            if !hasElementInScope("h1") && !hasElementInScope("h2") && !hasElementInScope("h3") &&
               !hasElementInScope("h4") && !hasElementInScope("h5") && !hasElementInScope("h6") {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags()
            if currentNode?.name != name {
                emitError("end-tag-too-early")
            }
            // Pop until h1-h6
            while let current = currentNode {
                popCurrentElement()
                if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(current.name) {
                    break
                }
            }
        } else if FORMATTING_ELEMENTS.contains(name) || name == "a" {
            // Run adoption agency algorithm (simplified)
            adoptionAgency(name: name)
        } else if ["applet", "marquee", "object"].contains(name) {
            if !hasElementInScope(name) {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags()
            if currentNode?.name != name {
                emitError("end-tag-too-early")
            }
            popUntil(name)
            clearActiveFormattingElementsToLastMarker()
        } else if name == "br" {
            emitError("unexpected-end-tag")
            // Treat as <br>
            reconstructActiveFormattingElements()
            _ = insertElement(name: "br", attrs: [:])
            popCurrentElement()
            framesetOk = false
        } else if name == "template" {
            // Handle template end tag
            // Per spec: check if template is on the stack of open elements (not in scope!)
            let hasTemplate = openElements.contains { $0.name == "template" }
            if !hasTemplate {
                emitError("unexpected-end-tag")
                return
            }
            generateImpliedEndTags()
            if currentNode?.name != "template" {
                emitError("end-tag-too-early")
            }
            // Pop elements until template
            while let current = currentNode {
                let name = current.name
                popCurrentElement()
                if name == "template" {
                    break
                }
            }
            // Clear active formatting elements to last marker
            while let last = activeFormattingElements.last {
                activeFormattingElements.removeLast()
                if last == nil {  // marker
                    break
                }
            }
            // Pop template insertion mode
            if !templateInsertionModes.isEmpty {
                templateInsertionModes.removeLast()
            }
            // Reset insertion mode
            resetInsertionMode()
        } else {
            // Any other end tag
            anyOtherEndTag(name: name)
        }
    }

    private func anyOtherEndTag(name: String) {
        for i in stride(from: openElements.count - 1, through: 0, by: -1) {
            let node = openElements[i]
            if node.name == name {
                generateImpliedEndTags(except: name)
                if currentNode?.name != name {
                    emitError("end-tag-too-early")
                }
                while openElements.count > i {
                    popCurrentElement()
                }
                return
            }
            if SPECIAL_ELEMENTS.contains(node.name) {
                emitError("unexpected-end-tag")
                return
            }
        }
    }

    private func processComment(_ text: String) {
        let comment = Node(name: "#comment", data: .comment(text))

        switch insertionMode {
        case .initial, .beforeHtml:
            document.appendChild(comment)
        case .afterAfterBody, .afterAfterFrameset:
            // In fragment parsing, append to html element; otherwise to document
            if fragmentContext != nil, let html = openElements.first {
                html.appendChild(comment)
            } else {
                document.appendChild(comment)
            }
        default:
            // Use adjustedInsertionTarget to properly handle template content
            adjustedInsertionTarget.appendChild(comment)
        }
    }

    private func processDoctype(_ doctype: Doctype) {
        if insertionMode != .initial {
            emitError("unexpected-doctype")
            return
        }

        let node = Node(name: "!doctype", data: .doctype(doctype))
        document.appendChild(node)
        insertionMode = .beforeHtml
    }

    private func processEOF() {
        // Generate implied end tags and finish
        switch insertionMode {
        case .initial:
            insertionMode = .beforeHtml
            processEOF()
        case .beforeHtml:
            insertHtmlElement()
            insertionMode = .beforeHead
            processEOF()
        case .beforeHead:
            insertHeadElement()
            insertionMode = .inHead
            processEOF()
        case .inHead:
            popCurrentElement()
            insertionMode = .afterHead
            processEOF()
        case .inHeadNoscript:
            emitError("eof-in-noscript")
            popCurrentElement()  // noscript
            insertionMode = .inHead
            processEOF()
        case .afterHead:
            insertBodyElement()
            insertionMode = .inBody
            processEOF()
        case .text:
            // EOF in text mode (script/rawtext)
            emitError("eof-in-script-html-comment-like-text")
            popCurrentElement()
            insertionMode = originalInsertionMode
            processEOF()
        case .inTable, .inTableBody, .inRow, .inCell, .inCaption, .inColumnGroup:
            // EOF in table contexts - pop elements and process EOF
            emitError("eof-in-table")
            // For in-table modes, we should process EOF which will handle generating implied tags
            insertionMode = .inBody
            processEOF()
        case .inTemplate:
            // EOF in template - pop template and close
            // Check if template is in the stack (not in scope - table breaks scope but template is still there)
            let hasTemplate = openElements.contains { $0.name == "template" }
            if !hasTemplate {
                // No template in stack - stop processing
                break
            }
            emitError("eof-in-template")
            popUntil("template")
            clearActiveFormattingElementsToLastMarker()
            if !templateInsertionModes.isEmpty {
                templateInsertionModes.removeLast()
            }
            resetInsertionMode()
            processEOF()
        case .inBody, .inSelect, .inSelectInTable, .inFrameset, .afterBody, .afterFrameset, .afterAfterBody, .afterAfterFrameset, .inTableText:
            // Per spec: if template insertion modes stack is not empty, process using in template rules
            if !templateInsertionModes.isEmpty {
                insertionMode = .inTemplate
                processEOF()
            }
            // Otherwise stop parsing (break)
        }
    }

    // MARK: - Element Insertion

    private var currentNode: Node? {
        openElements.last
    }

    /// Returns the adjusted insertion target, redirecting to templateContent for template elements
    private var adjustedInsertionTarget: Node {
        guard let current = currentNode else { return document }
        // If current node is a template, insert into its content document fragment
        if current.name == "template", let content = current.templateContent {
            return content
        }
        return current
    }

    private func createElement(name: String, namespace: Namespace = .html, attrs: [String: String]) -> Node {
        return Node(name: name, namespace: namespace, attrs: attrs)
    }

    /// Adjust attributes for foreign content (SVG/MathML)
    private func adjustForeignAttributes(_ attrs: [String: String], namespace: Namespace) -> [String: String] {
        var adjusted: [String: String] = [:]
        for (name, value) in attrs {
            let lowercaseName = name.lowercased()
            var adjustedName = name

            // Foreign attribute adjustments (xmlns, xlink, xml namespace prefixes)
            // These apply to both SVG and MathML
            if let foreignAdjusted = FOREIGN_ATTRIBUTE_ADJUSTMENTS[lowercaseName] {
                adjustedName = foreignAdjusted
            }
            // SVG attribute adjustments
            else if namespace == .svg {
                if let svgAdjusted = SVG_ATTRIBUTE_ADJUSTMENTS[lowercaseName] {
                    adjustedName = svgAdjusted
                }
            }
            // MathML attribute adjustments
            else if namespace == .math {
                if let mathAdjusted = MATHML_ATTRIBUTE_ADJUSTMENTS[lowercaseName] {
                    adjustedName = mathAdjusted
                }
            }

            adjusted[adjustedName] = value
        }
        return adjusted
    }

    @discardableResult
    private func insertElement(name: String, namespace: Namespace = .html, attrs: [String: String]) -> Node {
        let element = createElement(name: name, namespace: namespace, attrs: attrs)
        insertNode(element)
        openElements.append(element)
        return element
    }

    private func insertNode(_ node: Node) {
        // Per spec: foster parenting only applies when the target is a table element
        // (table, tbody, tfoot, thead, tr). If we're inside a formatting element,
        // insert normally into that element.
        if fosterParentingEnabled {
            let target = adjustedInsertionTarget
            if ["table", "tbody", "tfoot", "thead", "tr"].contains(target.name) {
                fosterParentNode(node)
            } else {
                target.appendChild(node)
            }
        } else {
            adjustedInsertionTarget.appendChild(node)
        }
    }

    /// Foster parent insertion - used when we need to insert nodes outside of a table
    private func fosterParentNode(_ node: Node) {
        // Find last table and last template in the stack
        var lastTableIndex: Int? = nil
        var lastTemplateIndex: Int? = nil

        for i in stride(from: openElements.count - 1, through: 0, by: -1) {
            let element = openElements[i]
            if element.name == "table" && lastTableIndex == nil {
                lastTableIndex = i
            }
            if element.name == "template" && lastTemplateIndex == nil {
                lastTemplateIndex = i
            }
        }

        // If last template is after last table, or there's no table, use template contents
        if let templateIndex = lastTemplateIndex {
            if lastTableIndex == nil || templateIndex > lastTableIndex! {
                if let content = openElements[templateIndex].templateContent {
                    content.appendChild(node)
                    return
                }
            }
        }

        // If no table found in the stack
        guard let tableIndex = lastTableIndex else {
            // For fragment parsing or when there's no table, insert in document or first element
            if !openElements.isEmpty {
                openElements[0].appendChild(node)
            } else {
                // Fragment parsing - insert directly into document
                document.appendChild(node)
            }
            return
        }

        let tableElement = openElements[tableIndex]

        // If table's parent is an element, insert before table
        if let parent = tableElement.parent {
            parent.insertBefore(node, reference: tableElement)
            return
        }

        // Otherwise, insert at the end of the element before table in the stack
        if tableIndex > 0 {
            openElements[tableIndex - 1].appendChild(node)
        } else {
            // Table is first in stack, insert into document
            document.appendChild(node)
        }
    }

    private func insertCharacter(_ ch: Character) {
        let target = adjustedInsertionTarget

        // Per spec: foster parenting for text only applies when the target is a table element
        if fosterParentingEnabled && ["table", "tbody", "tfoot", "thead", "tr"].contains(target.name) {
            insertCharacterWithFosterParenting(ch)
            return
        }

        // Merge with previous text node if possible
        if let lastChild = target.children.last, lastChild.name == "#text" {
            if case .text(let existing) = lastChild.data {
                lastChild.data = .text(existing + String(ch))
                return
            }
        }

        let textNode = Node(name: "#text", data: .text(String(ch)))
        target.appendChild(textNode)
    }

    private func insertCharacterWithFosterParenting(_ ch: Character) {
        // Find the foster parent location (before the table)
        var lastTableIndex: Int? = nil
        var lastTemplateIndex: Int? = nil

        for i in stride(from: openElements.count - 1, through: 0, by: -1) {
            let element = openElements[i]
            if element.name == "table" && lastTableIndex == nil {
                lastTableIndex = i
            }
            if element.name == "template" && lastTemplateIndex == nil {
                lastTemplateIndex = i
            }
        }

        // If last template is after last table, or there's no table, use template contents
        if let templateIndex = lastTemplateIndex {
            if lastTableIndex == nil || templateIndex > lastTableIndex! {
                if let content = openElements[templateIndex].templateContent {
                    // Merge with previous text node if possible
                    if let lastChild = content.children.last, lastChild.name == "#text" {
                        if case .text(let existing) = lastChild.data {
                            lastChild.data = .text(existing + String(ch))
                            return
                        }
                    }
                    let textNode = Node(name: "#text", data: .text(String(ch)))
                    content.appendChild(textNode)
                    return
                }
            }
        }

        // If no table found
        guard let tableIndex = lastTableIndex else {
            let target = adjustedInsertionTarget
            if let lastChild = target.children.last, lastChild.name == "#text" {
                if case .text(let existing) = lastChild.data {
                    lastChild.data = .text(existing + String(ch))
                    return
                }
            }
            let textNode = Node(name: "#text", data: .text(String(ch)))
            target.appendChild(textNode)
            return
        }

        let tableElement = openElements[tableIndex]

        // Insert before the table
        if let parent = tableElement.parent {
            // Check if there's a text node right before the table that we can merge with
            if let tableIdx = parent.children.firstIndex(where: { $0 === tableElement }),
               tableIdx > 0 {
                let prevNode = parent.children[tableIdx - 1]
                if prevNode.name == "#text" {
                    if case .text(let existing) = prevNode.data {
                        prevNode.data = .text(existing + String(ch))
                        return
                    }
                }
            }
            let textNode = Node(name: "#text", data: .text(String(ch)))
            parent.insertBefore(textNode, reference: tableElement)
        } else {
            // Table has no parent - use the element before table in stack
            if tableIndex > 0 {
                let target = openElements[tableIndex - 1]
                if let lastChild = target.children.last, lastChild.name == "#text" {
                    if case .text(let existing) = lastChild.data {
                        lastChild.data = .text(existing + String(ch))
                        return
                    }
                }
                let textNode = Node(name: "#text", data: .text(String(ch)))
                target.appendChild(textNode)
            }
        }
    }

    private func popCurrentElement() {
        if !openElements.isEmpty {
            openElements.removeLast()
        }
    }

    private func popUntil(_ name: String) {
        // In fragment parsing, if the target element is only the context element
        // (not on the actual stack), we should pop until we reach the html element
        let isContextOnly = contextElement?.name == name &&
                           !openElements.contains { $0.name == name }

        while let current = currentNode {
            if current.name == name {
                popCurrentElement()
                break
            }
            // In fragment parsing with context-only target, stop at html element
            if isContextOnly && current.name == "html" {
                break
            }
            popCurrentElement()
        }
    }

    /// Clear the stack back to a table context (table, template, or html)
    private func clearStackBackToTableContext() {
        while let current = currentNode {
            if ["table", "template", "html"].contains(current.name) {
                break
            }
            popCurrentElement()
        }
    }

    /// Clear the stack back to a table body context (tbody, tfoot, thead, template, or html)
    private func clearStackBackToTableBodyContext() {
        while let current = currentNode {
            if ["tbody", "tfoot", "thead", "template", "html"].contains(current.name) {
                break
            }
            popCurrentElement()
        }
    }

    /// Clear the stack back to a table row context (tr, template, or html)
    private func clearStackBackToTableRowContext() {
        while let current = currentNode {
            if ["tr", "template", "html"].contains(current.name) {
                break
            }
            popCurrentElement()
        }
    }

    /// Close the current cell (td or th)
    private func closeCell() {
        generateImpliedEndTags()
        if let current = currentNode, current.name != "td" && current.name != "th" {
            emitError("end-tag-too-early")
        }
        // Pop until td or th
        while let current = currentNode {
            let name = current.name
            popCurrentElement()
            if name == "td" || name == "th" {
                break
            }
        }
        clearActiveFormattingElementsToLastMarker()
        insertionMode = .inRow
    }

    private func insertHtmlElement() {
        let html = createElement(name: "html", attrs: [:])
        document.appendChild(html)
        openElements.append(html)
    }

    private func insertHeadElement() {
        let head = insertElement(name: "head", attrs: [:])
        headElement = head
    }

    private func insertBodyElement() {
        let body = insertElement(name: "body", attrs: [:])
        bodyElement = body
    }

    // MARK: - Scope Checking

    private func hasElementInScope(_ name: String) -> Bool {
        return hasElementInScope(name, scopeElements: SCOPE_ELEMENTS)
    }

    private func hasElementInButtonScope(_ name: String) -> Bool {
        return hasElementInScope(name, scopeElements: BUTTON_SCOPE_ELEMENTS)
    }

    private func hasElementInSelectScope(_ name: String) -> Bool {
        // In select scope, everything except optgroup and option is a scope marker
        for node in openElements.reversed() {
            if node.name == name {
                return true
            }
            if node.name != "optgroup" && node.name != "option" {
                // Per spec: In fragment parsing, if context element matches, consider it in scope
                if let ctx = contextElement, ctx.name == name {
                    return true
                }
                return false
            }
        }
        // Also check context element for fragment parsing
        if let ctx = contextElement, ctx.name == name {
            return true
        }
        return false
    }

    private func hasElementInListItemScope(_ name: String) -> Bool {
        return hasElementInScope(name, scopeElements: LIST_ITEM_SCOPE_ELEMENTS)
    }

    private func hasElementInTableScope(_ name: String) -> Bool {
        return hasElementInScope(name, scopeElements: TABLE_SCOPE_ELEMENTS)
    }

    private func hasElementInScope(_ name: String, scopeElements: Set<String>) -> Bool {
        for node in openElements.reversed() {
            if node.name == name {
                return true
            }
            if scopeElements.contains(node.name) {
                return false
            }
        }
        return false
    }

    // MARK: - Implied End Tags

    private func generateImpliedEndTags(except: String? = nil) {
        while let current = currentNode {
            if IMPLIED_END_TAGS.contains(current.name) && current.name != except {
                popCurrentElement()
            } else {
                break
            }
        }
    }

    private func closePElement() {
        generateImpliedEndTags(except: "p")
        if currentNode?.name != "p" {
            emitError("expected-p-end-tag")
        }
        popUntil("p")
    }

    // MARK: - Formatting Elements

    private func pushFormattingElement(_ element: Node) {
        activeFormattingElements.append(element)
    }

    private func insertMarker() {
        activeFormattingElements.append(nil)
    }

    private func clearActiveFormattingElementsToLastMarker() {
        while let last = activeFormattingElements.popLast() {
            if last == nil {
                break
            }
        }
    }

    private func reconstructActiveFormattingElements() {
        // 1. If there are no entries in the list, return
        if activeFormattingElements.isEmpty { return }

        // 2. If the last entry is a marker or is already in open elements, return
        guard let lastEntry = activeFormattingElements.last else { return }
        if lastEntry == nil { return }  // marker
        if let elem = lastEntry, openElements.contains(where: { $0 === elem }) {
            return
        }

        // 3. Rewind: find the first entry that's either a marker or in open elements
        var entryIndex = activeFormattingElements.count - 1
        while entryIndex > 0 {
            entryIndex -= 1
            if let entry = activeFormattingElements[entryIndex] {
                if openElements.contains(where: { $0 === entry }) {
                    entryIndex += 1
                    break
                }
            } else {
                // Hit a marker
                entryIndex += 1
                break
            }
        }

        // 4. Advance: create and insert elements
        while entryIndex < activeFormattingElements.count {
            guard let entry = activeFormattingElements[entryIndex] else {
                entryIndex += 1
                continue
            }

            // Create new element with same name and attributes
            let newElement = insertElement(name: entry.name, namespace: entry.namespace ?? .html, attrs: entry.attrs)

            // Replace the entry in the list
            activeFormattingElements[entryIndex] = newElement

            entryIndex += 1
        }
    }

    private func adoptionAgency(name: String) {
        // Step 1: If current node is the subject and not in active formatting, just pop it
        if let current = currentNode, current.name == name {
            if !hasActiveFormattingEntry(name) {
                popUntil(name)
                return
            }
        }

        // Step 2: Outer loop (max 8 iterations)
        for _ in 0..<8 {
            // Step 3: Find formatting element in active formatting list
            var formattingElementIndex: Int?
            for i in stride(from: activeFormattingElements.count - 1, through: 0, by: -1) {
                guard let elem = activeFormattingElements[i] else {
                    break  // Hit marker
                }
                if elem.name == name {
                    formattingElementIndex = i
                    break
                }
            }

            guard let feIndex = formattingElementIndex,
                  let formattingElement = activeFormattingElements[feIndex] else {
                // No formatting element found - use any other end tag handling
                anyOtherEndTag(name: name)
                return
            }

            // Step 4: Check if formatting element is in open elements
            guard let feStackIndex = openElements.firstIndex(where: { $0 === formattingElement }) else {
                emitError("adoption-agency-1.3")
                activeFormattingElements.remove(at: feIndex)
                return
            }

            // Step 5: Check if formatting element is in scope
            if !hasElementInScope(name) {
                emitError("adoption-agency-1.3")
                return
            }

            // Step 6: If formatting element is not current node, emit error
            if currentNode !== formattingElement {
                emitError("adoption-agency-1.3")
            }

            // Step 7: Find furthest block (first special element after formatting element)
            var furthestBlock: Node?
            var furthestBlockIndex: Int?
            for i in (feStackIndex + 1)..<openElements.count {
                let node = openElements[i]
                if SPECIAL_ELEMENTS.contains(node.name) {
                    furthestBlock = node
                    furthestBlockIndex = i
                    break
                }
            }

            // Step 8: If no furthest block, pop to formatting element and remove from active formatting
            guard let fb = furthestBlock, let fbIndex = furthestBlockIndex else {
                while openElements.count > feStackIndex {
                    popCurrentElement()
                }
                activeFormattingElements.remove(at: feIndex)
                return
            }

            // Step 9: Common ancestor
            // Safety check - formatting element must have a parent
            if feStackIndex == 0 {
                // No common ancestor - just pop to formatting element
                while openElements.count > feStackIndex {
                    popCurrentElement()
                }
                activeFormattingElements.remove(at: feIndex)
                return
            }
            let commonAncestor = openElements[feStackIndex - 1]

            // Step 10: Bookmark
            var bookmark = feIndex + 1

            // Step 11: Node and last node
            var node = fb
            var lastNode = fb
            var nodeIndex = fbIndex

            // Step 12: Inner loop
            var innerLoopCounter = 0
            while true {
                innerLoopCounter += 1

                // Safety check
                if innerLoopCounter > 100 {
                    break
                }

                // Step 12.1: Move node up the stack
                nodeIndex -= 1
                if nodeIndex < 0 || nodeIndex >= openElements.count {
                    break
                }
                node = openElements[nodeIndex]

                // Step 12.2: If node is formatting element, break
                if node === formattingElement {
                    break
                }

                // Step 12.3: Find node's entry in active formatting
                var nodeFormattingIndex: Int?
                for i in 0..<activeFormattingElements.count {
                    if let elem = activeFormattingElements[i], elem === node {
                        nodeFormattingIndex = i
                        break
                    }
                }

                // Step 12.4: If inner loop counter > 3 and node is in active formatting, remove it
                if innerLoopCounter > 3, let nfi = nodeFormattingIndex {
                    activeFormattingElements.remove(at: nfi)
                    if nfi < bookmark {
                        bookmark -= 1
                    }
                    nodeFormattingIndex = nil
                }

                // Step 12.5: If node is not in active formatting, remove from stack and continue
                if nodeFormattingIndex == nil {
                    openElements.remove(at: nodeIndex)
                    // After removal, elements shift down, so nodeIndex now points to what was nodeIndex+1.
                    // The next decrement at the loop start will correctly move to the element that was above.
                    continue
                }

                // Step 12.6: Create new element and replace in both lists
                let newElement = Node(name: node.name, namespace: node.namespace ?? .html, attrs: node.attrs)

                // Replace in active formatting
                activeFormattingElements[nodeFormattingIndex!] = newElement

                // Replace in open elements
                openElements[nodeIndex] = newElement
                node = newElement

                // Step 12.7: If last node is furthest block, update bookmark
                if lastNode === fb {
                    bookmark = nodeFormattingIndex! + 1
                }

                // Step 12.8: Reparent last node
                if let parent = lastNode.parent {
                    parent.removeChild(lastNode)
                }
                node.appendChild(lastNode)

                // Step 12.9: last node = node
                lastNode = node
            }

            // Step 13: Insert last node into common ancestor
            if let parent = lastNode.parent {
                parent.removeChild(lastNode)
            }
            // Insert into common ancestor (or its template content if template)
            if commonAncestor.name == "template", let content = commonAncestor.templateContent {
                content.appendChild(lastNode)
            } else {
                commonAncestor.appendChild(lastNode)
            }

            // Step 14: Create new formatting element
            let newFormattingElement = Node(name: formattingElement.name, namespace: formattingElement.namespace ?? .html, attrs: formattingElement.attrs)

            // Step 15: Move children of furthest block to new formatting element
            while !fb.children.isEmpty {
                let child = fb.children[0]
                fb.removeChild(child)
                newFormattingElement.appendChild(child)
            }

            // Step 16: Append new formatting element to furthest block
            fb.appendChild(newFormattingElement)

            // Step 17: Remove formatting element from active formatting and insert new at bookmark
            activeFormattingElements.remove(at: feIndex)
            if bookmark > activeFormattingElements.count {
                bookmark = activeFormattingElements.count
            }
            activeFormattingElements.insert(newFormattingElement, at: bookmark)

            // Step 18: Remove formatting element from open elements and insert new after furthest block
            openElements.removeAll { $0 === formattingElement }
            if let newFbIndex = openElements.firstIndex(where: { $0 === fb }) {
                openElements.insert(newFormattingElement, at: newFbIndex + 1)
            }
        }
    }

    /// Check if there's an entry for the given name in active formatting elements (before any marker)
    private func hasActiveFormattingEntry(_ name: String) -> Bool {
        for i in stride(from: activeFormattingElements.count - 1, through: 0, by: -1) {
            guard let elem = activeFormattingElements[i] else {
                return false  // Hit marker
            }
            if elem.name == name {
                return true
            }
        }
        return false
    }

    // MARK: - Foreign Content

    /// Elements that break out of foreign content back to HTML
    private static let foreignContentBreakoutElements: Set<String> = [
        "b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl", "dt",
        "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i", "img", "li",
        "listing", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small", "span",
        "strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var"
    ]

    /// HTML integration points in SVG
    private static let svgHtmlIntegrationPoints: Set<String> = ["foreignObject", "desc", "title"]

    /// MathML text integration points (affect how certain tags are processed, not general HTML processing)
    private static let mathmlTextIntegrationPoints: Set<String> = ["mi", "mo", "mn", "ms", "mtext"]

    /// Get the adjusted current node per WHATWG spec
    /// In fragment case with only one element on stack, use the context element instead
    private var adjustedCurrentNode: Node? {
        // If we're in fragment parsing and the stack only has the html element,
        // use the context element for namespace decisions
        if contextElement != nil && openElements.count == 1 {
            return contextElement
        }
        return openElements.last
    }

    /// Check if we should process start tags in foreign content mode
    /// Returns false only for SVG HTML integration points (not MathML text integration points)
    /// because MathML text integration points still process MOST start tags as foreign content
    private func shouldProcessInForeignContent() -> Bool {
        guard let node = adjustedCurrentNode else { return false }
        guard let ns = node.namespace else { return false }

        // Check if we're in an SVG HTML integration point (foreignObject, desc, title)
        // These process start tags as HTML
        if ns == .svg && Self.svgHtmlIntegrationPoints.contains(node.name) {
            return false
        }

        // Note: MathML text integration points (mi, mo, mn, ms, mtext) still process
        // most start tags as foreign content - only breakout elements are handled as HTML
        // So we don't return false for them here

        return ns == .svg || ns == .math
    }

    /// Check if current node is a MathML text integration point
    private func isInMathMLTextIntegrationPoint() -> Bool {
        guard let currentNode = openElements.last else { return false }
        return currentNode.namespace == .math && Self.mathmlTextIntegrationPoints.contains(currentNode.name)
    }

    /// Check if current node is an SVG HTML integration point
    private func isInSVGHtmlIntegrationPoint() -> Bool {
        guard let currentNode = openElements.last else { return false }
        return currentNode.namespace == .svg && Self.svgHtmlIntegrationPoints.contains(currentNode.name)
    }

    /// Check if there are any foreign (SVG/MathML) elements in the open elements stack
    private func hasForeignElementInStack() -> Bool {
        return openElements.contains { elem in
            elem.namespace == .svg || elem.namespace == .math
        }
    }

    /// Process an end tag in foreign content per WHATWG spec
    /// Returns true if handled, false if should fall through to normal processing
    private func processForeignContentEndTag(name: String) -> Bool {
        let lowercaseName = name.lowercased()

        // Special handling for </br> and </p> - break out and reprocess as end tag
        if lowercaseName == "br" || lowercaseName == "p" {
            emitError("unexpected-end-tag")
            // Pop until we leave foreign content (reach SVG HTML integration point or HTML namespace)
            while let current = currentNode,
                  let ns = current.namespace,
                  (ns == .svg || ns == .math),
                  !(ns == .svg && Self.svgHtmlIntegrationPoints.contains(current.name)) {
                popCurrentElement()
            }
            // Reprocess the end tag in HTML mode - return false to let normal processing handle it
            return false
        }

        // Walk up the stack looking for a matching foreign element
        // Per WHATWG: "Any other end tag" in foreign content
        for i in stride(from: openElements.count - 1, through: 0, by: -1) {
            let node = openElements[i]

            // If we hit an HTML element, let normal processing handle it
            if node.namespace == nil || node.namespace == .html {
                return false
            }

            // Check if this foreign element matches (case-insensitive)
            if node.name.lowercased() == lowercaseName {
                // Pop elements until we've popped this node
                while openElements.count > i {
                    popCurrentElement()
                }
                return true
            }
        }

        // No matching foreign element found, let normal processing handle it
        return false
    }

    /// Process a start tag in foreign content
    /// Returns true if handled, false if should fall through to normal processing
    private func processForeignContentStartTag(name: String, attrs: [String: String], selfClosing: Bool) -> Bool {
        let lowercaseName = name.lowercased()

        // In MathML text integration points (mi, mo, mn, ms, mtext), only mglyph and malignmark
        // stay in MathML - everything else should be processed as HTML
        if let adjNode = adjustedCurrentNode,
           adjNode.namespace == .math && Self.mathmlTextIntegrationPoints.contains(adjNode.name),
           lowercaseName != "mglyph" && lowercaseName != "malignmark" {
            return false
        }

        // Check for breakout elements
        // font only breaks out if it has color, face, or size attributes
        let isFontBreakout = lowercaseName == "font" &&
            (attrs.keys.contains { $0.lowercased() == "color" || $0.lowercased() == "face" || $0.lowercased() == "size" })

        if Self.foreignContentBreakoutElements.contains(lowercaseName) || isFontBreakout {
            // If current node is MathML text integration point or SVG HTML integration point,
            // process breakout elements as HTML without popping
            if let current = currentNode,
               let ns = current.namespace,
               ((ns == .svg && Self.svgHtmlIntegrationPoints.contains(current.name)) ||
                (ns == .math && Self.mathmlTextIntegrationPoints.contains(current.name))) {
                return false
            }

            // Pop until we leave foreign content (but not HTML integration points)
            while let current = currentNode,
                  let ns = current.namespace,
                  (ns == .svg || ns == .math),
                  !(ns == .svg && Self.svgHtmlIntegrationPoints.contains(current.name)),
                  !(ns == .math && Self.mathmlTextIntegrationPoints.contains(current.name)) {
                popCurrentElement()
            }
            // Process as normal HTML
            return false
        }

        // Determine the namespace for the new element using adjusted current node
        guard let adjNode = adjustedCurrentNode,
              let currentNs = adjNode.namespace else { return false }

        // SVG and MathML elements inside foreign content should use their own namespace
        var ns: Namespace = currentNs
        var adjustedName = name
        if lowercaseName == "svg" {
            ns = .svg
        } else if lowercaseName == "math" {
            ns = .math
        } else if currentNs == .svg {
            // Apply SVG tag name adjustments
            adjustedName = SVG_ELEMENT_ADJUSTMENTS[lowercaseName] ?? name
        }

        let adjustedAttrs = adjustForeignAttributes(attrs, namespace: ns)
        _ = insertElement(name: adjustedName, namespace: ns, attrs: adjustedAttrs)

        if selfClosing {
            popCurrentElement()
        }

        return true
    }

    // MARK: - Rawtext and RCDATA Parsing

    private func parseRawtext(name: String, attrs: [String: String]) {
        _ = insertElement(name: name, attrs: attrs)
        originalInsertionMode = insertionMode
        insertionMode = .text
        // TODO: Switch tokenizer to RAWTEXT state
    }

    private func parseRCDATA(name: String, attrs: [String: String]) {
        _ = insertElement(name: name, attrs: attrs)
        originalInsertionMode = insertionMode
        insertionMode = .text
        // TODO: Switch tokenizer to RCDATA state
    }

    // MARK: - Insertion Mode Reset

    private func resetInsertionMode() {
        var last = false

        for i in stride(from: openElements.count - 1, through: 0, by: -1) {
            var node = openElements[i]
            if i == 0 {
                last = true
                if let ctx = contextElement {
                    node = ctx
                }
            }

            switch node.name {
            case "select":
                insertionMode = .inSelect
                return
            case "td", "th":
                if !last {
                    insertionMode = .inCell
                    return
                }
            case "tr":
                insertionMode = .inRow
                return
            case "tbody", "thead", "tfoot":
                insertionMode = .inTableBody
                return
            case "caption":
                insertionMode = .inCaption
                return
            case "colgroup":
                insertionMode = .inColumnGroup
                return
            case "table":
                insertionMode = .inTable
                return
            case "template":
                if let mode = templateInsertionModes.last {
                    insertionMode = mode
                }
                return
            case "head":
                if !last {
                    insertionMode = .inHead
                    return
                }
            case "body":
                insertionMode = .inBody
                return
            case "frameset":
                insertionMode = .inFrameset
                return
            case "html":
                if headElement == nil {
                    insertionMode = .beforeHead
                } else {
                    insertionMode = .afterHead
                }
                return
            default:
                break
            }

            if last {
                insertionMode = .inBody
                return
            }
        }
    }

    // MARK: - Utilities

    private func isWhitespace(_ ch: Character) -> Bool {
        return ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}"
    }

    private func emitError(_ code: String) {
        if collectErrors {
            errors.append(ParseError(code: code))
        }
    }
}

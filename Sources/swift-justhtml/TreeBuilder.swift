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

        // Set up fragment parsing context
        if let ctx = fragmentContext {
            // Create context element (virtual, not part of the tree)
            let ctxElement = Node(name: ctx.tagName, namespace: ctx.namespace ?? .html)
            self.contextElement = ctxElement

            // For template context, push inTemplate onto template insertion modes
            if ctx.tagName == "template" {
                templateInsertionModes.append(.inTemplate)
            }

            // Reset insertion mode based on context element
            // Note: openElements is empty, so resetInsertionMode will fall through
            // and use the context element at the "last" position
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
            } else if ["noscript", "noframes", "style"].contains(name) {
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
                if insertionMode == .text {
                    originalInsertionMode = savedMode
                } else {
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

        default:
            processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
        }
    }

    private func processStartTagInBody(name: String, attrs: [String: String], selfClosing: Bool) {
        if name == "html" {
            emitError("unexpected-start-tag")
            if let html = openElements.first {
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
            } else {
                insertionMode = savedMode
            }
        } else if name == "body" {
            emitError("unexpected-start-tag")
            if openElements.count >= 2, openElements[1].name == "body" {
                framesetOk = false
                for (key, value) in attrs where openElements[1].attrs[key] == nil {
                    openElements[1].attrs[key] = value
                }
            }
        } else if name == "frameset" {
            emitError("unexpected-start-tag")
            // Ignore unless framesetOk
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
            // TODO: close li elements
            if hasElementInButtonScope("p") {
                closePElement()
            }
            _ = insertElement(name: name, attrs: attrs)
        } else if ["dd", "dt"].contains(name) {
            framesetOk = false
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
            // Check for active 'a' element
            reconstructActiveFormattingElements()
            let element = insertElement(name: name, attrs: attrs)
            pushFormattingElement(element)
        } else if FORMATTING_ELEMENTS.contains(name) {
            reconstructActiveFormattingElements()
            let element = insertElement(name: name, attrs: attrs)
            pushFormattingElement(element)
        } else if name == "nobr" {
            reconstructActiveFormattingElements()
            if hasElementInScope("nobr") {
                emitError("unexpected-start-tag")
                // Run adoption agency
                _ = insertElement(name: name, attrs: attrs)
            } else {
                let element = insertElement(name: name, attrs: attrs)
                pushFormattingElement(element)
            }
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
            insertionMode = .inSelect
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
            // TODO: adjust math attributes
            let element = insertElement(name: name, namespace: .math, attrs: attrs)
            if selfClosing {
                popCurrentElement()
            }
        } else if name == "svg" {
            reconstructActiveFormattingElements()
            // TODO: adjust svg attributes
            let element = insertElement(name: name, namespace: .svg, attrs: attrs)
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
                // TODO: handle template
                emitError("unexpected-end-tag")
            } else {
                emitError("unexpected-end-tag")
            }

        case .afterHead:
            if name == "body" || name == "html" || name == "br" {
                insertBodyElement()
                insertionMode = .inBody
                processEndTag(name: name)
            } else if name == "template" {
                // Process in head
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
            if !hasElementInScope("template") {
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
        case .initial, .beforeHtml, .afterAfterBody, .afterAfterFrameset:
            document.appendChild(comment)
        default:
            if let current = currentNode {
                current.appendChild(comment)
            } else {
                document.appendChild(comment)
            }
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
        case .afterHead:
            insertBodyElement()
            insertionMode = .inBody
            processEOF()
        default:
            break
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

    @discardableResult
    private func insertElement(name: String, namespace: Namespace = .html, attrs: [String: String]) -> Node {
        let element = createElement(name: name, namespace: namespace, attrs: attrs)
        insertNode(element)
        openElements.append(element)
        return element
    }

    private func insertNode(_ node: Node) {
        adjustedInsertionTarget.appendChild(node)
    }

    private func insertCharacter(_ ch: Character) {
        let target = adjustedInsertionTarget

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

    private func popCurrentElement() {
        if !openElements.isEmpty {
            openElements.removeLast()
        }
    }

    private func popUntil(_ name: String) {
        while let current = currentNode {
            popCurrentElement()
            if current.name == name {
                break
            }
        }
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

    private func hasElementInListItemScope(_ name: String) -> Bool {
        return hasElementInScope(name, scopeElements: LIST_ITEM_SCOPE_ELEMENTS)
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
        // Simplified adoption agency algorithm
        for _ in 0..<8 {
            // Find formatting element
            var formattingElement: Node?
            var formattingIdx: Int?
            for i in stride(from: activeFormattingElements.count - 1, through: 0, by: -1) {
                guard let elem = activeFormattingElements[i] else {
                    break  // Hit marker
                }
                if elem.name == name {
                    formattingElement = elem
                    formattingIdx = i
                    break
                }
            }

            guard let fe = formattingElement, let _ = formattingIdx else {
                anyOtherEndTag(name: name)
                return
            }

            guard let stackIdx = openElements.firstIndex(where: { $0 === fe }) else {
                activeFormattingElements.removeAll { $0 === fe }
                return
            }

            if !hasElementInScope(name) {
                emitError("unexpected-end-tag")
                return
            }

            if currentNode !== fe {
                emitError("end-tag-too-early")
            }

            // Pop to formatting element
            while openElements.count > stackIdx {
                popCurrentElement()
            }
            activeFormattingElements.removeAll { $0 === fe }
            return
        }
    }

    // MARK: - Foreign Content

    /// Elements that break out of foreign content back to HTML
    private static let foreignContentBreakoutElements: Set<String> = [
        "b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl", "dt",
        "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i", "img", "li",
        "listing", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small", "span",
        "strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var"
    ]

    /// Check if we should process in foreign content mode
    private func shouldProcessInForeignContent() -> Bool {
        guard let currentNode = openElements.last else { return false }
        guard let ns = currentNode.namespace else { return false }
        return ns == .svg || ns == .math
    }

    /// Process a start tag in foreign content
    /// Returns true if handled, false if should fall through to normal processing
    private func processForeignContentStartTag(name: String, attrs: [String: String], selfClosing: Bool) -> Bool {
        let lowercaseName = name.lowercased()

        // Check for breakout elements
        // font only breaks out if it has color, face, or size attributes
        let isFontBreakout = lowercaseName == "font" &&
            (attrs.keys.contains { $0.lowercased() == "color" || $0.lowercased() == "face" || $0.lowercased() == "size" })

        if Self.foreignContentBreakoutElements.contains(lowercaseName) || isFontBreakout {
            // Pop until we leave foreign content
            while let current = currentNode,
                  let ns = current.namespace,
                  (ns == .svg || ns == .math) {
                popCurrentElement()
            }
            // Process as normal HTML
            return false
        }

        // Insert element in current foreign namespace
        guard let ns = currentNode?.namespace else { return false }
        _ = insertElement(name: name, namespace: ns, attrs: attrs)

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

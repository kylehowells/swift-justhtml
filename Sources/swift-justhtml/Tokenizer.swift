// Tokenizer.swift - HTML5 tokenizer state machine

import Foundation

/// Protocol for receiving tokens from the tokenizer
public protocol TokenSink: AnyObject {
    func processToken(_ token: Token)
    /// Current element's namespace (for rawtext state switching)
    var currentNamespace: Namespace? { get }
}

/// RCDATA elements that switch tokenizer to RCDATA state
private let RCDATA_ELEMENTS: Set<String> = ["title", "textarea"]

/// RAWTEXT elements that switch tokenizer to RAWTEXT state
private let RAWTEXT_ELEMENTS: Set<String> = ["style", "xmp", "iframe", "noembed", "noframes"]

/// Script element needs SCRIPT DATA state
private let SCRIPT_ELEMENT = "script"

/// Tokenizer options
public struct TokenizerOpts {
    public var initialState: Tokenizer.State
    public var initialRawtextTag: String?
    public var xmlCoercion: Bool
    public var discardBom: Bool

    public init(
        initialState: Tokenizer.State = .data,
        initialRawtextTag: String? = nil,
        xmlCoercion: Bool = false,
        discardBom: Bool = false
    ) {
        self.initialState = initialState
        self.initialRawtextTag = initialRawtextTag
        self.xmlCoercion = xmlCoercion
        self.discardBom = discardBom
    }
}

/// HTML5 tokenizer
public final class Tokenizer {
    /// Tokenizer states
    public enum State {
        case data
        case rcdata
        case rawtext
        case scriptData
        case plaintext
        case tagOpen
        case endTagOpen
        case tagName
        case rcdataLessThan
        case rcdataEndTagOpen
        case rcdataEndTagName
        case rawtextLessThan
        case rawtextEndTagOpen
        case rawtextEndTagName
        case scriptDataLessThan
        case scriptDataEndTagOpen
        case scriptDataEndTagName
        case beforeAttributeName
        case attributeName
        case afterAttributeName
        case beforeAttributeValue
        case attributeValueDoubleQuoted
        case attributeValueSingleQuoted
        case attributeValueUnquoted
        case afterAttributeValueQuoted
        case selfClosingStartTag
        case bogusComment
        case markupDeclarationOpen
        case commentStart
        case commentStartDash
        case comment
        case commentEndDash
        case commentEnd
        case commentEndBang
        case doctype
        case beforeDoctypeName
        case doctypeName
        case afterDoctypeName
        case afterDoctypePublicKeyword
        case beforeDoctypePublicIdentifier
        case doctypePublicIdentifierDoubleQuoted
        case doctypePublicIdentifierSingleQuoted
        case afterDoctypePublicIdentifier
        case betweenDoctypePublicAndSystemIdentifiers
        case afterDoctypeSystemKeyword
        case beforeDoctypeSystemIdentifier
        case doctypeSystemIdentifierDoubleQuoted
        case doctypeSystemIdentifierSingleQuoted
        case afterDoctypeSystemIdentifier
        case bogusDoctype
        case cdataSection
        case cdataSectionBracket
        case cdataSectionEnd
        case characterReference
        case namedCharacterReference
        case ambiguousAmpersand
        case numericCharacterReference
        case hexadecimalCharacterReferenceStart
        case decimalCharacterReferenceStart
        case hexadecimalCharacterReference
        case decimalCharacterReference
        case numericCharacterReferenceEnd
    }

    private weak var sink: TokenSink?
    private let opts: TokenizerOpts

    private var state: State
    private var returnState: State = .data
    private var input: String = ""
    private var pos: String.Index
    private var line: Int = 1
    private var column: Int = 0

    // Current token being built
    private var currentTagName: String = ""
    private var currentTagIsEnd: Bool = false
    private var currentTagSelfClosing: Bool = false
    private var currentAttrs: [String: String] = [:]
    private var currentAttrName: String = ""
    private var currentAttrValue: String = ""

    // Comment/doctype building
    private var currentComment: String = ""
    private var currentDoctypeName: String = ""
    private var currentDoctypePublicId: String? = nil
    private var currentDoctypeSystemId: String? = nil
    private var currentDoctypeForceQuirks: Bool = false

    // Character buffer
    private var charBuffer: String = ""

    // Temporary buffer for rawtext/rcdata end tag matching
    private var tempBuffer: String = ""
    private var lastStartTagName: String = ""

    // Character reference state
    private var charRefCode: UInt32 = 0
    private var charRefTempBuffer: String = ""

    // Error collection
    public var errors: [ParseError] = []
    private var collectErrors: Bool

    public init(_ sink: TokenSink, opts: TokenizerOpts = TokenizerOpts(), collectErrors: Bool = false) {
        self.sink = sink
        self.opts = opts
        self.state = opts.initialState
        self.collectErrors = collectErrors
        self.pos = "".startIndex
        if let rawtextTag = opts.initialRawtextTag {
            self.lastStartTagName = rawtextTag
        }
    }

    public func run(_ html: String) {
        self.input = html
        self.pos = html.startIndex

        // Optionally discard BOM
        if opts.discardBom && !html.isEmpty && html.first == "\u{FEFF}" {
            pos = html.index(after: pos)
        }

        // Process all input
        while pos < input.endIndex {
            processState()
        }

        // Handle EOF - process remaining states until we reach data state
        var eofIterations = 0
        while state != .data && eofIterations < 100 {
            processState()
            eofIterations += 1
        }

        // Flush and emit EOF
        flushCharBuffer()
        emit(.eof)
    }

    private func processState() {
        switch state {
        case .data:
            dataState()
        case .rcdata:
            rcdataState()
        case .rawtext:
            rawtextState()
        case .plaintext:
            plaintextState()
        case .tagOpen:
            tagOpenState()
        case .endTagOpen:
            endTagOpenState()
        case .tagName:
            tagNameState()
        case .rcdataLessThan:
            rcdataLessThanState()
        case .rcdataEndTagOpen:
            rcdataEndTagOpenState()
        case .rcdataEndTagName:
            rcdataEndTagNameState()
        case .rawtextLessThan:
            rawtextLessThanState()
        case .rawtextEndTagOpen:
            rawtextEndTagOpenState()
        case .rawtextEndTagName:
            rawtextEndTagNameState()
        case .beforeAttributeName:
            beforeAttributeNameState()
        case .attributeName:
            attributeNameState()
        case .afterAttributeName:
            afterAttributeNameState()
        case .beforeAttributeValue:
            beforeAttributeValueState()
        case .attributeValueDoubleQuoted:
            attributeValueDoubleQuotedState()
        case .attributeValueSingleQuoted:
            attributeValueSingleQuotedState()
        case .attributeValueUnquoted:
            attributeValueUnquotedState()
        case .afterAttributeValueQuoted:
            afterAttributeValueQuotedState()
        case .selfClosingStartTag:
            selfClosingStartTagState()
        case .bogusComment:
            bogusCommentState()
        case .markupDeclarationOpen:
            markupDeclarationOpenState()
        case .commentStart:
            commentStartState()
        case .commentStartDash:
            commentStartDashState()
        case .comment:
            commentState()
        case .commentEndDash:
            commentEndDashState()
        case .commentEnd:
            commentEndState()
        case .commentEndBang:
            commentEndBangState()
        case .doctype:
            doctypeState()
        case .beforeDoctypeName:
            beforeDoctypeNameState()
        case .doctypeName:
            doctypeNameState()
        case .afterDoctypeName:
            afterDoctypeNameState()
        case .afterDoctypePublicKeyword:
            afterDoctypePublicKeywordState()
        case .beforeDoctypePublicIdentifier:
            beforeDoctypePublicIdentifierState()
        case .doctypePublicIdentifierDoubleQuoted:
            doctypePublicIdentifierDoubleQuotedState()
        case .doctypePublicIdentifierSingleQuoted:
            doctypePublicIdentifierSingleQuotedState()
        case .afterDoctypePublicIdentifier:
            afterDoctypePublicIdentifierState()
        case .betweenDoctypePublicAndSystemIdentifiers:
            betweenDoctypePublicAndSystemIdentifiersState()
        case .afterDoctypeSystemKeyword:
            afterDoctypeSystemKeywordState()
        case .beforeDoctypeSystemIdentifier:
            beforeDoctypeSystemIdentifierState()
        case .doctypeSystemIdentifierDoubleQuoted:
            doctypeSystemIdentifierDoubleQuotedState()
        case .doctypeSystemIdentifierSingleQuoted:
            doctypeSystemIdentifierSingleQuotedState()
        case .afterDoctypeSystemIdentifier:
            afterDoctypeSystemIdentifierState()
        case .bogusDoctype:
            bogusDoctypeState()
        case .characterReference:
            characterReferenceState()
        case .namedCharacterReference:
            namedCharacterReferenceState()
        case .ambiguousAmpersand:
            ambiguousAmpersandState()
        case .numericCharacterReference:
            numericCharacterReferenceState()
        case .hexadecimalCharacterReferenceStart:
            hexadecimalCharacterReferenceStartState()
        case .decimalCharacterReferenceStart:
            decimalCharacterReferenceStartState()
        case .hexadecimalCharacterReference:
            hexadecimalCharacterReferenceState()
        case .decimalCharacterReference:
            decimalCharacterReferenceState()
        case .numericCharacterReferenceEnd:
            numericCharacterReferenceEndState()
        case .cdataSection:
            cdataSectionState()
        case .cdataSectionBracket:
            cdataSectionBracketState()
        case .cdataSectionEnd:
            cdataSectionEndState()
        case .scriptDataLessThan, .scriptDataEndTagOpen, .scriptDataEndTagName, .scriptData:
            // For now, treat script data like rawtext
            rawtextState()
        }
    }

    // MARK: - Character Consumption

    private func consume() -> Character? {
        guard pos < input.endIndex else { return nil }
        let ch = input[pos]
        pos = input.index(after: pos)

        // Track line/column
        if ch == "\n" {
            line += 1
            column = 0
        } else {
            column += 1
        }

        return ch
    }

    private func peek() -> Character? {
        guard pos < input.endIndex else { return nil }
        return input[pos]
    }

    private func peekAhead(_ n: Int) -> Character? {
        var idx = pos
        for _ in 0..<n {
            guard idx < input.endIndex else { return nil }
            idx = input.index(after: idx)
        }
        guard idx < input.endIndex else { return nil }
        return input[idx]
    }

    private func reconsume() {
        if pos > input.startIndex {
            pos = input.index(before: pos)
            // Adjust line/column tracking
            if input[pos] == "\n" {
                line -= 1
                // column tracking becomes inaccurate here but that's OK for now
            } else {
                column -= 1
            }
        }
    }

    private func consumeIf(_ expected: String, caseInsensitive: Bool = true) -> Bool {
        var tempPos = pos
        for ch in expected {
            guard tempPos < input.endIndex else { return false }
            let inputCh = input[tempPos]
            let match = caseInsensitive
                ? inputCh.asLowercaseCharacter == ch.asLowercaseCharacter
                : inputCh == ch
            if !match { return false }
            tempPos = input.index(after: tempPos)
        }
        // Consume the matched characters
        for _ in expected {
            _ = consume()
        }
        return true
    }

    // MARK: - Token Emission

    private func emit(_ token: Token) {
        flushCharBuffer()
        sink?.processToken(token)
    }

    private func emitChar(_ ch: Character) {
        charBuffer.append(ch)
    }

    private func emitString(_ s: String) {
        charBuffer.append(s)
    }

    private func flushCharBuffer() {
        if !charBuffer.isEmpty {
            sink?.processToken(.character(charBuffer))
            charBuffer = ""
        }
    }

    private func emitCurrentTag() {
        flushCharBuffer()
        if currentTagIsEnd {
            sink?.processToken(.endTag(name: currentTagName))
        } else {
            sink?.processToken(.startTag(name: currentTagName, attrs: currentAttrs, selfClosing: currentTagSelfClosing))
            lastStartTagName = currentTagName

            // Switch to appropriate state for special elements (only in HTML namespace)
            let ns = sink?.currentNamespace
            if ns == nil || ns == .html {
                if RCDATA_ELEMENTS.contains(currentTagName) {
                    state = .rcdata
                } else if RAWTEXT_ELEMENTS.contains(currentTagName) {
                    state = .rawtext
                } else if currentTagName == SCRIPT_ELEMENT {
                    state = .scriptData
                } else if currentTagName == "plaintext" {
                    state = .plaintext
                }
            }
        }
        resetTag()
    }

    private func emitCurrentComment() {
        emit(.comment(currentComment))
        currentComment = ""
    }

    private func emitCurrentDoctype() {
        let doctype = Doctype(
            name: currentDoctypeName.isEmpty ? nil : currentDoctypeName,
            publicId: currentDoctypePublicId,
            systemId: currentDoctypeSystemId,
            forceQuirks: currentDoctypeForceQuirks
        )
        emit(.doctype(doctype))
        resetDoctype()
    }

    private func resetTag() {
        currentTagName = ""
        currentTagIsEnd = false
        currentTagSelfClosing = false
        currentAttrs = [:]
        currentAttrName = ""
        currentAttrValue = ""
    }

    private func resetDoctype() {
        currentDoctypeName = ""
        currentDoctypePublicId = nil
        currentDoctypeSystemId = nil
        currentDoctypeForceQuirks = false
    }

    private func storeCurrentAttr() {
        if !currentAttrName.isEmpty && currentAttrs[currentAttrName] == nil {
            currentAttrs[currentAttrName] = currentAttrValue
        }
        currentAttrName = ""
        currentAttrValue = ""
    }

    private func emitError(_ code: String) {
        if collectErrors {
            errors.append(ParseError(code: code, line: line, column: column))
        }
    }

    // MARK: - Tokenizer States

    private func dataState() {
        guard let ch = consume() else {
            emit(.eof)
            return
        }
        switch ch {
        case "&":
            returnState = .data
            state = .characterReference
        case "<":
            state = .tagOpen
        case "\0":
            emitError("unexpected-null-character")
            emitChar(ch)
        default:
            emitChar(ch)
        }
    }

    private func rcdataState() {
        guard let ch = consume() else {
            emit(.eof)
            return
        }
        switch ch {
        case "&":
            returnState = .rcdata
            state = .characterReference
        case "<":
            state = .rcdataLessThan
        case "\0":
            emitError("unexpected-null-character")
            emitChar("\u{FFFD}")
        default:
            emitChar(ch)
        }
    }

    private func rawtextState() {
        guard let ch = consume() else {
            emit(.eof)
            return
        }
        switch ch {
        case "<":
            state = .rawtextLessThan
        case "\0":
            emitError("unexpected-null-character")
            emitChar("\u{FFFD}")
        default:
            emitChar(ch)
        }
    }

    private func plaintextState() {
        guard let ch = consume() else {
            emit(.eof)
            return
        }
        if ch == "\0" {
            emitError("unexpected-null-character")
            emitChar("\u{FFFD}")
        } else {
            emitChar(ch)
        }
    }

    private func tagOpenState() {
        guard let ch = consume() else {
            emitError("eof-before-tag-name")
            emitChar("<")
            state = .data
            return
        }
        switch ch {
        case "!":
            state = .markupDeclarationOpen
        case "/":
            state = .endTagOpen
        case "?":
            emitError("unexpected-question-mark-instead-of-tag-name")
            currentComment = ""
            state = .bogusComment
            reconsume()
        default:
            if ch.isASCIILetter {
                resetTag()
                currentTagIsEnd = false
                state = .tagName
                reconsume()
            } else {
                emitError("invalid-first-character-of-tag-name")
                emitChar("<")
                state = .data
                reconsume()
            }
        }
    }

    private func endTagOpenState() {
        guard let ch = consume() else {
            emitError("eof-before-tag-name")
            emitString("</")
            state = .data
            return
        }
        if ch.isASCIILetter {
            resetTag()
            currentTagIsEnd = true
            state = .tagName
            reconsume()
        } else if ch == ">" {
            emitError("missing-end-tag-name")
            state = .data
        } else {
            emitError("invalid-first-character-of-tag-name")
            currentComment = ""
            state = .bogusComment
            reconsume()
        }
    }

    private func tagNameState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .beforeAttributeName
        case "/":
            state = .selfClosingStartTag
        case ">":
            state = .data
            emitCurrentTag()
        case "\0":
            emitError("unexpected-null-character")
            currentTagName.append("\u{FFFD}")
        default:
            currentTagName.append(ch.asLowercaseCharacter)
        }
    }

    private func rcdataLessThanState() {
        guard let ch = consume() else {
            emitChar("<")
            state = .rcdata
            return
        }
        if ch == "/" {
            tempBuffer = ""
            state = .rcdataEndTagOpen
        } else {
            emitChar("<")
            state = .rcdata
            reconsume()
        }
    }

    private func rcdataEndTagOpenState() {
        guard let ch = consume() else {
            emitString("</")
            state = .rcdata
            return
        }
        if ch.isASCIILetter {
            resetTag()
            currentTagIsEnd = true
            state = .rcdataEndTagName
            reconsume()
        } else {
            emitString("</")
            state = .rcdata
            reconsume()
        }
    }

    private func rcdataEndTagNameState() {
        guard let ch = consume() else {
            emitString("</")
            emitString(tempBuffer)
            state = .rcdata
            return
        }

        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            if tempBuffer.lowercased() == lastStartTagName.lowercased() {
                state = .beforeAttributeName
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rcdata
                reconsume()
            }
        case "/":
            if tempBuffer.lowercased() == lastStartTagName.lowercased() {
                state = .selfClosingStartTag
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rcdata
                reconsume()
            }
        case ">":
            if tempBuffer.lowercased() == lastStartTagName.lowercased() {
                currentTagName = tempBuffer.lowercased()
                state = .data
                emitCurrentTag()
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rcdata
                reconsume()
            }
        default:
            if ch.isASCIILetter {
                currentTagName.append(ch.asLowercaseCharacter)
                tempBuffer.append(ch)
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rcdata
                reconsume()
            }
        }
    }

    private func rawtextLessThanState() {
        guard let ch = consume() else {
            emitChar("<")
            state = .rawtext
            return
        }
        if ch == "/" {
            tempBuffer = ""
            state = .rawtextEndTagOpen
        } else {
            emitChar("<")
            state = .rawtext
            reconsume()
        }
    }

    private func rawtextEndTagOpenState() {
        guard let ch = consume() else {
            emitString("</")
            state = .rawtext
            return
        }
        if ch.isASCIILetter {
            resetTag()
            currentTagIsEnd = true
            state = .rawtextEndTagName
            reconsume()
        } else {
            emitString("</")
            state = .rawtext
            reconsume()
        }
    }

    private func rawtextEndTagNameState() {
        guard let ch = consume() else {
            emitString("</")
            emitString(tempBuffer)
            state = .rawtext
            return
        }

        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            if tempBuffer.lowercased() == lastStartTagName.lowercased() {
                state = .beforeAttributeName
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rawtext
                reconsume()
            }
        case "/":
            if tempBuffer.lowercased() == lastStartTagName.lowercased() {
                state = .selfClosingStartTag
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rawtext
                reconsume()
            }
        case ">":
            if tempBuffer.lowercased() == lastStartTagName.lowercased() {
                currentTagName = tempBuffer.lowercased()
                state = .data
                emitCurrentTag()
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rawtext
                reconsume()
            }
        default:
            if ch.isASCIILetter {
                currentTagName.append(ch.asLowercaseCharacter)
                tempBuffer.append(ch)
            } else {
                emitString("</")
                emitString(tempBuffer)
                state = .rawtext
                reconsume()
            }
        }
    }

    private func beforeAttributeNameState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case "/", ">":
            state = ch == "/" ? .selfClosingStartTag : .data
            if ch == ">" {
                emitCurrentTag()
            }
        case "=":
            emitError("unexpected-equals-sign-before-attribute-name")
            currentAttrName = String(ch)
            state = .attributeName
        default:
            storeCurrentAttr()
            state = .attributeName
            reconsume()
        }
    }

    private func attributeNameState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ", "/", ">":
            storeCurrentAttr()
            state = ch == "/" ? .selfClosingStartTag : (ch == ">" ? .data : .afterAttributeName)
            if ch == ">" {
                emitCurrentTag()
            }
        case "=":
            state = .beforeAttributeValue
        case "\0":
            emitError("unexpected-null-character")
            currentAttrName.append("\u{FFFD}")
        case "\"", "'", "<":
            emitError("unexpected-character-in-attribute-name")
            currentAttrName.append(ch)
        default:
            currentAttrName.append(ch.asLowercaseCharacter)
        }
    }

    private func afterAttributeNameState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case "/":
            state = .selfClosingStartTag
        case "=":
            state = .beforeAttributeValue
        case ">":
            storeCurrentAttr()
            state = .data
            emitCurrentTag()
        default:
            storeCurrentAttr()
            state = .attributeName
            reconsume()
        }
    }

    private func beforeAttributeValueState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case "\"":
            state = .attributeValueDoubleQuoted
        case "'":
            state = .attributeValueSingleQuoted
        case ">":
            emitError("missing-attribute-value")
            storeCurrentAttr()
            state = .data
            emitCurrentTag()
        default:
            state = .attributeValueUnquoted
            reconsume()
        }
    }

    private func attributeValueDoubleQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\"":
            storeCurrentAttr()
            state = .afterAttributeValueQuoted
        case "&":
            returnState = .attributeValueDoubleQuoted
            state = .characterReference
        case "\0":
            emitError("unexpected-null-character")
            currentAttrValue.append("\u{FFFD}")
        default:
            currentAttrValue.append(ch)
        }
    }

    private func attributeValueSingleQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "'":
            storeCurrentAttr()
            state = .afterAttributeValueQuoted
        case "&":
            returnState = .attributeValueSingleQuoted
            state = .characterReference
        case "\0":
            emitError("unexpected-null-character")
            currentAttrValue.append("\u{FFFD}")
        default:
            currentAttrValue.append(ch)
        }
    }

    private func attributeValueUnquotedState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            storeCurrentAttr()
            state = .beforeAttributeName
        case "&":
            returnState = .attributeValueUnquoted
            state = .characterReference
        case ">":
            storeCurrentAttr()
            state = .data
            emitCurrentTag()
        case "\0":
            emitError("unexpected-null-character")
            currentAttrValue.append("\u{FFFD}")
        case "\"", "'", "<", "=", "`":
            emitError("unexpected-character-in-unquoted-attribute-value")
            currentAttrValue.append(ch)
        default:
            currentAttrValue.append(ch)
        }
    }

    private func afterAttributeValueQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .beforeAttributeName
        case "/":
            state = .selfClosingStartTag
        case ">":
            state = .data
            emitCurrentTag()
        default:
            emitError("missing-whitespace-between-attributes")
            state = .beforeAttributeName
            reconsume()
        }
    }

    private func selfClosingStartTagState() {
        guard let ch = consume() else {
            emitError("eof-in-tag")
            state = .data
            return
        }
        switch ch {
        case ">":
            currentTagSelfClosing = true
            state = .data
            emitCurrentTag()
        default:
            emitError("unexpected-solidus-in-tag")
            state = .beforeAttributeName
            reconsume()
        }
    }

    private func bogusCommentState() {
        guard let ch = consume() else {
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case ">":
            emitCurrentComment()
            state = .data
        case "\0":
            emitError("unexpected-null-character")
            currentComment.append("\u{FFFD}")
        default:
            currentComment.append(ch)
        }
    }

    private func markupDeclarationOpenState() {
        if consumeIf("--") {
            currentComment = ""
            state = .commentStart
        } else if consumeIf("DOCTYPE", caseInsensitive: true) {
            state = .doctype
        } else if consumeIf("[CDATA[", caseInsensitive: false) {
            // CDATA is only valid in foreign content (SVG/MathML)
            if let ns = sink?.currentNamespace, ns == .svg || ns == .math {
                // In foreign content - process as CDATA section
                state = .cdataSection
            } else {
                // In HTML - treat as bogus comment
                emitError("cdata-in-html-content")
                currentComment = "[CDATA["
                state = .bogusComment
            }
        } else {
            emitError("incorrectly-opened-comment")
            currentComment = ""
            state = .bogusComment
        }
    }

    private func commentStartState() {
        guard let ch = consume() else {
            emitError("eof-in-comment")
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case "-":
            state = .commentStartDash
        case ">":
            emitError("abrupt-closing-of-empty-comment")
            emitCurrentComment()
            state = .data
        default:
            state = .comment
            reconsume()
        }
    }

    private func commentStartDashState() {
        guard let ch = consume() else {
            emitError("eof-in-comment")
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case "-":
            state = .commentEnd
        case ">":
            emitError("abrupt-closing-of-empty-comment")
            emitCurrentComment()
            state = .data
        default:
            currentComment.append("-")
            state = .comment
            reconsume()
        }
    }

    private func commentState() {
        guard let ch = consume() else {
            emitError("eof-in-comment")
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case "<":
            currentComment.append(ch)
            // Could go to commentLessThanSign state, but simplified here
        case "-":
            state = .commentEndDash
        case "\0":
            emitError("unexpected-null-character")
            currentComment.append("\u{FFFD}")
        default:
            currentComment.append(ch)
        }
    }

    private func commentEndDashState() {
        guard let ch = consume() else {
            emitError("eof-in-comment")
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case "-":
            state = .commentEnd
        default:
            currentComment.append("-")
            state = .comment
            reconsume()
        }
    }

    private func commentEndState() {
        guard let ch = consume() else {
            emitError("eof-in-comment")
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case ">":
            emitCurrentComment()
            state = .data
        case "!":
            state = .commentEndBang
        case "-":
            currentComment.append("-")
        default:
            currentComment.append("--")
            state = .comment
            reconsume()
        }
    }

    private func commentEndBangState() {
        guard let ch = consume() else {
            emitError("eof-in-comment")
            emitCurrentComment()
            state = .data
            return
        }
        switch ch {
        case "-":
            currentComment.append("--!")
            state = .commentEndDash
        case ">":
            emitError("incorrectly-closed-comment")
            emitCurrentComment()
            state = .data
        default:
            currentComment.append("--!")
            state = .comment
            reconsume()
        }
    }

    private func doctypeState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .beforeDoctypeName
        case ">":
            state = .beforeDoctypeName
            reconsume()
        default:
            emitError("missing-whitespace-before-doctype-name")
            state = .beforeDoctypeName
            reconsume()
        }
    }

    private func beforeDoctypeNameState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case ">":
            emitError("missing-doctype-name")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        case "\0":
            emitError("unexpected-null-character")
            currentDoctypeName.append("\u{FFFD}")
            state = .doctypeName
        default:
            currentDoctypeName.append(ch.asLowercaseCharacter)
            state = .doctypeName
        }
    }

    private func doctypeNameState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .afterDoctypeName
        case ">":
            emitCurrentDoctype()
            state = .data
        case "\0":
            emitError("unexpected-null-character")
            currentDoctypeName.append("\u{FFFD}")
        default:
            currentDoctypeName.append(ch.asLowercaseCharacter)
        }
    }

    private func afterDoctypeNameState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case ">":
            emitCurrentDoctype()
            state = .data
        default:
            // Check for PUBLIC or SYSTEM
            reconsume()
            if consumeIf("PUBLIC", caseInsensitive: true) {
                state = .afterDoctypePublicKeyword
            } else if consumeIf("SYSTEM", caseInsensitive: true) {
                state = .afterDoctypeSystemKeyword
            } else {
                emitError("invalid-character-sequence-after-doctype-name")
                currentDoctypeForceQuirks = true
                state = .bogusDoctype
            }
        }
    }

    private func afterDoctypePublicKeywordState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .beforeDoctypePublicIdentifier
        case "\"":
            emitError("missing-whitespace-after-doctype-public-keyword")
            currentDoctypePublicId = ""
            state = .doctypePublicIdentifierDoubleQuoted
        case "'":
            emitError("missing-whitespace-after-doctype-public-keyword")
            currentDoctypePublicId = ""
            state = .doctypePublicIdentifierSingleQuoted
        case ">":
            emitError("missing-doctype-public-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            emitError("missing-quote-before-doctype-public-identifier")
            currentDoctypeForceQuirks = true
            state = .bogusDoctype
            reconsume()
        }
    }

    private func beforeDoctypePublicIdentifierState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case "\"":
            currentDoctypePublicId = ""
            state = .doctypePublicIdentifierDoubleQuoted
        case "'":
            currentDoctypePublicId = ""
            state = .doctypePublicIdentifierSingleQuoted
        case ">":
            emitError("missing-doctype-public-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            emitError("missing-quote-before-doctype-public-identifier")
            currentDoctypeForceQuirks = true
            state = .bogusDoctype
            reconsume()
        }
    }

    private func doctypePublicIdentifierDoubleQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\"":
            state = .afterDoctypePublicIdentifier
        case "\0":
            emitError("unexpected-null-character")
            currentDoctypePublicId?.append("\u{FFFD}")
        case ">":
            emitError("abrupt-doctype-public-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            currentDoctypePublicId?.append(ch)
        }
    }

    private func doctypePublicIdentifierSingleQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "'":
            state = .afterDoctypePublicIdentifier
        case "\0":
            emitError("unexpected-null-character")
            currentDoctypePublicId?.append("\u{FFFD}")
        case ">":
            emitError("abrupt-doctype-public-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            currentDoctypePublicId?.append(ch)
        }
    }

    private func afterDoctypePublicIdentifierState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .betweenDoctypePublicAndSystemIdentifiers
        case ">":
            emitCurrentDoctype()
            state = .data
        case "\"":
            emitError("missing-whitespace-between-doctype-public-and-system-identifiers")
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierDoubleQuoted
        case "'":
            emitError("missing-whitespace-between-doctype-public-and-system-identifiers")
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierSingleQuoted
        default:
            emitError("missing-quote-before-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            state = .bogusDoctype
            reconsume()
        }
    }

    private func betweenDoctypePublicAndSystemIdentifiersState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case ">":
            emitCurrentDoctype()
            state = .data
        case "\"":
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierDoubleQuoted
        case "'":
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierSingleQuoted
        default:
            emitError("missing-quote-before-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            state = .bogusDoctype
            reconsume()
        }
    }

    private func afterDoctypeSystemKeywordState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            state = .beforeDoctypeSystemIdentifier
        case "\"":
            emitError("missing-whitespace-after-doctype-system-keyword")
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierDoubleQuoted
        case "'":
            emitError("missing-whitespace-after-doctype-system-keyword")
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierSingleQuoted
        case ">":
            emitError("missing-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            emitError("missing-quote-before-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            state = .bogusDoctype
            reconsume()
        }
    }

    private func beforeDoctypeSystemIdentifierState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case "\"":
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierDoubleQuoted
        case "'":
            currentDoctypeSystemId = ""
            state = .doctypeSystemIdentifierSingleQuoted
        case ">":
            emitError("missing-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            emitError("missing-quote-before-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            state = .bogusDoctype
            reconsume()
        }
    }

    private func doctypeSystemIdentifierDoubleQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\"":
            state = .afterDoctypeSystemIdentifier
        case "\0":
            emitError("unexpected-null-character")
            currentDoctypeSystemId?.append("\u{FFFD}")
        case ">":
            emitError("abrupt-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            currentDoctypeSystemId?.append(ch)
        }
    }

    private func doctypeSystemIdentifierSingleQuotedState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "'":
            state = .afterDoctypeSystemIdentifier
        case "\0":
            emitError("unexpected-null-character")
            currentDoctypeSystemId?.append("\u{FFFD}")
        case ">":
            emitError("abrupt-doctype-system-identifier")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            state = .data
        default:
            currentDoctypeSystemId?.append(ch)
        }
    }

    private func afterDoctypeSystemIdentifierState() {
        guard let ch = consume() else {
            emitError("eof-in-doctype")
            currentDoctypeForceQuirks = true
            emitCurrentDoctype()
            return
        }
        switch ch {
        case "\t", "\n", "\u{0C}", " ":
            // Ignore
            break
        case ">":
            emitCurrentDoctype()
            state = .data
        default:
            emitError("unexpected-character-after-doctype-system-identifier")
            state = .bogusDoctype
            reconsume()
        }
    }

    private func bogusDoctypeState() {
        guard let ch = consume() else {
            emitCurrentDoctype()
            return
        }
        switch ch {
        case ">":
            emitCurrentDoctype()
            state = .data
        case "\0":
            emitError("unexpected-null-character")
        default:
            break
        }
    }

    // MARK: - Character Reference States

    private var isInAttribute: Bool {
        return returnState == .attributeValueDoubleQuoted ||
               returnState == .attributeValueSingleQuoted ||
               returnState == .attributeValueUnquoted
    }

    private func flushCharRefTempBuffer() {
        if isInAttribute {
            currentAttrValue.append(charRefTempBuffer)
        } else {
            emitString(charRefTempBuffer)
        }
        charRefTempBuffer = ""
    }

    private func emitCharRefChar(_ ch: Character) {
        if isInAttribute {
            currentAttrValue.append(ch)
        } else {
            emitChar(ch)
        }
    }

    private func emitCharRefString(_ s: String) {
        if isInAttribute {
            currentAttrValue.append(s)
        } else {
            emitString(s)
        }
    }

    private func characterReferenceState() {
        charRefTempBuffer = "&"

        guard let ch = consume() else {
            flushCharRefTempBuffer()
            state = returnState
            return
        }

        if ch.isASCIILetter || ch.isASCIIDigit {
            state = .namedCharacterReference
            reconsume()
        } else if ch == "#" {
            charRefTempBuffer.append(ch)
            state = .numericCharacterReference
        } else {
            flushCharRefTempBuffer()
            state = returnState
            reconsume()
        }
    }

    private func namedCharacterReferenceState() {
        // Collect alphanumeric characters
        var entityName = ""
        var matchedEntity: String? = nil
        var matchedLength = 0
        var consumed = 0

        while let ch = peek() {
            if ch.isASCIILetter || ch.isASCIIDigit {
                entityName.append(ch)
                _ = consume()
                consumed += 1

                // Check for match
                if let decoded = NAMED_ENTITIES[entityName] {
                    matchedEntity = decoded
                    matchedLength = consumed
                }
            } else {
                break
            }
        }

        // Check for semicolon
        let hasSemicolon = peek() == ";"
        if hasSemicolon && matchedEntity != nil {
            _ = consume()  // consume the semicolon
            emitCharRefString(matchedEntity!)
            state = returnState
            return
        }

        // Try to use the longest match
        if let match = matchedEntity {
            // In attributes, legacy entities without semicolon followed by alphanumeric or = are not decoded
            if isInAttribute {
                let nextChar = peek()
                if nextChar != nil && (nextChar!.isASCIILetter || nextChar!.isASCIIDigit || nextChar! == "=") {
                    // Don't decode - emit as is
                    flushCharRefTempBuffer()
                    emitCharRefString(entityName)
                    state = returnState
                    return
                }
            }

            // Check if this is a legacy entity
            let matchedName = String(entityName.prefix(matchedLength))
            if LEGACY_ENTITIES.contains(matchedName) {
                // Unconsume the extra characters
                for _ in 0..<(consumed - matchedLength) {
                    reconsume()
                }
                if !hasSemicolon {
                    emitError("missing-semicolon-after-character-reference")
                }
                emitCharRefString(match)
                state = returnState
                return
            }
        }

        // No match - emit everything as text
        flushCharRefTempBuffer()
        // Put back all consumed characters except the first (which is in tempBuffer)
        for _ in 0..<consumed {
            reconsume()
        }
        state = .ambiguousAmpersand
    }

    private func ambiguousAmpersandState() {
        guard let ch = consume() else {
            state = returnState
            return
        }

        if ch.isASCIILetter || ch.isASCIIDigit {
            if isInAttribute {
                currentAttrValue.append(ch)
            } else {
                emitChar(ch)
            }
        } else if ch == ";" {
            emitError("unknown-named-character-reference")
            state = returnState
            reconsume()
        } else {
            state = returnState
            reconsume()
        }
    }

    private func numericCharacterReferenceState() {
        charRefCode = 0

        guard let ch = consume() else {
            state = .decimalCharacterReferenceStart
            reconsume()
            return
        }

        if ch == "x" || ch == "X" {
            charRefTempBuffer.append(ch)
            state = .hexadecimalCharacterReferenceStart
        } else {
            state = .decimalCharacterReferenceStart
            reconsume()
        }
    }

    private func hexadecimalCharacterReferenceStartState() {
        guard let ch = consume() else {
            emitError("absence-of-digits-in-numeric-character-reference")
            flushCharRefTempBuffer()
            state = returnState
            return
        }

        if ch.isHexDigit {
            state = .hexadecimalCharacterReference
            reconsume()
        } else {
            emitError("absence-of-digits-in-numeric-character-reference")
            flushCharRefTempBuffer()
            state = returnState
            reconsume()
        }
    }

    private func decimalCharacterReferenceStartState() {
        guard let ch = consume() else {
            emitError("absence-of-digits-in-numeric-character-reference")
            flushCharRefTempBuffer()
            state = returnState
            return
        }

        if ch.isASCIIDigit {
            state = .decimalCharacterReference
            reconsume()
        } else {
            emitError("absence-of-digits-in-numeric-character-reference")
            flushCharRefTempBuffer()
            state = returnState
            reconsume()
        }
    }

    private func hexadecimalCharacterReferenceState() {
        guard let ch = consume() else {
            state = .numericCharacterReferenceEnd
            return
        }

        if ch.isASCIIDigit {
            charRefCode = charRefCode &* 16 &+ UInt32(ch.asciiValue! - 0x30)
        } else if ch >= "A" && ch <= "F" {
            charRefCode = charRefCode &* 16 &+ UInt32(ch.asciiValue! - 0x37)
        } else if ch >= "a" && ch <= "f" {
            charRefCode = charRefCode &* 16 &+ UInt32(ch.asciiValue! - 0x57)
        } else if ch == ";" {
            state = .numericCharacterReferenceEnd
        } else {
            emitError("missing-semicolon-after-character-reference")
            state = .numericCharacterReferenceEnd
            reconsume()
        }
    }

    private func decimalCharacterReferenceState() {
        guard let ch = consume() else {
            state = .numericCharacterReferenceEnd
            return
        }

        if ch.isASCIIDigit {
            charRefCode = charRefCode &* 10 &+ UInt32(ch.asciiValue! - 0x30)
        } else if ch == ";" {
            state = .numericCharacterReferenceEnd
        } else {
            emitError("missing-semicolon-after-character-reference")
            state = .numericCharacterReferenceEnd
            reconsume()
        }
    }

    private func numericCharacterReferenceEndState() {
        // Apply replacements and validation per spec
        let decoded = decodeNumericEntity(String(charRefCode, radix: 10), isHex: false)

        // Check for various error conditions
        if charRefCode == 0 {
            emitError("null-character-reference")
        } else if charRefCode > 0x10FFFF {
            emitError("character-reference-outside-unicode-range")
        } else if charRefCode >= 0xD800 && charRefCode <= 0xDFFF {
            emitError("surrogate-character-reference")
        } else if (charRefCode >= 0xFDD0 && charRefCode <= 0xFDEF) ||
                  (charRefCode & 0xFFFF) == 0xFFFE ||
                  (charRefCode & 0xFFFF) == 0xFFFF {
            emitError("noncharacter-character-reference")
        } else if charRefCode < 0x20 && charRefCode != 0x09 && charRefCode != 0x0A && charRefCode != 0x0C ||
                  (charRefCode >= 0x7F && charRefCode <= 0x9F) {
            emitError("control-character-reference")
        }

        // Decode the code point (with possible replacement)
        let result: String
        if charRefCode == 0 {
            result = "\u{FFFD}"
        } else if charRefCode > 0x10FFFF {
            result = "\u{FFFD}"
        } else if charRefCode >= 0xD800 && charRefCode <= 0xDFFF {
            result = "\u{FFFD}"
        } else {
            // Check for windows-1252 replacements
            let replacements: [UInt32: UInt32] = [
                0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
                0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
                0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
                0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
                0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
                0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
                0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178
            ]
            let finalCode = replacements[charRefCode] ?? charRefCode
            if let scalar = Unicode.Scalar(finalCode) {
                result = String(Character(scalar))
            } else {
                result = "\u{FFFD}"
            }
        }

        charRefTempBuffer = ""
        emitCharRefString(result)
        state = returnState
    }

    // MARK: - CDATA States

    private func cdataSectionState() {
        guard let ch = consume() else {
            emitError("eof-in-cdata")
            return
        }

        if ch == "]" {
            state = .cdataSectionBracket
        } else {
            emitChar(ch)
        }
    }

    private func cdataSectionBracketState() {
        guard let ch = consume() else {
            emitChar("]")
            state = .cdataSection
            return
        }

        if ch == "]" {
            state = .cdataSectionEnd
        } else {
            emitChar("]")
            state = .cdataSection
            reconsume()
        }
    }

    private func cdataSectionEndState() {
        guard let ch = consume() else {
            emitString("]]")
            state = .cdataSection
            return
        }

        if ch == "]" {
            emitChar("]")
        } else if ch == ">" {
            state = .data
        } else {
            emitString("]]")
            state = .cdataSection
            reconsume()
        }
    }
}

// MARK: - Character Extensions

extension Character {
    var isASCIILetter: Bool {
        return ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    var isASCIIDigit: Bool {
        return ("0"..."9").contains(self)
    }

    var isHexDigit: Bool {
        return isASCIIDigit || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }

    var asLowercaseCharacter: Character {
        return Character(String(self).lowercased())
    }
}

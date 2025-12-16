// Tokenizer.swift - HTML5 tokenizer state machine

import Foundation

/// Protocol for receiving tokens from the tokenizer
public protocol TokenSink: AnyObject {
    func processToken(_ token: Token)
}

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

        while pos < input.endIndex {
            processState()
        }

        // Flush any remaining character buffer
        flushCharBuffer()

        // Emit EOF
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
        default:
            // For unimplemented states, just consume and move on
            _ = consume()
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
        guard let ch = consume() else { return }
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
        guard let ch = consume() else { return }
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
        guard let ch = consume() else { return }
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
        guard let ch = consume() else { return }
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
            // For now, treat CDATA as bogus comment in HTML
            emitError("cdata-in-html-content")
            currentComment = "[CDATA["
            state = .bogusComment
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
}

// MARK: - Character Extensions

extension Character {
    var isASCIILetter: Bool {
        return ("a"..."z").contains(self) || ("A"..."Z").contains(self)
    }

    var asLowercaseCharacter: Character {
        return Character(String(self).lowercased())
    }
}

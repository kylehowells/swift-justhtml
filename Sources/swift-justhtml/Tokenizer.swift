// Tokenizer.swift - HTML5 tokenizer state machine

import Foundation

// MARK: - TokenSink

/// Protocol for receiving tokens from the tokenizer
public protocol TokenSink: AnyObject {
	func processToken(_ token: Token)
	/// Current element's namespace (for rawtext state switching)
	var currentNamespace: Namespace? { get }
}

/// Script element needs SCRIPT DATA state
private let SCRIPT_ELEMENT = "script"

/// RCDATA elements that switch tokenizer to RCDATA state.
private func isRCDATAElement(_ name: String) -> Bool {
	switch name {
		case "title", "textarea":
			return true
		default:
			return false
	}
}

/// RAWTEXT elements that switch tokenizer to RAWTEXT state.
private func isRAWTEXTElement(_ name: String) -> Bool {
	switch name {
		case "style", "xmp", "iframe", "noembed", "noframes":
			return true
		default:
			return false
	}
}

/// Preprocess line endings per HTML5 spec
/// CR (U+000D) followed by LF (U+000A) → LF
/// CR (U+000D) not followed by LF → LF
/// Uses scalar iteration for consistent cross-platform behavior
private func preprocessLineEndings(_ html: String) -> String {
	// Fast path: check if there's any CR to process
	var hasCR = false
	for scalar in html.unicodeScalars {
		if scalar == "\r" {
			hasCR = true
			break
		}
	}
	if !hasCR { return html }

	// Process CR/CRLF to LF
	var result = ""
	result.reserveCapacity(html.count)
	var prevWasCR = false

	for scalar in html.unicodeScalars {
		if scalar == "\r" {
			result.append("\n")
			prevWasCR = true
		}
		else if scalar == "\n", prevWasCR {
			// Skip LF after CR (already converted CR to LF)
			prevWasCR = false
		}
		else {
			result.unicodeScalars.append(scalar)
			prevWasCR = false
		}
	}

	return result
}

/// Coerce text for XML compatibility
/// - Form feed (U+000C) → space
/// - Noncharacters (U+FDD0-U+FDEF, U+xFFFE/U+xFFFF) → replacement character
private func coerceTextForXML(_ text: String) -> String {
	var result = ""
	result.reserveCapacity(text.count)
	var changed = false

	for scalar in text.unicodeScalars {
		let cp = scalar.value
		// Form feed → space
		if cp == 0x0C {
			result.unicodeScalars.append(" ")
			changed = true
			continue
		}
		// Noncharacter range U+FDD0-U+FDEF
		if cp >= 0xFDD0, cp <= 0xFDEF {
			result.unicodeScalars.append("\u{FFFD}")
			changed = true
			continue
		}
		// Noncharacters U+xFFFE and U+xFFFF on all planes
		let low16 = cp & 0xFFFF
		if low16 == 0xFFFE || low16 == 0xFFFF {
			result.unicodeScalars.append("\u{FFFD}")
			changed = true
			continue
		}
		result.unicodeScalars.append(scalar)
	}

	return changed ? result : text
}

/// Coerce comment for XML compatibility
/// - Double hyphens (--) → (- -) with space
private func coerceCommentForXML(_ text: String) -> String {
	guard text.contains("--") else { return text }

	return text.replacingOccurrences(of: "--", with: "- -")
}

// MARK: - TokenizerOpts

/// Tokenizer options
public struct TokenizerOpts {
	public var initialState: Tokenizer.State
	public var initialRawtextTag: String? = nil
	public var xmlCoercion: Bool
	public var discardBom: Bool
	public var scripting: Bool
	public var trackLocations: Bool
	/// Maximum length for named character reference entity names (DoS protection)
	public var maxEntityNameLength: Int

	public init(
		initialState: Tokenizer.State = .data,
		initialRawtextTag: String? = nil,
		xmlCoercion: Bool = false,
		discardBom: Bool = false,
		scripting: Bool = false,
		trackLocations: Bool = true,
		maxEntityNameLength: Int = ParserLimits.default.maxEntityNameLength
	) {
		self.initialState = initialState
		self.initialRawtextTag = initialRawtextTag
		self.xmlCoercion = xmlCoercion
		self.discardBom = discardBom
		self.scripting = scripting
		self.trackLocations = trackLocations
		self.maxEntityNameLength = maxEntityNameLength
	}
}

// MARK: - Tokenizer

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
		case scriptDataEscapeStart
		case scriptDataEscapeStartDash
		case scriptDataEscaped
		case scriptDataEscapedDash
		case scriptDataEscapedDashDash
		case scriptDataEscapedLessThan
		case scriptDataEscapedEndTagOpen
		case scriptDataEscapedEndTagName
		case scriptDataDoubleEscapeStart
		case scriptDataDoubleEscaped
		case scriptDataDoubleEscapedDash
		case scriptDataDoubleEscapedDashDash
		case scriptDataDoubleEscapedLessThan
		case scriptDataDoubleEscapeEnd
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

	private let sink: TokenSink
	private let opts: TokenizerOpts

	private var state: State
	private var returnState: State = .data
	// UTF-8 byte-based input for performance
	private var inputBytes: ContiguousArray<UInt8> = []
	private var pos: Int = 0
	private var inputLength: Int = 0
	private var line: Int = 1
	private var column: Int = 0
	private let trackLocations: Bool
	private var emittedEOF: Bool = false
	private var eofDrainIterations: Int = 0

	public var currentLine: Int {
		return self.line
	}

	public var currentColumn: Int {
		return self.column
	}

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

	/// Character buffer (bytes - converted to String only when flushing)
	private var charBuffer: ContiguousArray<UInt8> = []

	/// Reusable buffer for tag/attribute name scanning (avoids allocation per tag)
	private var nameBuffer: ContiguousArray<UInt8> = []

	// Temporary buffer for rawtext/rcdata end tag matching
	private var tempBuffer: String = ""
	private var lastStartTagName: String = ""

	// Character reference state
	private var charRefCode: UInt32 = 0
	private var charRefTempBuffer: String = ""

	// Error collection
	public var errors: [ParseError] = []
	private var collectErrors: Bool

	public init(_ sink: TokenSink, opts: TokenizerOpts = TokenizerOpts(), collectErrors: Bool = false)
	{
		self.sink = sink
		self.opts = opts
		self.state = opts.initialState
		self.collectErrors = collectErrors
		self.trackLocations = opts.trackLocations || collectErrors
		self.pos = 0
		if let rawtextTag = opts.initialRawtextTag {
			self.lastStartTagName = rawtextTag
		}
	}

	public func run(_ html: String) {
		self.startIncrementalRun(html)

		while self.pumpIncrementalRun() {}
	}

	internal func startIncrementalRun(_ html: String) {
		// Preprocess input: normalize line endings per HTML5 spec
		// CR (U+000D) followed by LF (U+000A) → LF
		// CR (U+000D) not followed by LF → LF
		// Note: Always process, don't rely on contains() which may have platform differences
		let preprocessed = preprocessLineEndings(html)

		self.state = self.opts.initialState
		self.returnState = .data
		self.pos = 0
		self.line = 1
		self.column = 0
		self.emittedEOF = false
		self.eofDrainIterations = 0

		self.currentTagName = ""
		self.currentTagIsEnd = false
		self.currentTagSelfClosing = false
		self.currentAttrs.removeAll(keepingCapacity: true)
		self.currentAttrName = ""
		self.currentAttrValue = ""
		self.currentComment = ""
		self.currentDoctypeName = ""
		self.currentDoctypePublicId = nil
		self.currentDoctypeSystemId = nil
		self.currentDoctypeForceQuirks = false
		self.charBuffer.removeAll(keepingCapacity: true)
		self.nameBuffer.removeAll(keepingCapacity: true)
		self.tempBuffer = ""
		self.lastStartTagName = self.opts.initialRawtextTag ?? ""
		self.charRefCode = 0
		self.charRefTempBuffer = ""
		self.errors.removeAll(keepingCapacity: true)

		// Convert to UTF-8 bytes for fast processing
		self.inputBytes = ContiguousArray(preprocessed.utf8)
		self.inputLength = self.inputBytes.count

		// Optionally discard BOM (EF BB BF in UTF-8)
		if self.opts.discardBom, self.inputLength >= 3,
		   self.inputBytes[0] == 0xEF, self.inputBytes[1] == 0xBB, self.inputBytes[2] == 0xBF
		{
			self.pos = 3
		}
	}

	@discardableResult
	internal func pumpIncrementalRun() -> Bool {
		if self.emittedEOF {
			return false
		}

		if self.pos < self.inputLength {
			self.processState()
			return !self.emittedEOF
		}

		// Handle EOF - process remaining states until we reach data state
		if self.state != .data, self.eofDrainIterations < 100 {
			self.processState()
			self.eofDrainIterations += 1
			return !self.emittedEOF
		}

		self.emitEOF()
		return false
	}

	/// Switch to plaintext state (called by tree builder for plaintext element)
	public func switchToPlaintext() {
		self.state = .plaintext
	}

	private func processState() {
		switch self.state {
			case .data:
				self.dataState()

			case .rcdata:
				self.rcdataState()

			case .rawtext:
				self.rawtextState()

			case .plaintext:
				self.plaintextState()

			case .tagOpen:
				self.tagOpenState()

			case .endTagOpen:
				self.endTagOpenState()

			case .tagName:
				self.tagNameState()

			case .rcdataLessThan:
				self.rcdataLessThanState()

			case .rcdataEndTagOpen:
				self.rcdataEndTagOpenState()

			case .rcdataEndTagName:
				self.rcdataEndTagNameState()

			case .rawtextLessThan:
				self.rawtextLessThanState()

			case .rawtextEndTagOpen:
				self.rawtextEndTagOpenState()

			case .rawtextEndTagName:
				self.rawtextEndTagNameState()

			case .beforeAttributeName:
				self.beforeAttributeNameState()

			case .attributeName:
				self.attributeNameState()

			case .afterAttributeName:
				self.afterAttributeNameState()

			case .beforeAttributeValue:
				self.beforeAttributeValueState()

			case .attributeValueDoubleQuoted:
				self.attributeValueDoubleQuotedState()

			case .attributeValueSingleQuoted:
				self.attributeValueSingleQuotedState()

			case .attributeValueUnquoted:
				self.attributeValueUnquotedState()

			case .afterAttributeValueQuoted:
				self.afterAttributeValueQuotedState()

			case .selfClosingStartTag:
				self.selfClosingStartTagState()

			case .bogusComment:
				self.bogusCommentState()

			case .markupDeclarationOpen:
				self.markupDeclarationOpenState()

			case .commentStart:
				self.commentStartState()

			case .commentStartDash:
				self.commentStartDashState()

			case .comment:
				self.commentState()

			case .commentEndDash:
				self.commentEndDashState()

			case .commentEnd:
				self.commentEndState()

			case .commentEndBang:
				self.commentEndBangState()

			case .doctype:
				self.doctypeState()

			case .beforeDoctypeName:
				self.beforeDoctypeNameState()

			case .doctypeName:
				self.doctypeNameState()

			case .afterDoctypeName:
				self.afterDoctypeNameState()

			case .afterDoctypePublicKeyword:
				self.afterDoctypePublicKeywordState()

			case .beforeDoctypePublicIdentifier:
				self.beforeDoctypePublicIdentifierState()

			case .doctypePublicIdentifierDoubleQuoted:
				self.doctypePublicIdentifierDoubleQuotedState()

			case .doctypePublicIdentifierSingleQuoted:
				self.doctypePublicIdentifierSingleQuotedState()

			case .afterDoctypePublicIdentifier:
				self.afterDoctypePublicIdentifierState()

			case .betweenDoctypePublicAndSystemIdentifiers:
				self.betweenDoctypePublicAndSystemIdentifiersState()

			case .afterDoctypeSystemKeyword:
				self.afterDoctypeSystemKeywordState()

			case .beforeDoctypeSystemIdentifier:
				self.beforeDoctypeSystemIdentifierState()

			case .doctypeSystemIdentifierDoubleQuoted:
				self.doctypeSystemIdentifierDoubleQuotedState()

			case .doctypeSystemIdentifierSingleQuoted:
				self.doctypeSystemIdentifierSingleQuotedState()

			case .afterDoctypeSystemIdentifier:
				self.afterDoctypeSystemIdentifierState()

			case .bogusDoctype:
				self.bogusDoctypeState()

			case .characterReference:
				self.characterReferenceState()

			case .namedCharacterReference:
				self.namedCharacterReferenceState()

			case .ambiguousAmpersand:
				self.ambiguousAmpersandState()

			case .numericCharacterReference:
				self.numericCharacterReferenceState()

			case .hexadecimalCharacterReferenceStart:
				self.hexadecimalCharacterReferenceStartState()

			case .decimalCharacterReferenceStart:
				self.decimalCharacterReferenceStartState()

			case .hexadecimalCharacterReference:
				self.hexadecimalCharacterReferenceState()

			case .decimalCharacterReference:
				self.decimalCharacterReferenceState()

			case .numericCharacterReferenceEnd:
				self.numericCharacterReferenceEndState()

			case .cdataSection:
				self.cdataSectionState()

			case .cdataSectionBracket:
				self.cdataSectionBracketState()

			case .cdataSectionEnd:
				self.cdataSectionEndState()

			case .scriptData:
				self.scriptDataState()

			case .scriptDataLessThan:
				self.scriptDataLessThanState()

			case .scriptDataEndTagOpen:
				self.scriptDataEndTagOpenState()

			case .scriptDataEndTagName:
				self.scriptDataEndTagNameState()

			case .scriptDataEscapeStart:
				self.scriptDataEscapeStartState()

			case .scriptDataEscapeStartDash:
				self.scriptDataEscapeStartDashState()

			case .scriptDataEscaped:
				self.scriptDataEscapedState()

			case .scriptDataEscapedDash:
				self.scriptDataEscapedDashState()

			case .scriptDataEscapedDashDash:
				self.scriptDataEscapedDashDashState()

			case .scriptDataEscapedLessThan:
				self.scriptDataEscapedLessThanState()

			case .scriptDataEscapedEndTagOpen:
				self.scriptDataEscapedEndTagOpenState()

			case .scriptDataEscapedEndTagName:
				self.scriptDataEscapedEndTagNameState()

			case .scriptDataDoubleEscapeStart:
				self.scriptDataDoubleEscapeStartState()

			case .scriptDataDoubleEscaped:
				self.scriptDataDoubleEscapedState()

			case .scriptDataDoubleEscapedDash:
				self.scriptDataDoubleEscapedDashState()

			case .scriptDataDoubleEscapedDashDash:
				self.scriptDataDoubleEscapedDashDashState()

			case .scriptDataDoubleEscapedLessThan:
				self.scriptDataDoubleEscapedLessThanState()

			case .scriptDataDoubleEscapeEnd:
				self.scriptDataDoubleEscapeEndState()
		}
	}

	// MARK: - Character Consumption

	/// Consume the next character from the input
	/// Returns nil at EOF
	@inline(__always)
	private func consume() -> Character? {
		guard self.pos < self.inputLength else { return nil }

		let byte = self.inputBytes[self.pos]
		self.pos += 1

		// Fast path for ASCII (most common in HTML)
		if byte < 0x80 {
			self.advanceLocation(for: byte)
			return Character(UnicodeScalar(byte))
		}

		// Multi-byte UTF-8 sequence
		self.advanceColumn()
		return self.decodeUTF8(startingWith: byte)
	}

	/// Decode a multi-byte UTF-8 sequence starting with the given byte
	@inline(__always)
	private func decodeUTF8(startingWith firstByte: UInt8) -> Character {
		// 2-byte sequence: 110xxxxx 10xxxxxx
		if firstByte & 0xE0 == 0xC0 {
			guard self.pos < self.inputLength else { return "\u{FFFD}" }

			let b2 = self.inputBytes[self.pos]
			self.pos += 1
			let codepoint = UInt32(firstByte & 0x1F) << 6 | UInt32(b2 & 0x3F)
			if let scalar = Unicode.Scalar(codepoint) {
				return Character(scalar)
			}
			return "\u{FFFD}"
		}

		// 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx
		if firstByte & 0xF0 == 0xE0 {
			guard self.pos + 1 < self.inputLength else { return "\u{FFFD}" }

			let b2 = self.inputBytes[self.pos]
			let b3 = self.inputBytes[self.pos + 1]
			self.pos += 2
			let codepoint = UInt32(firstByte & 0x0F) << 12 | UInt32(b2 & 0x3F) << 6 | UInt32(b3 & 0x3F)
			if let scalar = Unicode.Scalar(codepoint) {
				return Character(scalar)
			}
			return "\u{FFFD}"
		}

		// 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
		if firstByte & 0xF8 == 0xF0 {
			guard self.pos + 2 < self.inputLength else { return "\u{FFFD}" }

			let b2 = self.inputBytes[self.pos]
			let b3 = self.inputBytes[self.pos + 1]
			let b4 = self.inputBytes[self.pos + 2]
			self.pos += 3
			let codepoint =
				UInt32(firstByte & 0x07) << 18 | UInt32(b2 & 0x3F) << 12
					| UInt32(b3 & 0x3F) << 6 | UInt32(b4 & 0x3F)
			if let scalar = Unicode.Scalar(codepoint) {
				return Character(scalar)
			}
			return "\u{FFFD}"
		}

		// Invalid UTF-8
		return "\u{FFFD}"
	}

	/// Peek at the next character without consuming it
	@inline(__always)
	private func peek() -> Character? {
		guard self.pos < self.inputLength else { return nil }

		let byte = self.inputBytes[self.pos]

		// Fast path for ASCII
		if byte < 0x80 {
			return Character(UnicodeScalar(byte))
		}

		// For multi-byte, decode without advancing position
		let savedPos = self.pos
		self.pos += 1
		let ch = self.decodeUTF8(startingWith: byte)
		self.pos = savedPos
		return ch
	}

	/// Put the last consumed character back
	@inline(__always)
	private func reconsume() {
		guard self.pos > 0 else { return }

		// Move back one byte first
		self.pos -= 1

		// Check if we need to move back more for multi-byte sequences
		// Walk back to find the start of the UTF-8 character
		while self.pos > 0, self.inputBytes[self.pos] & 0xC0 == 0x80 {
			self.pos -= 1
		}

		if self.trackLocations {
			// Adjust line/column tracking
			if self.inputBytes[self.pos] == 0x0A { // '\n'
				self.line -= 1
				// column tracking becomes inaccurate here but that's OK
			}
			else {
				self.column -= 1
			}
		}
	}

	private func consumeIf(_ expected: String, caseInsensitive: Bool = true) -> Bool {
		var tempPos = self.pos

		for expectedByte in expected.utf8 {
			guard tempPos < self.inputLength else { return false }

			let inputByte = self.inputBytes[tempPos]

			let match: Bool
			if caseInsensitive {
				// ASCII case-insensitive comparison
				let inputLower = (inputByte >= 0x41 && inputByte <= 0x5A) ? inputByte + 32 : inputByte
				let expectedLower =
					(expectedByte >= 0x41 && expectedByte <= 0x5A) ? expectedByte + 32 : expectedByte
				match = inputLower == expectedLower
			}
			else {
				match = inputByte == expectedByte
			}

			if !match { return false }
			tempPos += 1
		}

		// Consume the matched characters
		self.pos = tempPos
		if self.trackLocations {
			self.column += expected.utf8.count
		}
		return true
	}

	@inline(__always)
	private func advanceColumn() {
		if self.trackLocations {
			self.column += 1
		}
	}

	@inline(__always)
	private func advanceColumns(_ count: Int) {
		if self.trackLocations {
			self.column += count
		}
	}

	@inline(__always)
	private func advanceLocation(for byte: UInt8) {
		guard self.trackLocations else { return }
		if byte == 0x0A {
			self.line += 1
			self.column = 0
		}
		else {
			self.column += 1
		}
	}

	// MARK: - Token Emission

	@inline(__always)
	private func emit(_ token: Token) {
		self.flushCharBuffer()
		self.sink.processToken(token)
	}

	@inline(__always)
	private func emitEOF() {
		guard !self.emittedEOF else { return }

		self.emittedEOF = true
		self.emit(.eof)
	}

	@inline(__always)
	private func emitChar(_ ch: Character) {
		// Convert character to UTF-8 bytes
		for byte in String(ch).utf8 {
			self.charBuffer.append(byte)
		}
	}

	@inline(__always)
	private func emitString(_ s: String) {
		// Append string as UTF-8 bytes
		for byte in s.utf8 {
			self.charBuffer.append(byte)
		}
	}

	@inline(__always)
	private func emitByte(_ byte: UInt8) {
		self.charBuffer.append(byte)
	}

	@inline(__always)
	private func emitBytes(_ bytes: ArraySlice<UInt8>) {
		self.charBuffer.append(contentsOf: bytes)
	}

	private func flushCharBuffer() {
		if !self.charBuffer.isEmpty {
			// Convert bytes to String only when flushing
			var text = String(decoding: self.charBuffer, as: UTF8.self)
			if self.opts.xmlCoercion {
				text = coerceTextForXML(text)
			}
			self.sink.processToken(.character(text))
			self.charBuffer.removeAll(keepingCapacity: true)
		}
	}

	private func emitCurrentTag() {
		self.flushCharBuffer()
		if self.currentTagIsEnd {
			self.sink.processToken(.endTag(name: self.currentTagName))
		}
		else {
			self.sink.processToken(
				.startTag(
					name: self.currentTagName, attrs: self.currentAttrs,
					selfClosing: self.currentTagSelfClosing))
			self.lastStartTagName = self.currentTagName

			// Switch to appropriate state for special elements (only in HTML namespace)
			let ns = self.sink.currentNamespace
			if ns == nil || ns == .html {
				if isRCDATAElement(self.currentTagName) {
					self.state = .rcdata
				}
				else if isRAWTEXTElement(self.currentTagName) {
					self.state = .rawtext
				}
				else if self.currentTagName == "noscript", self.opts.scripting {
					// When scripting is enabled, noscript content is raw text
					self.state = .rawtext
				}
				else if self.currentTagName == SCRIPT_ELEMENT {
					self.state = .scriptData
				}
				else if self.currentTagName == "plaintext" {
					self.state = .plaintext
				}
			}
		}
		self.resetTag()
	}

	private func emitCurrentComment() {
		var comment = self.currentComment
		if self.opts.xmlCoercion {
			comment = coerceCommentForXML(comment)
		}
		self.emit(.comment(comment))
		self.currentComment = ""
	}

	private func emitCurrentDoctype() {
		let doctype = Doctype(
			name: currentDoctypeName.isEmpty ? nil : self.currentDoctypeName,
			publicId: self.currentDoctypePublicId,
			systemId: self.currentDoctypeSystemId,
			forceQuirks: self.currentDoctypeForceQuirks
		)
		self.emit(.doctype(doctype))
		self.resetDoctype()
	}

	private func resetTag() {
		self.currentTagName = ""
		self.currentTagIsEnd = false
		self.currentTagSelfClosing = false
		self.currentAttrs = [:]
		self.currentAttrName = ""
		self.currentAttrValue = ""
	}

	private func resetDoctype() {
		self.currentDoctypeName = ""
		self.currentDoctypePublicId = nil
		self.currentDoctypeSystemId = nil
		self.currentDoctypeForceQuirks = false
	}

	private func storeCurrentAttr() {
		if !self.currentAttrName.isEmpty,
		   let existingValue = self.currentAttrs.updateValue(self.currentAttrValue, forKey: self.currentAttrName)
		{
			self.currentAttrs[self.currentAttrName] = existingValue
		}
		self.currentAttrName = ""
		self.currentAttrValue = ""
	}

	private func emitError(_ code: String) {
		if self.collectErrors {
			self.errors.append(ParseError(code: code, line: self.line, column: self.column))
		}
	}

	// MARK: - Tokenizer States

	private func dataState() {
		// Batch scan: find next special character and emit all text at once
		let startPos = self.pos

		if !self.trackLocations {
			while self.pos < self.inputLength {
				let byte = self.inputBytes[self.pos]

				if byte == 0x3C { // '<'
					if self.pos > startPos {
						self.emitTextBytes(from: startPos, to: self.pos)
					}
					self.pos += 1
					self.state = .tagOpen
					return
				}

				if byte == 0x26 { // '&'
					if self.pos > startPos {
						self.emitTextBytes(from: startPos, to: self.pos)
					}
					self.pos += 1
					self.returnState = .data
					self.state = .characterReference
					return
				}

				if byte == 0x00 { // null
					if self.pos > startPos {
						self.emitTextBytes(from: startPos, to: self.pos)
					}
					self.pos += 1
					self.emitError("unexpected-null-character")
					self.emitChar("\0")
					return
				}

				self.pos += 1
			}

			// EOF
			if self.pos > startPos {
				self.emitTextBytes(from: startPos, to: self.pos)
			}
			self.emitEOF()
			return
		}

		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			if byte == 0x3C { // '<'
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.state = .tagOpen
				return
			}

			if byte == 0x26 { // '&'
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.returnState = .data
				self.state = .characterReference
				return
			}

			if byte == 0x00 { // null
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.emitError("unexpected-null-character")
				self.emitChar("\0")
				return
			}

			self.advanceLocation(for: byte)
			self.pos += 1
		}

		// EOF
		if self.pos > startPos {
			self.emitTextBytes(from: startPos, to: self.pos)
		}
		self.emitEOF()
	}

	/// Emit a run of bytes as text (just copy bytes, convert when flushing)
	@inline(__always)
	private func emitTextBytes(from start: Int, to end: Int) {
		// Just append the bytes - conversion happens in flushCharBuffer
		self.charBuffer.append(contentsOf: self.inputBytes[start ..< end])
	}

	private func rcdataState() {
		// Batch scan for RCDATA (entities processed, so stop at &)
		let startPos = self.pos
		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			if byte == 0x3C { // '<'
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.state = .rcdataLessThan
				return
			}

			if byte == 0x26 { // '&'
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.returnState = .rcdata
				self.state = .characterReference
				return
			}

			if byte == 0x00 { // null
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.emitError("unexpected-null-character")
				self.emitChar("\u{FFFD}")
				return
			}

			self.advanceLocation(for: byte)
			self.pos += 1
		}

		if self.pos > startPos {
			self.emitTextBytes(from: startPos, to: self.pos)
		}
		self.emitEOF()
	}

	private func rawtextState() {
		// Batch scan for RAWTEXT (no entity processing, only stop at <)
		let startPos = self.pos
		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			if byte == 0x3C { // '<'
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.state = .rawtextLessThan
				return
			}

			if byte == 0x00 { // null
				if self.pos > startPos {
					self.emitTextBytes(from: startPos, to: self.pos)
				}
				self.pos += 1
				self.advanceColumn()
				self.emitError("unexpected-null-character")
				self.emitChar("\u{FFFD}")
				return
			}

			self.advanceLocation(for: byte)
			self.pos += 1
		}

		if self.pos > startPos {
			self.emitTextBytes(from: startPos, to: self.pos)
		}
		self.emitEOF()
	}

	private func plaintextState() {
		guard let ch = consume() else {
			self.emitEOF()
			return
		}

		if ch == "\0" {
			self.emitError("unexpected-null-character")
			self.emitChar("\u{FFFD}")
		}
		else {
			self.emitChar(ch)
		}
	}

	private func tagOpenState() {
		guard self.pos < self.inputLength else {
			self.emitError("eof-before-tag-name")
			self.emitChar("<")
			self.state = .data
			return
		}

		let byte = self.inputBytes[self.pos]
		switch byte {
			case 0x21: // !
				self.pos += 1
				self.advanceColumn()
				self.state = .markupDeclarationOpen

			case 0x2F: // /
				self.pos += 1
				self.advanceColumn()
				self.state = .endTagOpen

			case 0x3F: // ?
				self.emitError("unexpected-question-mark-instead-of-tag-name")
				self.currentComment = ""
				self.state = .bogusComment

			default:
				if (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) {
					self.resetTag()
					self.currentTagIsEnd = false
					self.state = .tagName
				}
				else {
					self.emitError("invalid-first-character-of-tag-name")
					self.emitChar("<")
					self.state = .data
				}
		}
	}

	private func endTagOpenState() {
		guard self.pos < self.inputLength else {
			self.emitError("eof-before-tag-name")
			self.emitString("</")
			self.state = .data
			return
		}

		let byte = self.inputBytes[self.pos]
		if (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A) {
			self.resetTag()
			self.currentTagIsEnd = true
			self.state = .tagName
		}
		else if byte == 0x3E {
			self.pos += 1
			self.advanceColumn()
			self.emitError("missing-end-tag-name")
			self.state = .data
		}
		else {
			self.emitError("invalid-first-character-of-tag-name")
			self.currentComment = ""
			self.state = .bogusComment
		}
	}

	private func tagNameState() {
		// Batch scan: collect tag name bytes until delimiter
		// Use reusable buffer to avoid allocation per tag
		self.nameBuffer.removeAll(keepingCapacity: true)

		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			// Check for delimiters
			switch byte {
				case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
					self.pos += 1
					self.advanceLocation(for: byte)
					if !self.nameBuffer.isEmpty {
						self.currentTagName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.state = .beforeAttributeName
					return

				case 0x2F: // /
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentTagName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.state = .selfClosingStartTag
					return

				case 0x3E: // >
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentTagName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.state = .data
					self.emitCurrentTag()
					return

				case 0x00: // null
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentTagName.append(String(decoding: self.nameBuffer, as: UTF8.self))
						self.nameBuffer.removeAll(keepingCapacity: true)
					}
					self.emitError("unexpected-null-character")
					self.currentTagName.append("\u{FFFD}")
      // Continue scanning

				default:
					// Lowercase ASCII A-Z (0x41-0x5A) -> a-z (0x61-0x7A)
					if byte >= 0x41, byte <= 0x5A {
						self.nameBuffer.append(byte + 32)
					}
					else {
						self.nameBuffer.append(byte)
					}

					// Track position
					self.advanceLocation(for: byte)
					self.pos += 1

					// Handle multi-byte UTF-8 sequences
					if byte >= 0x80 {
						// Skip continuation bytes (10xxxxxx pattern)
						while self.pos < self.inputLength, (self.inputBytes[self.pos] & 0xC0) == 0x80 {
							self.nameBuffer.append(self.inputBytes[self.pos])
							self.pos += 1
						}
					}
			}
		}

		// EOF
		if !self.nameBuffer.isEmpty {
			self.currentTagName.append(String(decoding: self.nameBuffer, as: UTF8.self))
		}
		self.emitError("eof-in-tag")
		self.state = .data
	}

	private func rcdataLessThanState() {
		guard let ch = consume() else {
			self.emitChar("<")
			self.state = .rcdata
			return
		}

		if ch == "/" {
			self.tempBuffer = ""
			self.state = .rcdataEndTagOpen
		}
		else {
			self.emitChar("<")
			self.state = .rcdata
			self.reconsume()
		}
	}

	private func rcdataEndTagOpenState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.state = .rcdata
			return
		}

		if ch.isASCIILetter {
			self.resetTag()
			self.currentTagIsEnd = true
			self.state = .rcdataEndTagName
			self.reconsume()
		}
		else {
			self.emitString("</")
			self.state = .rcdata
			self.reconsume()
		}
	}

	private func rcdataEndTagNameState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.emitString(self.tempBuffer)
			self.state = .rcdata
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .beforeAttributeName
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rcdata
					self.reconsume()
				}

			case "/":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .selfClosingStartTag
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rcdata
					self.reconsume()
				}

			case ">":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.currentTagName = self.tempBuffer.asciiLowercased()
					self.state = .data
					self.emitCurrentTag()
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rcdata
					self.reconsume()
				}

			default:
				if ch.isASCIILetter {
					self.currentTagName.append(ch.asLowercaseCharacter)
					self.tempBuffer.append(ch)
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rcdata
					self.reconsume()
				}
		}
	}

	private func rawtextLessThanState() {
		guard let ch = consume() else {
			self.emitChar("<")
			self.state = .rawtext
			return
		}

		if ch == "/" {
			self.tempBuffer = ""
			self.state = .rawtextEndTagOpen
		}
		else {
			self.emitChar("<")
			self.state = .rawtext
			self.reconsume()
		}
	}

	private func rawtextEndTagOpenState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.state = .rawtext
			return
		}

		if ch.isASCIILetter {
			self.resetTag()
			self.currentTagIsEnd = true
			self.state = .rawtextEndTagName
			self.reconsume()
		}
		else {
			self.emitString("</")
			self.state = .rawtext
			self.reconsume()
		}
	}

	private func rawtextEndTagNameState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.emitString(self.tempBuffer)
			self.state = .rawtext
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .beforeAttributeName
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rawtext
					self.reconsume()
				}

			case "/":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .selfClosingStartTag
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rawtext
					self.reconsume()
				}

			case ">":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.currentTagName = self.tempBuffer.asciiLowercased()
					self.state = .data
					self.emitCurrentTag()
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rawtext
					self.reconsume()
				}

			default:
				if ch.isASCIILetter {
					self.currentTagName.append(ch.asLowercaseCharacter)
					self.tempBuffer.append(ch)
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .rawtext
					self.reconsume()
				}
		}
	}

	// MARK: - Script Data States

	private func scriptDataState() {
		guard let ch = consume() else {
			self.emitEOF()
			return
		}

		switch ch {
			case "<":
				self.state = .scriptDataLessThan

			case "\0":
				self.emitError("unexpected-null-character")
				self.emitChar("\u{FFFD}")

			default:
				self.emitChar(ch)
		}
	}

	private func scriptDataLessThanState() {
		guard let ch = consume() else {
			self.emitChar("<")
			self.state = .scriptData
			return
		}

		switch ch {
			case "/":
				self.tempBuffer = ""
				self.state = .scriptDataEndTagOpen

			case "!":
				self.state = .scriptDataEscapeStart
				self.emitString("<!")

			default:
				self.emitChar("<")
				self.state = .scriptData
				self.reconsume()
		}
	}

	private func scriptDataEndTagOpenState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.state = .scriptData
			return
		}

		if ch.isASCIILetter {
			self.resetTag()
			self.currentTagIsEnd = true
			self.state = .scriptDataEndTagName
			self.reconsume()
		}
		else {
			self.emitString("</")
			self.state = .scriptData
			self.reconsume()
		}
	}

	private func scriptDataEndTagNameState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.emitString(self.tempBuffer)
			self.state = .scriptData
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .beforeAttributeName
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptData
					self.reconsume()
				}

			case "/":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .selfClosingStartTag
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptData
					self.reconsume()
				}

			case ">":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.currentTagName = self.tempBuffer.asciiLowercased()
					self.state = .data
					self.emitCurrentTag()
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptData
					self.reconsume()
				}

			default:
				if ch.isASCIILetter {
					self.currentTagName.append(ch.asLowercaseCharacter)
					self.tempBuffer.append(ch)
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptData
					self.reconsume()
				}
		}
	}

	private func scriptDataEscapeStartState() {
		guard let ch = consume() else {
			self.state = .scriptData
			return
		}

		if ch == "-" {
			self.state = .scriptDataEscapeStartDash
			self.emitChar("-")
		}
		else {
			self.state = .scriptData
			self.reconsume()
		}
	}

	private func scriptDataEscapeStartDashState() {
		guard let ch = consume() else {
			self.state = .scriptData
			return
		}

		if ch == "-" {
			self.state = .scriptDataEscapedDashDash
			self.emitChar("-")
		}
		else {
			self.state = .scriptData
			self.reconsume()
		}
	}

	private func scriptDataEscapedState() {
		guard let ch = consume() else {
			self.emitError("eof-in-script-html-comment-like-text")
			self.emitEOF()
			return
		}

		switch ch {
			case "-":
				self.state = .scriptDataEscapedDash
				self.emitChar("-")

			case "<":
				self.state = .scriptDataEscapedLessThan

			case "\0":
				self.emitError("unexpected-null-character")
				self.emitChar("\u{FFFD}")

			default:
				self.emitChar(ch)
		}
	}

	private func scriptDataEscapedDashState() {
		guard let ch = consume() else {
			self.emitError("eof-in-script-html-comment-like-text")
			self.emitEOF()
			return
		}

		switch ch {
			case "-":
				self.state = .scriptDataEscapedDashDash
				self.emitChar("-")

			case "<":
				self.state = .scriptDataEscapedLessThan

			case "\0":
				self.emitError("unexpected-null-character")
				self.state = .scriptDataEscaped
				self.emitChar("\u{FFFD}")

			default:
				self.state = .scriptDataEscaped
				self.emitChar(ch)
		}
	}

	private func scriptDataEscapedDashDashState() {
		guard let ch = consume() else {
			self.emitError("eof-in-script-html-comment-like-text")
			self.emitEOF()
			return
		}

		switch ch {
			case "-":
				self.emitChar("-")

			case "<":
				self.state = .scriptDataEscapedLessThan

			case ">":
				self.state = .scriptData
				self.emitChar(">")

			case "\0":
				self.emitError("unexpected-null-character")
				self.state = .scriptDataEscaped
				self.emitChar("\u{FFFD}")

			default:
				self.state = .scriptDataEscaped
				self.emitChar(ch)
		}
	}

	private func scriptDataEscapedLessThanState() {
		guard let ch = consume() else {
			self.emitChar("<")
			self.state = .scriptDataEscaped
			return
		}

		switch ch {
			case "/":
				self.tempBuffer = ""
				self.state = .scriptDataEscapedEndTagOpen

			default:
				if ch.isASCIILetter {
					self.tempBuffer = ""
					self.emitChar("<")
					self.state = .scriptDataDoubleEscapeStart
					self.reconsume()
				}
				else {
					self.emitChar("<")
					self.state = .scriptDataEscaped
					self.reconsume()
				}
		}
	}

	private func scriptDataEscapedEndTagOpenState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.state = .scriptDataEscaped
			return
		}

		if ch.isASCIILetter {
			self.resetTag()
			self.currentTagIsEnd = true
			self.state = .scriptDataEscapedEndTagName
			self.reconsume()
		}
		else {
			self.emitString("</")
			self.state = .scriptDataEscaped
			self.reconsume()
		}
	}

	private func scriptDataEscapedEndTagNameState() {
		guard let ch = consume() else {
			self.emitString("</")
			self.emitString(self.tempBuffer)
			self.state = .scriptDataEscaped
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .beforeAttributeName
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptDataEscaped
					self.reconsume()
				}

			case "/":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.state = .selfClosingStartTag
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptDataEscaped
					self.reconsume()
				}

			case ">":
				if self.tempBuffer.asciiCaseInsensitiveEquals(self.lastStartTagName) {
					self.currentTagName = self.tempBuffer.asciiLowercased()
					self.state = .data
					self.emitCurrentTag()
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptDataEscaped
					self.reconsume()
				}

			default:
				if ch.isASCIILetter {
					self.currentTagName.append(ch.asLowercaseCharacter)
					self.tempBuffer.append(ch)
				}
				else {
					self.emitString("</")
					self.emitString(self.tempBuffer)
					self.state = .scriptDataEscaped
					self.reconsume()
				}
		}
	}

	private func scriptDataDoubleEscapeStartState() {
		guard let ch = consume() else {
			self.state = .scriptDataEscaped
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ", "/", ">":
				if self.tempBuffer.asciiCaseInsensitiveEquals("script") {
					self.state = .scriptDataDoubleEscaped
				}
				else {
					self.state = .scriptDataEscaped
				}
				self.emitChar(ch)

			default:
				if ch.isASCIILetter {
					self.tempBuffer.append(ch)
					self.emitChar(ch)
				}
				else {
					self.state = .scriptDataEscaped
					self.reconsume()
				}
		}
	}

	private func scriptDataDoubleEscapedState() {
		guard let ch = consume() else {
			self.emitError("eof-in-script-html-comment-like-text")
			self.emitEOF()
			return
		}

		switch ch {
			case "-":
				self.state = .scriptDataDoubleEscapedDash
				self.emitChar("-")

			case "<":
				self.state = .scriptDataDoubleEscapedLessThan
				self.emitChar("<")

			case "\0":
				self.emitError("unexpected-null-character")
				self.emitChar("\u{FFFD}")

			default:
				self.emitChar(ch)
		}
	}

	private func scriptDataDoubleEscapedDashState() {
		guard let ch = consume() else {
			self.emitError("eof-in-script-html-comment-like-text")
			self.emitEOF()
			return
		}

		switch ch {
			case "-":
				self.state = .scriptDataDoubleEscapedDashDash
				self.emitChar("-")

			case "<":
				self.state = .scriptDataDoubleEscapedLessThan
				self.emitChar("<")

			case "\0":
				self.emitError("unexpected-null-character")
				self.state = .scriptDataDoubleEscaped
				self.emitChar("\u{FFFD}")

			default:
				self.state = .scriptDataDoubleEscaped
				self.emitChar(ch)
		}
	}

	private func scriptDataDoubleEscapedDashDashState() {
		guard let ch = consume() else {
			self.emitError("eof-in-script-html-comment-like-text")
			self.emitEOF()
			return
		}

		switch ch {
			case "-":
				self.emitChar("-")

			case "<":
				self.state = .scriptDataDoubleEscapedLessThan
				self.emitChar("<")

			case ">":
				self.state = .scriptData
				self.emitChar(">")

			case "\0":
				self.emitError("unexpected-null-character")
				self.state = .scriptDataDoubleEscaped
				self.emitChar("\u{FFFD}")

			default:
				self.state = .scriptDataDoubleEscaped
				self.emitChar(ch)
		}
	}

	private func scriptDataDoubleEscapedLessThanState() {
		guard let ch = consume() else {
			self.state = .scriptDataDoubleEscaped
			return
		}

		if ch == "/" {
			self.tempBuffer = ""
			self.state = .scriptDataDoubleEscapeEnd
			self.emitChar("/")
		}
		else {
			self.state = .scriptDataDoubleEscaped
			self.reconsume()
		}
	}

	private func scriptDataDoubleEscapeEndState() {
		guard let ch = consume() else {
			self.state = .scriptDataDoubleEscaped
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ", "/", ">":
				if self.tempBuffer.asciiCaseInsensitiveEquals("script") {
					self.state = .scriptDataEscaped
				}
				else {
					self.state = .scriptDataDoubleEscaped
				}
				self.emitChar(ch)

			default:
				if ch.isASCIILetter {
					self.tempBuffer.append(ch)
					self.emitChar(ch)
				}
				else {
					self.state = .scriptDataDoubleEscaped
					self.reconsume()
				}
		}
	}

	private func beforeAttributeNameState() {
		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
					self.pos += 1
					self.advanceLocation(for: byte)

				case 0x2F: // /
					self.pos += 1
					self.advanceColumn()
					self.state = .selfClosingStartTag
					return

				case 0x3E: // >
					self.pos += 1
					self.advanceColumn()
					self.state = .data
					self.emitCurrentTag()
					return

				case 0x3D: // =
					self.pos += 1
					self.advanceColumn()
					self.emitError("unexpected-equals-sign-before-attribute-name")
					self.currentAttrName = "="
					self.state = .attributeName
					return

				default:
					self.storeCurrentAttr()
					self.state = .attributeName
					return
			}
		}

		if self.pos >= self.inputLength {
			self.emitError("eof-in-tag")
			self.state = .data
		}
	}

	private func attributeNameState() {
		// Batch scan: collect attribute name bytes until delimiter
		// Use reusable buffer to avoid allocation per attribute
		self.nameBuffer.removeAll(keepingCapacity: true)

		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
					self.pos += 1
					self.advanceLocation(for: byte)
					if !self.nameBuffer.isEmpty {
						self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.state = .afterAttributeName
					return

				case 0x2F: // /
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.storeCurrentAttr()
					self.state = .selfClosingStartTag
					return

				case 0x3E: // >
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.storeCurrentAttr()
					self.state = .data
					self.emitCurrentTag()
					return

				case 0x3D: // =
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
					}
					self.state = .beforeAttributeValue
					return

				case 0x00: // null
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
						self.nameBuffer.removeAll(keepingCapacity: true)
					}
					self.emitError("unexpected-null-character")
					self.currentAttrName.append("\u{FFFD}")

				case 0x22, 0x27, 0x3C: // " ' <
					self.pos += 1
					self.advanceColumn()
					if !self.nameBuffer.isEmpty {
						self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
						self.nameBuffer.removeAll(keepingCapacity: true)
					}
					self.emitError("unexpected-character-in-attribute-name")
					self.currentAttrName.append(Character(UnicodeScalar(byte)))

				default:
					// Lowercase ASCII A-Z
					if byte >= 0x41, byte <= 0x5A {
						self.nameBuffer.append(byte + 32)
					}
					else {
						self.nameBuffer.append(byte)
					}
					self.advanceColumn()
					self.pos += 1

					// Handle multi-byte UTF-8
					if byte >= 0x80 {
						while self.pos < self.inputLength, (self.inputBytes[self.pos] & 0xC0) == 0x80 {
							self.nameBuffer.append(self.inputBytes[self.pos])
							self.pos += 1
						}
					}
			}
		}

		// EOF
		if !self.nameBuffer.isEmpty {
			self.currentAttrName.append(String(decoding: self.nameBuffer, as: UTF8.self))
		}
		self.emitError("eof-in-tag")
		self.state = .data
	}

	private func afterAttributeNameState() {
		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
					self.pos += 1
					self.advanceLocation(for: byte)

				case 0x2F: // /
					self.pos += 1
					self.advanceColumn()
					self.storeCurrentAttr()
					self.state = .selfClosingStartTag
					return

				case 0x3D: // =
					self.pos += 1
					self.advanceColumn()
					self.state = .beforeAttributeValue
					return

				case 0x3E: // >
					self.pos += 1
					self.advanceColumn()
					self.storeCurrentAttr()
					self.state = .data
					self.emitCurrentTag()
					return

				default:
					self.storeCurrentAttr()
					self.state = .attributeName
					return
			}
		}

		if self.pos >= self.inputLength {
			self.emitError("eof-in-tag")
			self.state = .data
		}
	}

	private func beforeAttributeValueState() {
		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
					self.pos += 1
					self.advanceLocation(for: byte)

				case 0x22: // "
					self.pos += 1
					self.advanceColumn()
					self.state = .attributeValueDoubleQuoted
					return

				case 0x27: // '
					self.pos += 1
					self.advanceColumn()
					self.state = .attributeValueSingleQuoted
					return

				case 0x3E: // >
					self.pos += 1
					self.advanceColumn()
					self.emitError("missing-attribute-value")
					self.storeCurrentAttr()
					self.state = .data
					self.emitCurrentTag()
					return

				default:
					self.state = .attributeValueUnquoted
					return
			}
		}

		if self.pos >= self.inputLength {
			self.emitError("eof-in-tag")
			self.state = .data
		}
	}

	private func attributeValueDoubleQuotedState() {
		// Batch scan until " or & or null or EOF
		let startPos = self.pos

		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x22: // "
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.storeCurrentAttr()
					self.state = .afterAttributeValueQuoted
					return

				case 0x26: // &
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.returnState = .attributeValueDoubleQuoted
					self.state = .characterReference
					return

				case 0x00: // null
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.emitError("unexpected-null-character")
					self.currentAttrValue.append("\u{FFFD}")
					// Restart scanning from current position
					self.attributeValueDoubleQuotedState()
					return

				default:
					self.advanceLocation(for: byte)
					self.pos += 1
			}
		}

		// EOF
		if self.pos > startPos {
			self.currentAttrValue.append(
				String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
		}
		self.emitError("eof-in-tag")
		self.state = .data
	}

	private func attributeValueSingleQuotedState() {
		// Batch scan until ' or & or null or EOF
		let startPos = self.pos

		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x27: // '
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.storeCurrentAttr()
					self.state = .afterAttributeValueQuoted
					return

				case 0x26: // &
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.returnState = .attributeValueSingleQuoted
					self.state = .characterReference
					return

				case 0x00: // null
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.emitError("unexpected-null-character")
					self.currentAttrValue.append("\u{FFFD}")
					// Restart scanning from current position
					self.attributeValueSingleQuotedState()
					return

				default:
					self.advanceLocation(for: byte)
					self.pos += 1
			}
		}

		// EOF
		if self.pos > startPos {
			self.currentAttrValue.append(
				String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
		}
		self.emitError("eof-in-tag")
		self.state = .data
	}

	private func attributeValueUnquotedState() {
		// Batch scan until delimiter
		let startPos = self.pos

		while self.pos < self.inputLength {
			let byte = self.inputBytes[self.pos]

			switch byte {
				case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceLocation(for: byte)
					self.storeCurrentAttr()
					self.state = .beforeAttributeName
					return

				case 0x26: // &
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.returnState = .attributeValueUnquoted
					self.state = .characterReference
					return

				case 0x3E: // >
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.storeCurrentAttr()
					self.state = .data
					self.emitCurrentTag()
					return

				case 0x00: // null
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.emitError("unexpected-null-character")
					self.currentAttrValue.append("\u{FFFD}")
					// Restart scanning from current position
					self.attributeValueUnquotedState()
					return

				case 0x22, 0x27, 0x3C, 0x3D, 0x60: // " ' < = `
					if self.pos > startPos {
						self.currentAttrValue.append(
							String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
					}
					self.pos += 1
					self.advanceColumn()
					self.emitError("unexpected-character-in-unquoted-attribute-value")
					self.currentAttrValue.append(Character(UnicodeScalar(byte)))
					// Restart scanning from current position
					self.attributeValueUnquotedState()
					return

				default:
					self.advanceLocation(for: byte)
					self.pos += 1
			}
		}

		// EOF
		if self.pos > startPos {
			self.currentAttrValue.append(
				String(decoding: self.inputBytes[startPos ..< self.pos], as: UTF8.self))
		}
		self.emitError("eof-in-tag")
		self.state = .data
	}

	private func afterAttributeValueQuotedState() {
		guard self.pos < self.inputLength else {
			self.emitError("eof-in-tag")
			self.state = .data
			return
		}

		let byte = self.inputBytes[self.pos]
		switch byte {
			case 0x09, 0x0A, 0x0C, 0x20: // \t \n \f space
				self.pos += 1
				self.advanceLocation(for: byte)
				self.state = .beforeAttributeName

			case 0x2F: // /
				self.pos += 1
				self.advanceColumn()
				self.state = .selfClosingStartTag

			case 0x3E: // >
				self.pos += 1
				self.advanceColumn()
				self.state = .data
				self.emitCurrentTag()

			default:
				_ = self.consume()
				self.emitError("missing-whitespace-between-attributes")
				self.state = .beforeAttributeName
				self.reconsume()
		}
	}

	private func selfClosingStartTagState() {
		guard self.pos < self.inputLength else {
			self.emitError("eof-in-tag")
			self.state = .data
			return
		}

		if self.inputBytes[self.pos] == 0x3E {
			self.pos += 1
			self.advanceColumn()
			self.currentTagSelfClosing = true
			self.state = .data
			self.emitCurrentTag()
		}
		else {
			_ = self.consume()
			self.emitError("unexpected-solidus-in-tag")
			self.state = .beforeAttributeName
			self.reconsume()
		}
	}

	private func bogusCommentState() {
		guard let ch = consume() else {
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case ">":
				self.emitCurrentComment()
				self.state = .data

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentComment.append("\u{FFFD}")

			default:
				self.currentComment.append(ch)
		}
	}

	private func markupDeclarationOpenState() {
		if self.consumeIf("--") {
			self.currentComment = ""
			self.state = .commentStart
		}
		else if self.consumeIf("DOCTYPE", caseInsensitive: true) {
			self.state = .doctype
		}
		else if self.consumeIf("[CDATA[", caseInsensitive: false) {
			// CDATA is only valid in foreign content (SVG/MathML)
			let ns = self.sink.currentNamespace
			if ns == .svg || ns == .math {
				// In foreign content - process as CDATA section
				self.state = .cdataSection
			}
			else {
				// In HTML - treat as bogus comment
				self.emitError("cdata-in-html-content")
				self.currentComment = "[CDATA["
				self.state = .bogusComment
			}
		}
		else {
			self.emitError("incorrectly-opened-comment")
			self.currentComment = ""
			self.state = .bogusComment
		}
	}

	private func commentStartState() {
		guard let ch = consume() else {
			self.emitError("eof-in-comment")
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case "-":
				self.state = .commentStartDash

			case ">":
				self.emitError("abrupt-closing-of-empty-comment")
				self.emitCurrentComment()
				self.state = .data

			default:
				self.state = .comment
				self.reconsume()
		}
	}

	private func commentStartDashState() {
		guard let ch = consume() else {
			self.emitError("eof-in-comment")
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case "-":
				self.state = .commentEnd

			case ">":
				self.emitError("abrupt-closing-of-empty-comment")
				self.emitCurrentComment()
				self.state = .data

			default:
				self.currentComment.append("-")
				self.state = .comment
				self.reconsume()
		}
	}

	private func commentState() {
		guard let ch = consume() else {
			self.emitError("eof-in-comment")
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case "<":
				self.currentComment.append(ch)

			// Could go to commentLessThanSign state, but simplified here
			case "-":
				self.state = .commentEndDash

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentComment.append("\u{FFFD}")

			default:
				self.currentComment.append(ch)
		}
	}

	private func commentEndDashState() {
		guard let ch = consume() else {
			self.emitError("eof-in-comment")
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case "-":
				self.state = .commentEnd

			default:
				self.currentComment.append("-")
				self.state = .comment
				self.reconsume()
		}
	}

	private func commentEndState() {
		guard let ch = consume() else {
			self.emitError("eof-in-comment")
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case ">":
				self.emitCurrentComment()
				self.state = .data

			case "!":
				self.state = .commentEndBang

			case "-":
				self.currentComment.append("-")

			default:
				self.currentComment.append("--")
				self.state = .comment
				self.reconsume()
		}
	}

	private func commentEndBangState() {
		guard let ch = consume() else {
			self.emitError("eof-in-comment")
			self.emitCurrentComment()
			self.state = .data
			return
		}

		switch ch {
			case "-":
				self.currentComment.append("--!")
				self.state = .commentEndDash

			case ">":
				self.emitError("incorrectly-closed-comment")
				self.emitCurrentComment()
				self.state = .data

			default:
				self.currentComment.append("--!")
				self.state = .comment
				self.reconsume()
		}
	}

	private func doctypeState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				self.state = .beforeDoctypeName

			case ">":
				self.state = .beforeDoctypeName
				self.reconsume()

			default:
				self.emitError("missing-whitespace-before-doctype-name")
				self.state = .beforeDoctypeName
				self.reconsume()
		}
	}

	private func beforeDoctypeNameState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				// Ignore
				break

			case ">":
				self.emitError("missing-doctype-name")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentDoctypeName.append("\u{FFFD}")
				self.state = .doctypeName

			default:
				self.currentDoctypeName.append(ch.asLowercaseCharacter)
				self.state = .doctypeName
		}
	}

	private func doctypeNameState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				self.state = .afterDoctypeName

			case ">":
				self.emitCurrentDoctype()
				self.state = .data

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentDoctypeName.append("\u{FFFD}")

			default:
				self.currentDoctypeName.append(ch.asLowercaseCharacter)
		}
	}

	private func afterDoctypeNameState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				// Ignore
				break

			case ">":
				self.emitCurrentDoctype()
				self.state = .data

			default:
				// Check for PUBLIC or SYSTEM
				self.reconsume()
				if self.consumeIf("PUBLIC", caseInsensitive: true) {
					self.state = .afterDoctypePublicKeyword
				}
				else if self.consumeIf("SYSTEM", caseInsensitive: true) {
					self.state = .afterDoctypeSystemKeyword
				}
				else {
					self.emitError("invalid-character-sequence-after-doctype-name")
					self.currentDoctypeForceQuirks = true
					self.state = .bogusDoctype
				}
		}
	}

	private func afterDoctypePublicKeywordState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				self.state = .beforeDoctypePublicIdentifier

			case "\"":
				self.emitError("missing-whitespace-after-doctype-public-keyword")
				self.currentDoctypePublicId = ""
				self.state = .doctypePublicIdentifierDoubleQuoted

			case "'":
				self.emitError("missing-whitespace-after-doctype-public-keyword")
				self.currentDoctypePublicId = ""
				self.state = .doctypePublicIdentifierSingleQuoted

			case ">":
				self.emitError("missing-doctype-public-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.emitError("missing-quote-before-doctype-public-identifier")
				self.currentDoctypeForceQuirks = true
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func beforeDoctypePublicIdentifierState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				// Ignore
				break

			case "\"":
				self.currentDoctypePublicId = ""
				self.state = .doctypePublicIdentifierDoubleQuoted

			case "'":
				self.currentDoctypePublicId = ""
				self.state = .doctypePublicIdentifierSingleQuoted

			case ">":
				self.emitError("missing-doctype-public-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.emitError("missing-quote-before-doctype-public-identifier")
				self.currentDoctypeForceQuirks = true
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func doctypePublicIdentifierDoubleQuotedState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\"":
				self.state = .afterDoctypePublicIdentifier

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentDoctypePublicId?.append("\u{FFFD}")

			case ">":
				self.emitError("abrupt-doctype-public-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.currentDoctypePublicId?.append(ch)
		}
	}

	private func doctypePublicIdentifierSingleQuotedState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "'":
				self.state = .afterDoctypePublicIdentifier

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentDoctypePublicId?.append("\u{FFFD}")

			case ">":
				self.emitError("abrupt-doctype-public-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.currentDoctypePublicId?.append(ch)
		}
	}

	private func afterDoctypePublicIdentifierState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				self.state = .betweenDoctypePublicAndSystemIdentifiers

			case ">":
				self.emitCurrentDoctype()
				self.state = .data

			case "\"":
				self.emitError("missing-whitespace-between-doctype-public-and-system-identifiers")
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierDoubleQuoted

			case "'":
				self.emitError("missing-whitespace-between-doctype-public-and-system-identifiers")
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierSingleQuoted

			default:
				self.emitError("missing-quote-before-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func betweenDoctypePublicAndSystemIdentifiersState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				// Ignore
				break

			case ">":
				self.emitCurrentDoctype()
				self.state = .data

			case "\"":
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierDoubleQuoted

			case "'":
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierSingleQuoted

			default:
				self.emitError("missing-quote-before-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func afterDoctypeSystemKeywordState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				self.state = .beforeDoctypeSystemIdentifier

			case "\"":
				self.emitError("missing-whitespace-after-doctype-system-keyword")
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierDoubleQuoted

			case "'":
				self.emitError("missing-whitespace-after-doctype-system-keyword")
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierSingleQuoted

			case ">":
				self.emitError("missing-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.emitError("missing-quote-before-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func beforeDoctypeSystemIdentifierState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				// Ignore
				break

			case "\"":
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierDoubleQuoted

			case "'":
				self.currentDoctypeSystemId = ""
				self.state = .doctypeSystemIdentifierSingleQuoted

			case ">":
				self.emitError("missing-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.emitError("missing-quote-before-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func doctypeSystemIdentifierDoubleQuotedState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\"":
				self.state = .afterDoctypeSystemIdentifier

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentDoctypeSystemId?.append("\u{FFFD}")

			case ">":
				self.emitError("abrupt-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.currentDoctypeSystemId?.append(ch)
		}
	}

	private func doctypeSystemIdentifierSingleQuotedState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "'":
				self.state = .afterDoctypeSystemIdentifier

			case "\0":
				self.emitError("unexpected-null-character")
				self.currentDoctypeSystemId?.append("\u{FFFD}")

			case ">":
				self.emitError("abrupt-doctype-system-identifier")
				self.currentDoctypeForceQuirks = true
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.currentDoctypeSystemId?.append(ch)
		}
	}

	private func afterDoctypeSystemIdentifierState() {
		guard let ch = consume() else {
			self.emitError("eof-in-doctype")
			self.currentDoctypeForceQuirks = true
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case "\t", "\n", "\u{0C}", " ":
				// Ignore
				break

			case ">":
				self.emitCurrentDoctype()
				self.state = .data

			default:
				self.emitError("unexpected-character-after-doctype-system-identifier")
				self.state = .bogusDoctype
				self.reconsume()
		}
	}

	private func bogusDoctypeState() {
		guard let ch = consume() else {
			self.emitCurrentDoctype()
			self.state = .data
			return
		}

		switch ch {
			case ">":
				self.emitCurrentDoctype()
				self.state = .data

			case "\0":
				self.emitError("unexpected-null-character")

			default:
				break
		}
	}

	// MARK: - Character Reference States

	private var isInAttribute: Bool {
		return self.returnState == .attributeValueDoubleQuoted
			|| self.returnState == .attributeValueSingleQuoted
			|| self.returnState == .attributeValueUnquoted
	}

	private func flushCharRefTempBuffer() {
		if self.isInAttribute {
			self.currentAttrValue.append(self.charRefTempBuffer)
		}
		else {
			self.emitString(self.charRefTempBuffer)
		}
		self.charRefTempBuffer = ""
	}

	private func emitCharRefString(_ s: String) {
		if self.isInAttribute {
			self.currentAttrValue.append(s)
		}
		else {
			self.emitString(s)
		}
	}

	private func characterReferenceState() {
		self.charRefTempBuffer = "&"

		guard let ch = consume() else {
			self.flushCharRefTempBuffer()
			self.state = self.returnState
			return
		}

		if ch.isASCIILetter || ch.isASCIIDigit {
			self.state = .namedCharacterReference
			self.reconsume()
		}
		else if ch == "#" {
			self.charRefTempBuffer.append(ch)
			self.state = .numericCharacterReference
		}
		else {
			self.flushCharRefTempBuffer()
			self.state = self.returnState
			self.reconsume()
		}
	}

	private func namedCharacterReferenceState() {
		if self.emitCommonNamedCharacterReference() {
			self.state = self.returnState
			return
		}

		// Collect alphanumeric characters
		var entityName = ""
		var matchedEntity: String? = nil
		var matchedLength = 0
		var consumed = 0
		let maxLength = self.opts.maxEntityNameLength
		var hitLimit = false

		while let ch = peek() {
			if ch.isASCIILetter || ch.isASCIIDigit {
				// Check entity name length limit (DoS protection)
				// The longest valid HTML entity is ~31 chars, so hitting this limit
				// means the entity is definitely invalid - stop looking for matches
				// but continue consuming to emit the full text
				if consumed >= maxLength {
					hitLimit = true
					// Consume remaining alphanumeric characters and emit them as text
					self.flushCharRefTempBuffer()
					self.emitCharRefString(entityName)
					// Emit remaining characters directly
					while let next = peek(), next.isASCIILetter || next.isASCIIDigit {
						self.emitChar(next)
						_ = self.consume()
					}
					self.state = self.returnState
					return
				}

				entityName.append(ch)
				_ = self.consume()
				consumed += 1

				// Check for match (only if we haven't exceeded the limit)
				if !hitLimit, let decoded = NAMED_ENTITIES[entityName] {
					matchedEntity = decoded
					matchedLength = consumed
				}
			}
			else {
				break
			}
		}

		// Check for semicolon immediately after the match
		// (only valid if we consumed exactly the matched length of characters)
		let hasSemicolon = self.peek() == ";"
		if hasSemicolon, matchedEntity != nil, consumed == matchedLength {
			_ = self.consume() // consume the semicolon
			self.emitCharRefString(matchedEntity!)
			self.state = self.returnState
			return
		}

		// Try to use the longest match
		if let match = matchedEntity {
			// In attributes, legacy entities without semicolon followed by alphanumeric or = are not decoded
			// We need to check the character AFTER the matched entity, not after all consumed chars
			if self.isInAttribute, !hasSemicolon {
				// The character after the match is at position matchedLength in entityName,
				// or the current peek() if we consumed exactly matchedLength characters
				let charAfterMatch: Character?
				if consumed > matchedLength {
					// The char after match is in entityName
					let idx = entityName.index(entityName.startIndex, offsetBy: matchedLength)
					charAfterMatch = entityName[idx]
				}
				else {
					charAfterMatch = self.peek()
				}
				if let ch = charAfterMatch, ch.isASCIILetter || ch.isASCIIDigit || ch == "=" {
					// Don't decode - emit as is
					self.flushCharRefTempBuffer()
					self.emitCharRefString(entityName)
					self.state = self.returnState
					return
				}
			}

			// If in attribute and there's a semicolon but we didn't consume exactly the matched length,
			// that means the full entity name (with semicolon) is invalid - don't use prefix match
			// e.g., "&noti;" in attribute - "noti" is not valid, so don't match "&not;"
			// In text content, we DO use prefix matching even with semicolon
			if self.isInAttribute, hasSemicolon, consumed != matchedLength {
				// Fall through to emit as text
			}
			else {
				// Check if this is a legacy entity
				let matchedName = String(entityName.prefix(matchedLength))
				if LEGACY_ENTITIES.contains(matchedName) {
					// Unconsume the extra characters
					for _ in 0 ..< (consumed - matchedLength) {
						self.reconsume()
					}
					if !hasSemicolon {
						self.emitError("missing-semicolon-after-character-reference")
					}
					self.emitCharRefString(match)
					self.state = self.returnState
					return
				}

				// The exact match isn't a legacy entity - try to find a legacy prefix
				// This handles cases like "&notin" where "notin" isn't legacy but "not" is
				if !hasSemicolon {
					for k in stride(from: matchedLength - 1, through: 1, by: -1) {
						let prefix = String(entityName.prefix(k))
						if LEGACY_ENTITIES.contains(prefix), let decoded = NAMED_ENTITIES[prefix] {
							// Unconsume back to just after the prefix
							for _ in 0 ..< (consumed - k) {
								self.reconsume()
							}
							self.emitError("missing-semicolon-after-character-reference")
							self.emitCharRefString(decoded)
							self.state = self.returnState
							return
						}
					}
				}
			}
		}

		// No match - emit everything as text
		self.flushCharRefTempBuffer()
		// Put back all consumed characters except the first (which is in tempBuffer)
		for _ in 0 ..< consumed {
			self.reconsume()
		}
		self.state = .ambiguousAmpersand
	}

	@inline(__always)
	private func emitCommonNamedCharacterReference() -> Bool {
		let remaining = self.inputLength - self.pos

		if remaining >= 3 {
			let b0 = self.inputBytes[self.pos]
			let b1 = self.inputBytes[self.pos + 1]
			let b2 = self.inputBytes[self.pos + 2]

			if self.hasEntitySemicolon(after: 3), b0 == 0x61, b1 == 0x6D, b2 == 0x70 { // amp
				return self.emitFastEntity("&", byteCount: 4)
			}
			if self.hasEntitySemicolon(after: 3), b0 == 0x41, b1 == 0x4D, b2 == 0x50 { // AMP
				return self.emitFastEntity("&", byteCount: 4)
			}
			if self.hasEntitySemicolon(after: 2), b0 == 0x6C, b1 == 0x74 { // lt
				return self.emitFastEntity("<", byteCount: 3)
			}
			if self.hasEntitySemicolon(after: 2), b0 == 0x67, b1 == 0x74 { // gt
				return self.emitFastEntity(">", byteCount: 3)
			}
			if self.hasEntitySemicolon(after: 2), b0 == 0x4C, b1 == 0x54 { // LT
				return self.emitFastEntity("<", byteCount: 3)
			}
			if self.hasEntitySemicolon(after: 2), b0 == 0x47, b1 == 0x54 { // GT
				return self.emitFastEntity(">", byteCount: 3)
			}
		}

		if remaining >= 4 {
			let b0 = self.inputBytes[self.pos]
			let b1 = self.inputBytes[self.pos + 1]
			let b2 = self.inputBytes[self.pos + 2]
			let b3 = self.inputBytes[self.pos + 3]

			if self.hasEntitySemicolon(after: 4), b0 == 0x71, b1 == 0x75, b2 == 0x6F, b3 == 0x74 { // quot
				return self.emitFastEntity("\"", byteCount: 5)
			}
			if self.hasEntitySemicolon(after: 4), b0 == 0x51, b1 == 0x55, b2 == 0x4F, b3 == 0x54 { // QUOT
				return self.emitFastEntity("\"", byteCount: 5)
			}
			if self.hasEntitySemicolon(after: 4), b0 == 0x6E, b1 == 0x62, b2 == 0x73, b3 == 0x70 { // nbsp
				return self.emitFastEntity("\u{00A0}", byteCount: 5)
			}
		}

		return false
	}

	@inline(__always)
	private func hasEntitySemicolon(after byteCount: Int) -> Bool {
		let semicolonIndex = self.pos + byteCount
		return semicolonIndex < self.inputLength && self.inputBytes[semicolonIndex] == 0x3B
	}

	@inline(__always)
	private func emitFastEntity(_ entity: String, byteCount: Int) -> Bool {
		self.pos += byteCount
		self.advanceColumns(byteCount)
		self.emitCharRefString(entity)
		return true
	}

	private func ambiguousAmpersandState() {
		guard let ch = consume() else {
			self.state = self.returnState
			return
		}

		if ch.isASCIILetter || ch.isASCIIDigit {
			if self.isInAttribute {
				self.currentAttrValue.append(ch)
			}
			else {
				self.emitChar(ch)
			}
		}
		else if ch == ";" {
			self.emitError("unknown-named-character-reference")
			self.state = self.returnState
			self.reconsume()
		}
		else {
			self.state = self.returnState
			self.reconsume()
		}
	}

	private func numericCharacterReferenceState() {
		self.charRefCode = 0

		guard let ch = consume() else {
			self.state = .decimalCharacterReferenceStart
			return
		}

		if ch == "x" || ch == "X" {
			self.charRefTempBuffer.append(ch)
			self.state = .hexadecimalCharacterReferenceStart
		}
		else {
			self.state = .decimalCharacterReferenceStart
			self.reconsume()
		}
	}

	private func hexadecimalCharacterReferenceStartState() {
		guard let ch = consume() else {
			self.emitError("absence-of-digits-in-numeric-character-reference")
			self.flushCharRefTempBuffer()
			self.state = self.returnState
			return
		}

		if ch.isHexDigit {
			self.state = .hexadecimalCharacterReference
			self.reconsume()
		}
		else {
			self.emitError("absence-of-digits-in-numeric-character-reference")
			self.flushCharRefTempBuffer()
			self.state = self.returnState
			self.reconsume()
		}
	}

	private func decimalCharacterReferenceStartState() {
		guard let ch = consume() else {
			self.emitError("absence-of-digits-in-numeric-character-reference")
			self.flushCharRefTempBuffer()
			self.state = self.returnState
			return
		}

		if ch.isASCIIDigit {
			self.state = .decimalCharacterReference
			self.reconsume()
		}
		else {
			self.emitError("absence-of-digits-in-numeric-character-reference")
			self.flushCharRefTempBuffer()
			self.state = self.returnState
			self.reconsume()
		}
	}

	private func hexadecimalCharacterReferenceState() {
		guard let ch = consume() else {
			self.state = .numericCharacterReferenceEnd
			return
		}

		if ch.isASCIIDigit {
			// Cap at 0x110000 to detect overflow (any value > 0x10FFFF is invalid)
			// Use 0x110000 as sentinel for "too large"
			if self.charRefCode <= 0x10FFFF {
				let newValue = UInt64(self.charRefCode) * 16 + UInt64(ch.asciiValue! - 0x30)
				self.charRefCode = newValue > 0x10FFFF ? 0x110000 : UInt32(newValue)
			}
		}
		else if ch >= "A", ch <= "F" {
			if self.charRefCode <= 0x10FFFF {
				let newValue = UInt64(self.charRefCode) * 16 + UInt64(ch.asciiValue! - 0x37)
				self.charRefCode = newValue > 0x10FFFF ? 0x110000 : UInt32(newValue)
			}
		}
		else if ch >= "a", ch <= "f" {
			if self.charRefCode <= 0x10FFFF {
				let newValue = UInt64(self.charRefCode) * 16 + UInt64(ch.asciiValue! - 0x57)
				self.charRefCode = newValue > 0x10FFFF ? 0x110000 : UInt32(newValue)
			}
		}
		else if ch == ";" {
			self.state = .numericCharacterReferenceEnd
		}
		else {
			self.emitError("missing-semicolon-after-character-reference")
			self.state = .numericCharacterReferenceEnd
			self.reconsume()
		}
	}

	private func decimalCharacterReferenceState() {
		guard let ch = consume() else {
			self.state = .numericCharacterReferenceEnd
			return
		}

		if ch.isASCIIDigit {
			// Cap at 0x110000 to detect overflow (any value > 0x10FFFF is invalid)
			// Use 0x110000 as sentinel for "too large"
			if self.charRefCode <= 0x10FFFF {
				let newValue = UInt64(self.charRefCode) * 10 + UInt64(ch.asciiValue! - 0x30)
				self.charRefCode = newValue > 0x10FFFF ? 0x110000 : UInt32(newValue)
			}
		}
		else if ch == ";" {
			self.state = .numericCharacterReferenceEnd
		}
		else {
			self.emitError("missing-semicolon-after-character-reference")
			self.state = .numericCharacterReferenceEnd
			self.reconsume()
		}
	}

	private func numericCharacterReferenceEndState() {
		// Check for various error conditions
		if self.charRefCode == 0 {
			self.emitError("null-character-reference")
		}
		else if self.charRefCode > 0x10FFFF {
			self.emitError("character-reference-outside-unicode-range")
		}
		else if self.charRefCode >= 0xD800 && self.charRefCode <= 0xDFFF {
			self.emitError("surrogate-character-reference")
		}
		else if (self.charRefCode >= 0xFDD0 && self.charRefCode <= 0xFDEF)
			|| (self.charRefCode & 0xFFFF) == 0xFFFE || (self.charRefCode & 0xFFFF) == 0xFFFF
		{
			self.emitError("noncharacter-character-reference")
		}
		else if self.charRefCode < 0x20 && self.charRefCode != 0x09 && self.charRefCode != 0x0A
			&& self.charRefCode != 0x0C || (self.charRefCode >= 0x7F && self.charRefCode <= 0x9F)
		{
			self.emitError("control-character-reference")
		}

		// Decode the code point (with possible replacement)
		let result: String
		if self.charRefCode == 0 {
			result = "\u{FFFD}"
		}
		else if self.charRefCode > 0x10FFFF {
			result = "\u{FFFD}"
		}
		else if self.charRefCode >= 0xD800, self.charRefCode <= 0xDFFF {
			result = "\u{FFFD}"
		}
		else {
			// Check for windows-1252 replacements
			let replacements: [UInt32: UInt32] = [
				0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E,
				0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
				0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152,
				0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
				0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
				0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
				0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
			]
			let finalCode = replacements[charRefCode] ?? self.charRefCode
			if let scalar = Unicode.Scalar(finalCode) {
				result = String(Character(scalar))
			}
			else {
				result = "\u{FFFD}"
			}
		}

		self.charRefTempBuffer = ""
		self.emitCharRefString(result)
		self.state = self.returnState
	}

	// MARK: - CDATA States

	private func cdataSectionState() {
		guard let ch = consume() else {
			self.emitError("eof-in-cdata")
			return
		}

		if ch == "]" {
			self.state = .cdataSectionBracket
		}
		else {
			self.emitChar(ch)
		}
	}

	private func cdataSectionBracketState() {
		guard let ch = consume() else {
			self.emitChar("]")
			self.state = .cdataSection
			return
		}

		if ch == "]" {
			self.state = .cdataSectionEnd
		}
		else {
			self.emitChar("]")
			self.state = .cdataSection
			self.reconsume()
		}
	}

	private func cdataSectionEndState() {
		guard let ch = consume() else {
			self.emitString("]]")
			self.state = .cdataSection
			return
		}

		if ch == "]" {
			self.emitChar("]")
		}
		else if ch == ">" {
			self.state = .data
		}
		else {
			self.emitString("]]")
			self.state = .cdataSection
			self.reconsume()
		}
	}
}

// MARK: - Character Extensions

extension Character {
	/// Check if character is ASCII letter (A-Z or a-z)
	@inline(__always)
	var isASCIILetter: Bool {
		return ("a" ... "z").contains(self) || ("A" ... "Z").contains(self)
	}

	/// Check if character is ASCII digit (0-9)
	@inline(__always)
	var isASCIIDigit: Bool {
		return ("0" ... "9").contains(self)
	}

	/// Check if character is hex digit (0-9, a-f, A-F)
	@inline(__always)
	var isHexDigit: Bool {
		return self.isASCIIDigit || ("a" ... "f").contains(self) || ("A" ... "F").contains(self)
	}

	/// Convert to lowercase character (ASCII optimized)
	@inline(__always)
	var asLowercaseCharacter: Character {
		if let ascii = self.asciiValue, ascii >= 65, ascii <= 90 {
			return Character(UnicodeScalar(ascii + 32))
		}
		return self
	}
}

// MARK: - String Extensions for ASCII Case-Insensitive Operations

extension String {
	/// Fast ASCII case-insensitive comparison using UTF-8 bytes
	/// Returns true if strings are equal ignoring ASCII case
	@inline(__always)
	func asciiCaseInsensitiveEquals(_ other: String) -> Bool {
		let selfUTF8 = self.utf8
		let otherUTF8 = other.utf8

		guard selfUTF8.count == otherUTF8.count else { return false }

		var selfIter = selfUTF8.makeIterator()
		var otherIter = otherUTF8.makeIterator()

		while let b1 = selfIter.next(), let b2 = otherIter.next() {
			if b1 != b2 {
				// Check if they differ only by ASCII case
				let lower1 = b1 >= 65 && b1 <= 90 ? b1 + 32 : b1
				let lower2 = b2 >= 65 && b2 <= 90 ? b2 + 32 : b2
				if lower1 != lower2 {
					return false
				}
			}
		}

		return true
	}

	/// Fast ASCII case-insensitive prefix check using UTF-8 bytes
	@inline(__always)
	func asciiCaseInsensitiveHasPrefix(_ prefix: String) -> Bool {
		let selfUTF8 = self.utf8
		let prefixUTF8 = prefix.utf8

		guard selfUTF8.count >= prefixUTF8.count else { return false }

		var selfIter = selfUTF8.makeIterator()
		var prefixIter = prefixUTF8.makeIterator()

		while let prefixByte = prefixIter.next() {
			guard let selfByte = selfIter.next() else { return false }
			if selfByte != prefixByte {
				let lowerSelf = selfByte >= 65 && selfByte <= 90 ? selfByte + 32 : selfByte
				let lowerPrefix = prefixByte >= 65 && prefixByte <= 90 ? prefixByte + 32 : prefixByte
				if lowerSelf != lowerPrefix {
					return false
				}
			}
		}

		return true
	}

	/// Fast ASCII lowercase (for HTML tag/attribute names which are ASCII)
	@inline(__always)
	func asciiLowercased() -> String {
		var bytes = ContiguousArray<UInt8>()
		bytes.reserveCapacity(self.utf8.count)
		for byte in self.utf8 {
			if byte >= 65, byte <= 90 {
				bytes.append(byte + 32)
			}
			else {
				bytes.append(byte)
			}
		}
		return String(decoding: bytes, as: UTF8.self)
	}
}

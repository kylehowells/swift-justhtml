// TreeBuilder.swift - HTML5 tree construction algorithm

import Foundation

// MARK: - FragmentContext

/// Fragment context for parsing HTML fragments
public struct FragmentContext {
	public let tagName: String
	public let namespace: Namespace?

	public init(_ tagName: String, namespace: Namespace? = nil) {
		self.tagName = tagName
		self.namespace = namespace
	}
}

// MARK: - InsertionMode

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

private enum ResetInsertionModeDecision {
	case use(InsertionMode)
	case continueSearch
	case skipElement
	case stop
}

private enum OtherEndTagStackSearchResult {
	case match(Int)
	case blockedBySpecialElement
	case noMatch
}

private enum ForeignContentEndTagSearchResult {
	case foreignMatch(Int)
	case htmlBoundaryOrNoMatch
}

private struct StartTagToken {
	let name: String
	let tagId: TagID
	let attrs: [String: String]
	let selfClosing: Bool

	init(name: String, attrs: [String: String], selfClosing: Bool) {
		self.name = name
		self.tagId = TagID.from(name)
		self.attrs = attrs
		self.selfClosing = selfClosing
	}
}

private struct EndTagToken {
	let name: String
	let tagId: TagID

	init(name: String) {
		self.name = name
		self.tagId = TagID.from(name)
	}
}

// MARK: - Tree Builder Constants

private let kQuirksPublicIdPrefixes = [
	"-//w3c//dtd html 3.2",
	"-//w3c//dtd html 4.0 transitional",
	"-//w3c//dtd html 4.0 frameset",
	"-//w3c//dtd html 4.01 transitional",
	"-//w3c//dtd html 4.01 frameset",
	"html", // Just "html" as public id
]
// MARK: - TreeBuilder

/// Tree builder that constructs DOM from tokens
public final class TreeBuilder: TokenSink {
	/// Document root
	private var document: Node

	/// Stack of open elements
	private var openElements: [Node] = []

	/// Active formatting elements
	private var activeFormattingElements: [Node?] = [] // nil = marker

	// Current insertion mode
	private var insertionMode: InsertionMode = .initial
	private var originalInsertionMode: InsertionMode = .initial

	/// Template insertion mode stack
	private var templateInsertionModes: [InsertionMode] = []

	// Head and body element references
	private var headElement: Node? = nil
	private var bodyElement: Node? = nil

	/// Form element pointer
	private var formElement: Node? = nil

	// Fragment context
	private let fragmentContext: FragmentContext?
	private var contextElement: Node? = nil

	// Flags
	private var framesetOk: Bool = true
	private var skipNextNewline: Bool = false // For pre/listing/textarea leading newline
	private var scripting: Bool = false
	private var iframeSrcdoc: Bool = false
	private var fosterParentingEnabled: Bool = false
	private var quirksMode: Bool = false // Document mode: quirks, limited-quirks, or no-quirks
	private var sawSelectElement: Bool = false
	private var sawSelectedcontentElement: Bool = false

	/// Pending table character tokens
	private var pendingTableCharacterTokens: String = ""
	private var pendingTableCharacterTokensAreWhitespace: Bool = true

	// Error collection
	public var errors: [ParseError] = []
	private var collectErrors: Bool

	/// Maximum nesting depth (DoS protection)
	private let maxNestingDepth: Int

	/// Reference to tokenizer for switching states
	public weak var tokenizer: Tokenizer? = nil

	/// Current namespace of the current element (for tokenizer state switching)
	public var currentNamespace: Namespace? {
		guard let currentNode = openElements.last else { return nil }

		return currentNode.namespace
	}

	public init(
		fragmentContext: FragmentContext? = nil,
		iframeSrcdoc: Bool = false,
		collectErrors: Bool = false,
		scripting: Bool = false,
		maxNestingDepth: Int = ParserLimits.default.maxNestingDepth
	) {
		self.fragmentContext = fragmentContext
		self.iframeSrcdoc = iframeSrcdoc
		self.collectErrors = collectErrors
		self.scripting = scripting
		self.maxNestingDepth = maxNestingDepth

		if fragmentContext != nil {
			self.document = Node.documentFragment()
		}
		else {
			self.document = Node.document()
		}

		// Set up fragment parsing context per WHATWG spec
		if let ctx = fragmentContext {
			// Create context element (virtual, not part of the tree)
			let ctxElement = Node(name: ctx.tagName, namespace: ctx.namespace ?? .html)
			self.contextElement = ctxElement

			// Create root html element and push onto stack (step 5-7 of fragment algorithm)
			let htmlElement = Node(name: "html", namespace: .html)
			self.document.appendChild(htmlElement)
			self.openElements.append(htmlElement)

			// For template context, push inTemplate onto template insertion modes
			if ctx.tagName == "template" {
				self.templateInsertionModes.append(.inTemplate)
			}

			// Reset insertion mode based on context element
			self.resetInsertionModeForFragment()
		}
	}

	/// Reset insertion mode specifically for fragment parsing (empty open elements stack)
	private func resetInsertionModeForFragment() {
		guard let ctx = contextElement else {
			self.insertionMode = .inBody
			return
		}

		self.insertionMode = self.initialInsertionModeForFragmentContext(ctx.name)
	}

	/// Finish parsing and return the root
	public func finish() -> Node {
		// Populate selectedcontent elements with content from selected option
		if self.sawSelectElement && self.sawSelectedcontentElement {
			self.populateSelectedcontent(self.document)
		}
		return self.document
	}

	/// Populate selectedcontent elements with content from the selected option
	/// Per HTML5 spec: selectedcontent mirrors the content of the selected option,
	/// or the first option if none is selected.
	private func populateSelectedcontent(_ root: Node) {
		var firstTarget: (source: Node, destination: Node)? = nil
		var additionalTargets: [(source: Node, destination: Node)]? = nil
		self.collectSelectedcontentCloneTargets(
			in: root,
			firstTarget: &firstTarget,
			additionalTargets: &additionalTargets)

		if let firstTarget {
			self.cloneChildren(from: firstTarget.source, to: firstTarget.destination)
		}
		if let additionalTargets {
			for target in additionalTargets {
				self.cloneChildren(from: target.source, to: target.destination)
			}
		}
	}

	private func collectSelectedcontentCloneTargets(
		in node: Node,
		firstTarget: inout (source: Node, destination: Node)?,
		additionalTargets: inout [(source: Node, destination: Node)]?
	) {
		if node.tagId == .select, let target = self.selectedcontentCloneTarget(in: node) {
			if firstTarget == nil {
				firstTarget = target
			}
			else {
				if additionalTargets == nil {
					additionalTargets = []
				}
				additionalTargets!.append(target)
			}
		}

		for child in node.children {
			self.collectSelectedcontentCloneTargets(
				in: child,
				firstTarget: &firstTarget,
				additionalTargets: &additionalTargets)
		}

		// Also search in template content
		if let content = node.templateContent {
			for child in content.children {
				self.collectSelectedcontentCloneTargets(
					in: child,
					firstTarget: &firstTarget,
					additionalTargets: &additionalTargets)
			}
		}
	}

	private func selectedcontentCloneTarget(in select: Node) -> (source: Node, destination: Node)? {
		var selectedcontent: Node? = nil
		var firstOption: Node? = nil
		var firstSelectedOption: Node? = nil
		self.findSelectedcontentSelection(
			in: select,
			selectedcontent: &selectedcontent,
			firstOption: &firstOption,
			firstSelectedOption: &firstSelectedOption
		)

		guard let destination = selectedcontent, let source = firstSelectedOption ?? firstOption else {
			return nil
		}
		return (source, destination)
	}

	private func findSelectedcontentSelection(
		in node: Node,
		selectedcontent: inout Node?,
		firstOption: inout Node?,
		firstSelectedOption: inout Node?
	) {
		if node.tagId == .selectedcontent, selectedcontent == nil {
			selectedcontent = node
		}

		if node.tagId == .option {
			if firstOption == nil {
				firstOption = node
			}
			if firstSelectedOption == nil, node.attrs["selected"] != nil {
				firstSelectedOption = node
			}
		}

		guard selectedcontent == nil || firstSelectedOption == nil else { return }

		for child in node.children {
			self.findSelectedcontentSelection(
				in: child,
				selectedcontent: &selectedcontent,
				firstOption: &firstOption,
				firstSelectedOption: &firstSelectedOption
			)
			if selectedcontent != nil && firstSelectedOption != nil {
				return
			}
		}

		if let content = node.templateContent {
			for child in content.children {
				self.findSelectedcontentSelection(
					in: child,
					selectedcontent: &selectedcontent,
					firstOption: &firstOption,
					firstSelectedOption: &firstSelectedOption
				)
				if selectedcontent != nil && firstSelectedOption != nil {
					return
				}
			}
		}
	}

	/// Clone children from one node to another
	private func cloneChildren(from source: Node, to dest: Node) {
		for child in source.children {
			let cloned = self.cloneNode(child)
			dest.appendChild(cloned)
		}
	}

	/// Deep clone a node
	private func cloneNode(_ node: Node) -> Node {
		let clone = Node(name: node.name, namespace: node.namespace, attrs: node.attrs, data: node.data)
		for child in node.children {
			clone.appendChild(self.cloneNode(child))
		}
		return clone
	}

	// MARK: - TokenSink

	public func processToken(_ token: Token) {
		switch token {
			case let .character(text):
				self.processCharacters(text)

			case let .startTag(name, attrs, selfClosing):
				self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)

			case let .endTag(name):
				self.processEndTag(name: name)

			case let .comment(text):
				self.processComment(text)

			case let .doctype(doctype):
				self.processDoctype(doctype)

			case .eof:
				self.processEOF()
		}
	}

	// MARK: - Token Processing

	private func processCharacters(_ text: String) {
		// Fast path for .text mode (script/style/etc content) - insert entire string at once
		if self.insertionMode == .text {
			// Handle skipNextNewline for textarea/pre/listing
			if self.skipNextNewline {
				self.skipNextNewline = false
				if text.first == "\n" {
					// Skip the first newline
					let remaining = String(text.dropFirst())
					if !remaining.isEmpty {
						self.insertText(remaining)
					}
					return
				}
			}
			self.insertText(text)
			return
		}

		// Fast path for .inBody mode - batch consecutive non-null characters
		if self.insertionMode == .inBody, !self.skipNextNewline,
		   !self.isInMathMLTextIntegrationPoint(), !self.isInSVGHtmlIntegrationPoint(),
		   !self.isInMathMLAnnotationXmlIntegrationPoint(), !self.shouldProcessInForeignContent()
		{
			if self.framesetOk {
				let textScan = self.scanTextForNullAndNonWhitespace(text)
				if !textScan.hasNull {
					self.reconstructActiveFormattingElements()
					self.insertText(text)
					if textScan.hasNonWhitespace {
						self.framesetOk = false
					}
					return
				}
			}
			else if !self.containsNullByte(text) {
				self.reconstructActiveFormattingElements()
				self.insertText(text)
				return
			}
		}

		// Fall back to character-by-character processing for complex cases
		for ch in text {
			self.processCharacter(ch)
		}
	}

	private func processCharacter(_ ch: Character) {
		// Skip first newline after pre/listing/textarea
		if self.skipNextNewline {
			self.skipNextNewline = false
			if ch == "\n" {
				return
			}
		}

		// HTML integration points (MathML text integration points, SVG HTML integration points,
		// and MathML annotation-xml with encoding) process characters as HTML
		// Check this BEFORE foreign content check since shouldProcessInForeignContent returns true for math namespace
		if self.isInMathMLTextIntegrationPoint() || self.isInSVGHtmlIntegrationPoint()
			|| self.isInMathMLAnnotationXmlIntegrationPoint()
		{
			self.processCharacterInIntegrationPoint(ch)
			return
		}

		// Check for foreign content - process characters according to foreign content rules
		if self.shouldProcessInForeignContent() {
			self.processCharacterInForeignContent(ch)
			return
		}

		switch self.insertionMode {
			case .initial:
				if self.isWhitespace(ch) {
					// Ignore
				}
				else {
					// Parse error - anything other than whitespace in initial mode sets quirks mode
					self.emitError("expected-doctype-but-got-chars")
					self.quirksMode = true
					self.insertionMode = .beforeHtml
					self.processCharacter(ch)
				}

			case .beforeHtml:
				if self.isWhitespace(ch) {
					// Ignore
				}
				else {
					self.insertHtmlElement()
					self.insertionMode = .beforeHead
					self.processCharacter(ch)
				}

			case .beforeHead:
				if self.isWhitespace(ch) {
					// Ignore
				}
				else {
					self.insertHeadElement()
					self.insertionMode = .inHead
					self.processCharacter(ch)
				}

			case .inHead:
				if self.isWhitespace(ch) {
					self.insertCharacter(ch)
				}
				else {
					// Act as if </head> was seen
					self.popCurrentElement() // head
					self.insertionMode = .afterHead
					self.processCharacter(ch)
				}

			case .inHeadNoscript:
				if self.isWhitespace(ch) {
					self.insertCharacter(ch)
				}
				else {
					// Pop noscript and reprocess
					self.emitError("unexpected-char")
					self.popCurrentElement()
					self.insertionMode = .inHead
					self.processCharacter(ch)
				}

			case .afterHead:
				if self.isWhitespace(ch) {
					self.insertCharacter(ch)
				}
				else {
					self.insertBodyElement()
					self.insertionMode = .inBody
					self.processCharacter(ch)
				}

			case .inBody:
				self.processBodyCharacter(ch)

			case .text:
				self.insertCharacter(ch)

			case .afterBody:
				self.processCharacterAfterBody(ch)

			case .afterAfterBody:
				self.processCharacterAfterBody(ch)

			case .inFrameset:
				self.processCharacterInFrameset(ch)

			case .afterFrameset:
				self.processCharacterAfterFrameset(ch)

			case .afterAfterFrameset:
				self.processCharacterAfterFrameset(ch)

			case .inColumnGroup:
				if self.isWhitespace(ch) {
					self.insertCharacter(ch)
				}
				else {
					// Non-whitespace: pop colgroup and reprocess in inTable
					if self.currentNode?.tagId == .colgroup {
						self.popCurrentElement()
						self.insertionMode = .inTable
						self.processCharacter(ch)
					}
					else {
						self.emitError("unexpected-char-in-column-group")
					}
				}

			case .inTable, .inTableBody, .inRow:
				self.startTableTextBuffer(with: ch)

			case .inTableText:
				self.bufferTableTextCharacter(ch)

			case .inCell, .inCaption:
				self.processBodyCharacter(ch)

			case .inSelect, .inSelectInTable:
				self.processCharacterInSelect(ch)

			default:
				self.insertCharacter(ch)
		}
	}

	private func processCharacterInIntegrationPoint(_ ch: Character) {
		if ch == "\0" {
			self.emitError("unexpected-null-character")
		}
		else if ch == "\u{0C}" {
			self.emitError("invalid-codepoint")
		}
		else {
			self.insertHtmlCharacter(ch)
		}
	}

	private func processCharacterInForeignContent(_ ch: Character) {
		if ch == "\0" {
			self.emitError("unexpected-null-character")
			self.insertCharacter("\u{FFFD}")
		}
		else if ch == "\u{0C}" {
			self.emitError("invalid-codepoint")
		}
		else {
			self.insertCharacter(ch)
			if !self.isWhitespace(ch) {
				self.framesetOk = false
			}
		}
	}

	private func processBodyCharacter(_ ch: Character) {
		if ch == "\0" {
			self.emitError("unexpected-null-character")
		}
		else {
			self.insertHtmlCharacter(ch)
		}
	}

	private func insertHtmlCharacter(_ ch: Character) {
		self.reconstructActiveFormattingElements()
		self.insertCharacter(ch)
		if !self.isWhitespace(ch) {
			self.framesetOk = false
		}
	}

	private func processCharacterAfterBody(_ ch: Character) {
		if self.isWhitespace(ch) {
			self.insertCharacter(ch)
		}
		else {
			self.emitError("unexpected-char-after-body")
			self.insertionMode = .inBody
			self.processCharacter(ch)
		}
	}

	private func processCharacterInFrameset(_ ch: Character) {
		if self.isWhitespace(ch) {
			self.insertCharacter(ch)
		}
		else if ch == "\0" {
			self.emitError("unexpected-null-character")
		}
		else {
			self.emitError("unexpected-char-in-frameset")
		}
	}

	private func processCharacterAfterFrameset(_ ch: Character) {
		if self.isWhitespace(ch) {
			self.insertCharacter(ch)
		}
		else if ch == "\0" {
			self.emitError("unexpected-null-character")
		}
		else {
			self.emitError("unexpected-char-after-frameset")
		}
	}

	private func startTableTextBuffer(with ch: Character) {
		if self.bufferTableTextCharacter(ch) {
			self.originalInsertionMode = self.insertionMode
			self.insertionMode = .inTableText
		}
	}

	@discardableResult
	private func bufferTableTextCharacter(_ ch: Character) -> Bool {
		if ch == "\0" {
			self.emitError("unexpected-null-character")
			return false
		}
		if ch == "\u{0C}" {
			self.emitError("invalid-codepoint-in-table-text")
			return false
		}

		self.pendingTableCharacterTokens.append(ch)
		if !self.isWhitespace(ch) {
			self.pendingTableCharacterTokensAreWhitespace = false
		}
		return true
	}

	private func processCharacterInSelect(_ ch: Character) {
		if ch == "\0" {
			self.emitError("unexpected-null-character")
		}
		else if ch == "\u{0C}" {
			self.emitError("invalid-codepoint-in-select")
		}
		else {
			self.reconstructActiveFormattingElements()
			self.insertCharacter(ch)
		}
	}

	/// Flush pending table character tokens (called before processing non-character tokens)
	private func flushPendingTableCharacterTokens() {
		guard self.insertionMode == .inTableText else { return }

		guard !self.pendingTableCharacterTokens.isEmpty else {
			self.insertionMode = self.originalInsertionMode
			return
		}

		if self.pendingTableCharacterTokensAreWhitespace {
			// Insert whitespace normally into the table
			for ch in self.pendingTableCharacterTokens {
				self.insertCharacter(ch)
			}
		}
		else {
			// Foster parent all characters (including whitespace)
			self.emitError("unexpected-char-in-table")
			self.withFosterParenting {
				for ch in self.pendingTableCharacterTokens {
					self.reconstructActiveFormattingElements()
					self.insertCharacter(ch)
					if !self.isWhitespace(ch) {
						self.framesetOk = false
					}
				}
			}
		}

		self.pendingTableCharacterTokens = ""
		self.pendingTableCharacterTokensAreWhitespace = true
		self.insertionMode = self.originalInsertionMode
	}

	private func processStartTag(name: String, attrs: [String: String], selfClosing: Bool) {
		self.processStartTag(StartTagToken(name: name, attrs: attrs, selfClosing: selfClosing))
	}

	private func processStartTag(_ tag: StartTagToken) {
		let name = tag.name
		let attrs = tag.attrs
		let selfClosing = tag.selfClosing

		// Flush pending table character tokens before processing any non-character token
		self.flushPendingTableCharacterTokens()
		// Check for foreign content processing
		if self.shouldProcessInForeignContent() {
			if self.processForeignContentStartTag(name: name, attrs: attrs, selfClosing: selfClosing) {
				return // Handled by foreign content rules
			}
			// Fall through to normal processing if breakout element or integration point
		}

		// Special handling for integration points in table modes without actual table in scope
		// Per Python justhtml: when at MathML text integration point or HTML integration point,
		// in a table mode but without a table in scope, use IN_BODY mode to process tags
		// This ensures table-related tags are ignored when there's no real table structure
		let atIntegrationPoint =
			self.isInMathMLTextIntegrationPoint() || self.isInSVGHtmlIntegrationPoint()
				|| self.isInMathMLAnnotationXmlIntegrationPoint()
		if self.insertionMode != .inBody, atIntegrationPoint {
			if self.isTableFamilyInsertionMode, !self.hasElementInTableScope(.table) {
				self.processStartTagUsingModeIfUnchanged(
					.inBody, name: name, attrs: attrs, selfClosing: selfClosing)
				return
			}
		}

		switch self.insertionMode {
			case .initial:
				// Parse error - start tag in initial mode sets quirks mode
				self.emitError("expected-doctype-but-got-start-tag")
				self.quirksMode = true
				self.insertionMode = .beforeHtml
				self.processStartTag(tag)

			case .beforeHtml:
				self.processStartTagBeforeHtml(name: name, attrs: attrs, selfClosing: selfClosing)

			case .beforeHead:
				self.processStartTagBeforeHead(name: name, attrs: attrs, selfClosing: selfClosing)

			case .inHead:
				self.processStartTagInHead(tag)

			case .inHeadNoscript:
				self.processStartTagInHeadNoscript(tag)

			case .afterHead:
				self.processStartTagAfterHead(tag)

			case .inBody:
				self.processStartTagInBody(tag)

			case .text:
				// Should not happen
				break

			case .afterBody:
				self.processStartTagAfterBody(name: name, attrs: attrs, selfClosing: selfClosing)

			case .afterAfterBody:
				self.processStartTagAfterBody(name: name, attrs: attrs, selfClosing: selfClosing)

			case .inTable:
				self.processStartTagInTable(tag)

			case .inTableBody:
				self.processStartTagInTableBody(tag)

			case .inRow:
				self.processStartTagInRow(tag)

			case .inCell:
				self.processStartTagInCell(tag)

			case .inColumnGroup:
				self.processStartTagInColumnGroup(tag)

			case .inCaption:
				self.processStartTagInCaption(tag)

			case .inFrameset:
				self.processStartTagInFrameset(name: name, attrs: attrs, selfClosing: selfClosing)

			case .afterFrameset:
				self.processStartTagAfterFrameset(name: name, attrs: attrs, selfClosing: selfClosing)

			case .afterAfterFrameset:
				self.processStartTagAfterFrameset(name: name, attrs: attrs, selfClosing: selfClosing)

			case .inTemplate:
				self.processStartTagInTemplate(tag)

			case .inSelect:
				self.processStartTagInSelect(tag)

			case .inSelectInTable:
				self.processStartTagInSelectInTable(tag)

			default:
				self.processStartTagInBody(tag)
		}
	}

	private var isTableFamilyInsertionMode: Bool {
		switch self.insertionMode {
			case .inTable, .inTableBody, .inRow, .inCell, .inCaption, .inColumnGroup:
				return true
			default:
				return false
		}
	}

	private func processStartTagBeforeHtml(name: String, attrs: [String: String], selfClosing: Bool) {
		if name == "html" {
			let element = self.createElement(name: name, namespace: .html, attrs: attrs)
			self.document.appendChild(element)
			self.openElements.append(element)
			self.insertionMode = .beforeHead
		}
		else {
			self.insertHtmlElement()
			self.insertionMode = .beforeHead
			self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
		}
	}

	private func processStartTagBeforeHead(name: String, attrs: [String: String], selfClosing: Bool) {
		if name == "html" {
			self.mergeAttributesOntoHtml(attrs)
		}
		else if name == "head" {
			let element = self.insertElement(name: name, attrs: attrs)
			self.headElement = element
			self.insertionMode = .inHead
		}
		else {
			self.insertHeadElement()
			self.insertionMode = .inHead
			self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
		}
	}

	private func processStartTagInHead(_ tag: StartTagToken) {
		switch tag.tagId {
			case .html:
				self.processStartTagInBody(tag)

			case .base, .basefont, .bgsound, .link, .meta:
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.popCurrentElement()

			case .title:
				self.parseRCDATA(name: tag.name, attrs: tag.attrs)

			case .noscript:
				if self.scripting {
					self.parseRawtext(name: tag.name, attrs: tag.attrs)
				}
				else {
					_ = self.insertElement(name: tag.name, attrs: tag.attrs)
					self.insertionMode = .inHeadNoscript
				}

			case .noframes, .script, .style:
				self.parseRawtext(name: tag.name, attrs: tag.attrs)

			case .template:
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.templateInsertionModes.append(.inTemplate)
				self.insertionMode = .inTemplate

			case .head:
				self.emitError("unexpected-start-tag")

			default:
				self.popCurrentElement()
				self.insertionMode = .afterHead
				self.processStartTag(tag)
		}
	}

	private func processStartTagInHeadNoscript(_ tag: StartTagToken) {
		switch tag.tagId {
			case .html:
				self.processStartTagInBody(tag)

			case .basefont, .bgsound, .link, .meta, .noframes, .style:
				self.processStartTagUsingRules(of: .inHead, tag)

			case .head, .noscript:
				self.emitError("unexpected-start-tag")

			default:
				self.emitError("unexpected-start-tag")
				self.popCurrentElement()
				self.insertionMode = .inHead
				self.processStartTag(tag)
		}
	}

	private func processStartTagAfterHead(_ tag: StartTagToken) {
		switch tag.tagId {
			case .html:
				self.processStartTagInBody(tag)

			case .body:
				let element = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.bodyElement = element
				self.framesetOk = false
				self.insertionMode = .inBody

			case .frameset:
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.insertionMode = .inFrameset

			case .base, .basefont, .bgsound, .link, .meta, .noframes,
			     .script, .style, .template, .title:
				self.processHeadProcessingStartTagAfterHead(tag)

			case .head:
				self.emitError("unexpected-start-tag")

			default:
				self.insertBodyElement()
				self.insertionMode = .inBody
				self.processStartTag(tag)
		}
	}

	private func processHeadProcessingStartTagAfterHead(_ tag: StartTagToken) {
		self.emitError("unexpected-start-tag")
		if let head = headElement {
			self.openElements.append(head)
		}
		self.processStartTagUsingRules(of: .inHead, tag, preserveTemplateMode: true)
		if let headElement {
			self.removeLastOpenElement(matching: headElement)
		}
	}

	private func processStartTagAfterBody(name: String, attrs: [String: String], selfClosing: Bool) {
		if name == "html" {
			self.mergeAttributesOntoHtml(attrs)
		}
		else {
			self.emitError("unexpected-start-tag-after-body")
			self.insertionMode = .inBody
			self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
		}
	}

	private func processStartTagInFrameset(name: String, attrs: [String: String], selfClosing: Bool) {
		if name == "html" {
			self.insertionMode = .inBody
			self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
		}
		else if name == "frameset" {
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if name == "frame" {
			_ = self.insertElement(name: name, attrs: attrs)
			self.popCurrentElement()
		}
		else if name == "noframes" {
			self.parseRawtext(name: name, attrs: attrs)
		}
		else {
			self.emitError("unexpected-start-tag-in-frameset")
		}
	}

	private func processStartTagAfterFrameset(
		name: String,
		attrs: [String: String],
		selfClosing: Bool
	) {
		if name == "html" {
			self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
		}
		else if name == "noframes" {
			self.parseRawtext(name: name, attrs: attrs)
		}
		else {
			self.emitError("unexpected-start-tag-after-frameset")
		}
	}

	private func processStartTagInSelectInTable(_ tag: StartTagToken) {
		switch tag.tagId {
			case .caption, .table, .tbody, .tfoot, .thead, .tr, .td, .th:
				self.emitError("unexpected-start-tag-in-select")
				if !self.closeSelectOrContextForReprocessing() {
					self.closeOpenSelectAndResetInsertionMode()
				}
				self.processStartTag(tag)

			default:
				self.processStartTagUsingModeIfUnchanged(.inSelect, tag)
		}
	}

	private func processStartTagInTemplate(_ tag: StartTagToken) {
		switch tag.tagId {
			case .base, .basefont, .bgsound, .link, .meta, .noframes,
			     .script, .style, .template, .title:
				self.processStartTagUsingRules(of: .inHead, tag)

			case .caption, .colgroup, .tbody, .tfoot, .thead:
				self.replaceTemplateInsertionModeAndReprocessStartTag(.inTable, tag)

			case .col:
				self.replaceTemplateInsertionModeAndReprocessStartTag(.inColumnGroup, tag)

			case .tr:
				self.replaceTemplateInsertionModeAndReprocessStartTag(.inTableBody, tag)

			case .td, .th:
				self.replaceTemplateInsertionModeAndReprocessStartTag(.inRow, tag)

			default:
				self.replaceTemplateInsertionModeAndReprocessStartTag(.inBody, tag)
		}
	}

	private func processStartTagInSelect(_ tag: StartTagToken) {
		switch tag.tagId {
			case .html:
				self.processStartTagInBody(tag)

			case .option:
				if self.currentNode?.tagId == .option {
					self.popCurrentElement()
				}
				self.reconstructActiveFormattingElements()
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)

			case .optgroup:
				self.popOpenOptionOrOptgroupForSelectInsertion()
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)

			case .hr, .keygen:
				self.popOpenOptionOrOptgroupForSelectInsertion()
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.popCurrentElement()

			case .plaintext:
				self.popOpenOptionOrOptgroupForSelectInsertion()
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.tokenizer?.switchToPlaintext()

			case .select:
				self.emitError("unexpected-start-tag-in-select")
				// Per browser behavior, check if select is anywhere on the stack, not using strict scope.
				if self.hasOpenElement(.select) {
					self.closeOpenSelectAndResetInsertionMode()
				}

			case .input:
				self.emitError("unexpected-start-tag-in-select")
				if !self.hasElementInSelectScope(.select) {
					return
				}
				if self.isSelectContextOnly {
					return
				}
				self.closeOpenSelectAndResetInsertionMode()
				self.processStartTag(tag)

			case .script, .template:
				self.processStartTagUsingRules(of: .inHead, tag, preserveTemplateMode: true)

			case .svg:
				self.insertForeignElement(
					name: tag.name, namespace: .svg, attrs: tag.attrs, selfClosing: tag.selfClosing)

			case .math:
				self.insertForeignElement(
					name: tag.name, namespace: .math, attrs: tag.attrs, selfClosing: tag.selfClosing)

			default:
				self.processOtherStartTagInSelect(tag)
		}
	}

	private func processStartTagInTable(_ tag: StartTagToken) {
		switch tag.tagId {
			case .caption:
				self.insertTableContextElement(name: tag.name, attrs: tag.attrs, mode: .inCaption, insertMarker: true)

			case .colgroup:
				self.insertTableContextElement(name: tag.name, attrs: tag.attrs, mode: .inColumnGroup)

			case .col:
				self.insertImpliedColumnGroupAndReprocessStartTag(tag)

			case .tbody, .tfoot, .thead:
				self.insertTableContextElement(name: tag.name, attrs: tag.attrs, mode: .inTableBody)

			case .tr, .td, .th:
				self.insertImpliedTableBodyAndReprocessStartTag(tag)

			case .table:
				self.closeCurrentTableAndReprocessStartTag(tag)

			case .script, .style, .template:
				self.processStartTagUsingRules(of: .inHead, tag, preserveTemplateMode: true)

			case .input:
				self.processInputStartTagInTable(attrs: tag.attrs, selfClosing: tag.selfClosing)

			case .form:
				self.processFormStartTagInTable(attrs: tag.attrs)

			default:
				self.fosterStartTagFromTable(tag)
		}
	}

	private func insertTableContextElement(
		name: String,
		attrs: [String: String],
		mode: InsertionMode,
		insertMarker: Bool = false
	) {
		self.clearStackBackToTableContext()
		if insertMarker {
			self.insertMarker()
		}
		_ = self.insertElement(name: name, attrs: attrs)
		self.insertionMode = mode
	}

	private func insertImpliedColumnGroupAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag) {
			self.insertTableContextElement(name: "colgroup", attrs: [:], mode: .inColumnGroup)
		}
	}

	private func insertImpliedTableBodyAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag) {
			self.insertTableContextElement(name: "tbody", attrs: [:], mode: .inTableBody)
		}
	}

	private func closeCurrentTableAndReprocessStartTag(_ tag: StartTagToken) {
		self.emitError("unexpected-start-tag-implies-end-tag")
		if self.hasElementInTableScope(.table) {
			self.closeCurrentTable()
			self.processStartTag(tag)
		}
	}

	private func processInputStartTagInTable(attrs: [String: String], selfClosing: Bool) {
		if self.isHiddenInput(attrs) {
			self.emitError("unexpected-hidden-input-in-table")
			_ = self.insertElement(name: "input", attrs: attrs)
			self.popCurrentElement()
		}
		else {
			self.fosterStartTagFromTable(
				StartTagToken(name: "input", attrs: attrs, selfClosing: selfClosing))
		}
	}

	private func processFormStartTagInTable(attrs: [String: String]) {
		self.emitError("unexpected-start-tag-in-table")
		if self.formElement == nil, !self.hasElementInScope(.template) {
			let element = self.insertElement(name: "form", attrs: attrs)
			self.formElement = element
			self.popCurrentElement()
		}
	}

	private func fosterStartTagFromTable(_ tag: StartTagToken) {
		self.emitError("unexpected-start-tag-in-table")
		self.processStartTagInBodyWithFosterParenting(tag)
	}

	private func processStartTagInTableBody(_ tag: StartTagToken) {
		switch tag.tagId {
			case .tr:
				self.insertTableRowElement(name: tag.name, attrs: tag.attrs)

			case .td, .th:
				self.emitError("unexpected-cell-in-table-body")
				self.insertImpliedTableRowAndReprocessStartTag(tag)

			case .caption, .col, .colgroup, .tbody, .tfoot, .thead:
				guard self.requireOpenTableSection() else {
					self.emitError("unexpected-start-tag")
					return
				}
				self.closeTableBodyAndReprocessStartTag(tag)

			case .table:
				self.closeCurrentTableAndReprocessStartTag(tag)

			default:
				self.processStartTagUsingModeIfUnchanged(.inTable, tag)
		}
	}

	private func insertImpliedTableRowAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag) {
			self.insertTableRowElement(name: "tr", attrs: [:])
		}
	}

	private func insertTableRowElement(name: String, attrs: [String: String]) {
		self.clearStackBackToTableBodyContext()
		_ = self.insertElement(name: name, attrs: attrs)
		self.insertionMode = .inRow
	}

	private func processStartTagInRow(_ tag: StartTagToken) {
		switch tag.tagId {
			case .td, .th:
				self.insertTableCellElement(name: tag.name, attrs: tag.attrs)

			case .caption, .col, .colgroup, .tbody, .tfoot, .thead, .tr:
				guard self.hasElementInTableScope(.tr) else {
					self.emitError("unexpected-start-tag")
					return
				}
				self.closeTableRowAndReprocessStartTag(tag)

			case .table:
				self.closeCurrentTableAndReprocessStartTag(tag)

			default:
				self.processStartTagUsingModeIfUnchanged(.inTable, tag)
		}
	}

	private func insertTableCellElement(name: String, attrs: [String: String]) {
		self.clearStackBackToTableRowContext()
		_ = self.insertElement(name: name, attrs: attrs)
		self.insertionMode = .inCell
		self.insertMarker()
	}

	private func processStartTagInCell(_ tag: StartTagToken) {
		switch tag.tagId {
			case .caption, .col, .colgroup, .tbody, .td, .tfoot, .th, .thead, .tr:
				if !self.hasTableCellElementInTableScope {
					self.emitError("unexpected-start-tag")
					return
				}
				self.closeCellAndReprocessStartTag(tag)

			default:
				self.processStartTagInBody(tag)
		}
	}

	private func processStartTagInColumnGroup(_ tag: StartTagToken) {
		switch tag.tagId {
			case .html:
				self.processStartTagInBody(tag)

			case .col:
				_ = self.insertElement(name: tag.name, attrs: tag.attrs)
				self.popCurrentElement()

			case .template:
				self.processStartTagUsingRules(of: .inHead, tag, preserveTemplateMode: true)

			default:
				self.closeColumnGroupAndReprocessStartTag(tag)
		}
	}

	private func closeColumnGroupAndReprocessStartTag(_ tag: StartTagToken) {
		if self.closeColumnGroup() {
			self.processStartTag(tag)
			return
		}
		self.emitError("unexpected-start-tag")
	}

	private func processStartTagInCaption(_ tag: StartTagToken) {
		switch tag.tagId {
			case .caption, .col, .colgroup, .table, .tbody, .td, .tfoot, .th, .thead, .tr:
				self.emitError("unexpected-start-tag-implies-end-tag")
				if !self.hasElementInTableScope(.caption) {
					if tag.tagId == .table {
						self.processStartTagInBody(tag)
					}
					return
				}
				self.closeCaptionAndReprocessStartTag(tag)

			default:
				self.processStartTagInBody(tag)
		}
	}

	private func processOtherStartTagInSelect(_ tag: StartTagToken) {
		let name = tag.name
		let attrs = tag.attrs
		let selfClosing = tag.selfClosing
		let normalized = self.normalizedSelectFallbackTag(tag)

		if self.isFormattingElementTag(normalized.tagId) {
			self.insertFormattingElementInSelect(name: name, attrs: attrs)
		}
		else if normalized.tagId == .br || normalized.tagId == .img {
			self.insertVoidElementInSelect(name: name, attrs: attrs)
		}
		else if self.isSelectFallbackFormElementTag(normalized.tagId) {
			self.insertFormElementInSelect(name: name, attrs: attrs, selfClosing: selfClosing)
		}
		else if self.isSelectInTableBoundaryTag(normalized.tagId) {
			self.emitError("unexpected-start-tag-implies-end-tag")
			if !self.closeSelectOrContextForReprocessing() {
				self.closeOpenSelectAndResetInsertionMode()
			}
			self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
		}
		else {
			// Fragment parsing uses inBody mode, which allows unknown element insertion.
			self.emitError("unexpected-start-tag-in-select")
		}
	}

	private func insertFormattingElementInSelect(name: String, attrs: [String: String]) {
		self.reconstructActiveFormattingElements()
		let element = self.insertElement(name: name, attrs: attrs)
		self.pushFormattingElement(element)
	}

	private func insertVoidElementInSelect(name: String, attrs: [String: String]) {
		self.reconstructActiveFormattingElements()
		_ = self.insertElement(name: name, attrs: attrs)
		self.popCurrentElement()
	}

	private func insertFormElementInSelect(
		name: String,
		attrs: [String: String],
		selfClosing: Bool
	) {
		self.reconstructActiveFormattingElements()
		_ = self.insertElement(name: name, attrs: attrs)
		if selfClosing {
			self.popCurrentElement()
		}
	}

	private func popOpenOptionOrOptgroupForSelectInsertion() {
		if let current = currentNode, current.tagId == .option {
			self.popCurrentElement()
		}
		if let current = currentNode, current.tagId == .optgroup {
			self.popCurrentElement()
		}
	}

	private func processStartTagInBody(name: String, attrs: [String: String], selfClosing: Bool) {
		self.processStartTagInBody(StartTagToken(name: name, attrs: attrs, selfClosing: selfClosing))
	}

	private func processStartTagInBody(_ tag: StartTagToken) {
		switch tag.tagId {
			case .html:
				self.processHtmlStartTagInBody(attrs: tag.attrs)

			case .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title:
				self.processStartTagUsingRules(
					of: .inHead, tag, preserveTemplateMode: true)

			case .noscript where self.scripting:
				self.processStartTagUsingRules(
					of: .inHead, tag, preserveTemplateMode: true)

			case .body:
				self.processBodyStartTagInBody(attrs: tag.attrs)

			case .frameset:
				self.processFramesetStartTagInBody(attrs: tag.attrs)

			case .address, .article, .aside, .blockquote, .center, .details, .dialog,
			     .div, .dl, .fieldset, .figcaption, .figure, .footer, .header, .main,
			     .menu, .nav, .ol, .p, .search, .section, .summary, .ul:
				self.processBlockStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .h1, .h2, .h3, .h4, .h5, .h6:
				self.processHeadingStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .pre, .listing:
				self.processPreListingStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .form:
				self.processFormStartTagInBody(attrs: tag.attrs)

			case .li:
				self.processListItemStartTag(attrs: tag.attrs)

			case .dd, .dt:
				self.processDefinitionListItemStartTag(name: tag.name, attrs: tag.attrs)

			case .plaintext:
				self.processPlaintextStartTagInBody(attrs: tag.attrs)

			case .button:
				self.processButtonStartTag(attrs: tag.attrs)

			case .a:
				self.processAnchorStartTag(attrs: tag.attrs)

			case .nobr:
				self.processNobrStartTag(attrs: tag.attrs)

			case .b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u:
				self.insertFormattingElement(name: tag.name, attrs: tag.attrs)

			case .applet, .marquee, .object:
				self.processFormattingScopeStartTag(name: tag.name, attrs: tag.attrs)

			case .table:
				self.processTableStartTagInBody(attrs: tag.attrs)

			case .input where self.contextElement?.tagId == .select:
				self.rejectSelectContentStartTagInBody()

			case .area, .br, .embed, .img, .keygen, .wbr:
				self.processVoidStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .input:
				self.processInputStartTagInBody(attrs: tag.attrs)

			case .param, .source, .track:
				self.processMediaStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .hr:
				self.processHrStartTagInBody(attrs: tag.attrs)

			case .image:
				self.processImageStartTagInBody(attrs: tag.attrs, selfClosing: tag.selfClosing)

			case .textarea:
				self.processTextareaStartTagInBody(attrs: tag.attrs)

			case .xmp:
				self.processXmpStartTagInBody(attrs: tag.attrs)

			case .iframe:
				self.processRawtextStartTagInBody(name: tag.name, attrs: tag.attrs, framesetOk: false)

			case .select:
				self.processSelectStartTagInBody(attrs: tag.attrs)

			case .optgroup, .option:
				self.processOptionStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .rb, .rtc:
				self.processRubyBaseStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .rp, .rt:
				self.processRubyTextStartTagInBody(name: tag.name, attrs: tag.attrs)

			case .math:
				self.processForeignStartTagInBody(
					name: tag.name, namespace: .math, attrs: tag.attrs, selfClosing: tag.selfClosing)

			case .svg:
				self.processForeignStartTagInBody(
					name: tag.name, namespace: .svg, attrs: tag.attrs, selfClosing: tag.selfClosing)

			case .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr:
				self.ignoreTableStartTagInBody()

			default:
				self.processFallbackStartTagInBody(tag)
		}
	}

	private func processFallbackStartTagInBody(_ tag: StartTagToken) {
		switch tag.name {
			case "dir", "hgroup":
				self.processBlockStartTagInBody(name: tag.name, attrs: tag.attrs)
			case "noembed":
				self.processRawtextStartTagInBody(name: tag.name, attrs: tag.attrs)
			default:
				self.processGenericStartTagInBody(name: tag.name, attrs: tag.attrs)
		}
	}

	private func processHtmlStartTagInBody(attrs: [String: String]) {
		self.emitError("unexpected-start-tag")
		if self.templateInsertionModes.isEmpty {
			self.mergeAttributesOntoHtml(attrs)
		}
	}

	private func processBodyStartTagInBody(attrs: [String: String]) {
		self.emitError("unexpected-start-tag")
		guard self.templateInsertionModes.isEmpty,
		      self.openElements.count >= 2,
		      self.openElements[1].tagId == .body
		else { return }

		self.framesetOk = false
		self.mergeMissingAttributes(attrs, into: self.openElements[1])
	}

	private func processFramesetStartTagInBody(attrs: [String: String]) {
		self.emitError("unexpected-start-tag")
		guard self.openElements.count > 1,
		      self.openElements[1].tagId == .body,
		      self.framesetOk
		else { return }

		self.openElements[1].parent?.removeChild(self.openElements[1])
		while self.openElements.count > 1 {
			self.popCurrentElement()
		}
		_ = self.insertElement(name: "frameset", attrs: attrs)
		self.insertionMode = .inFrameset
	}

	private func closePElementIfInButtonScope() {
		if self.hasElementInButtonScope(.p) {
			self.closePElement()
		}
	}

	private func processBlockStartTagInBody(name: String, attrs: [String: String]) {
		_ = self.insertElementAfterClosingPInButtonScope(name: name, attrs: attrs)
	}

	private func processHeadingStartTagInBody(name: String, attrs: [String: String]) {
		self.closePElementIfInButtonScope()
		if let current = currentNode, self.isHeadingTag(current.tagId) {
			self.emitError("unexpected-start-tag")
			self.popCurrentElement()
		}
		_ = self.insertElement(name: name, attrs: attrs)
	}

	private func processPreListingStartTagInBody(name: String, attrs: [String: String]) {
		self.closePElementIfInButtonScope()
		_ = self.insertElementAndDisableFrameset(name: name, attrs: attrs)
		self.skipNextNewline = true
	}

	private func processFormStartTagInBody(attrs: [String: String]) {
		if self.formElement != nil {
			self.emitError("unexpected-start-tag")
		}
		else {
			let element = self.insertElementAfterClosingPInButtonScope(name: "form", attrs: attrs)
			self.formElement = element
		}
	}

	private func processListItemStartTag(attrs: [String: String]) {
		self.framesetOk = false
		self.closeOpenListItem()
		self.closePElementIfInButtonScope()
		_ = self.insertElement(name: "li", attrs: attrs)
	}

	private func closeOpenListItem() {
		self.closeOpenBodyListItem(
			matching: { $0.tagId == .li },
			stopAtBoundary: { self.isScopeBoundary($0, scope: .listItem) }
		)
	}

	private func closeOpenBodyListItem(
		matching shouldClose: (Node) -> Bool,
		stopAtBoundary: (Node) -> Bool
	) {
		for node in self.openElements.reversed() {
			if shouldClose(node) {
				self.generateImpliedEndTags(except: node.name)
				if self.currentNode?.tagId != node.tagId {
					self.emitError("end-tag-too-early")
				}
				self.popUntil(node.tagId)
				return
			}
			if stopAtBoundary(node) { return }
		}
	}

	private func processDefinitionListItemStartTag(name: String, attrs: [String: String]) {
		self.framesetOk = false
		self.closeOpenDefinitionListItem()
		self.closePElementIfInButtonScope()
		_ = self.insertElement(name: name, attrs: attrs)
	}

	private func closeOpenDefinitionListItem() {
		self.closeOpenBodyListItem(
			matching: { $0.tagId == .dd || $0.tagId == .dt },
			stopAtBoundary: { self.isDefinitionListItemRecoveryBoundary($0) }
		)
	}

	private func processButtonStartTag(attrs: [String: String]) {
		if self.hasElementInScope(.button) {
			self.emitError("unexpected-start-tag")
			self.generateImpliedEndTags()
			self.popUntil(.button)
		}
		self.reconstructActiveFormattingElements()
		_ = self.insertElementAndDisableFrameset(name: "button", attrs: attrs)
	}

	private func processAnchorStartTag(attrs: [String: String]) {
		if self.hasActiveFormattingEntry("a") {
			self.emitError("unexpected-start-tag")
			self.adoptionAgency(name: "a")
			self.removeFormattingElementFromActiveAndOpenElements(named: "a")
		}
		self.insertFormattingElement(name: "a", attrs: attrs)
	}

	private func processNobrStartTag(attrs: [String: String]) {
		if self.hasElementInScope(.nobr) {
			self.emitError("unexpected-start-tag-implies-end-tag")
			self.adoptionAgency(name: "nobr")
			self.removeFormattingElementFromActiveAndOpenElements(named: "nobr")
		}
		self.insertFormattingElement(name: "nobr", attrs: attrs)
	}

	private func processPlaintextStartTagInBody(attrs: [String: String]) {
		_ = self.insertElementAfterClosingPInButtonScope(name: "plaintext", attrs: attrs)
	}

	@discardableResult
	private func insertElementAfterClosingPInButtonScope(name: String, attrs: [String: String]) -> Node {
		self.closePElementIfInButtonScope()
		return self.insertElement(name: name, attrs: attrs)
	}

	private func insertFormattingElement(name: String, attrs: [String: String]) {
		let element = self.insertElementAfterReconstructingFormatting(name: name, attrs: attrs)
		self.pushFormattingElement(element)
	}

	private func removeFormattingElementFromActiveAndOpenElements(named name: String) {
		guard let i = self.activeFormattingElementIndexFromEnd(stopAtMarker: false, where: { $0.name == name }),
		      let elem = self.activeFormattingElements[i]
		else { return }
		self.activeFormattingElements.remove(at: i)
		self.removeFirstOpenElement(matching: elem)
	}

	private func processFormattingScopeStartTag(name: String, attrs: [String: String]) {
		_ = self.insertElementAfterReconstructingFormatting(name: name, attrs: attrs)
		self.insertMarker()
		self.framesetOk = false
	}

	private func processTableStartTagInBody(attrs: [String: String]) {
		// Only close p element if NOT in quirks mode
		if !self.quirksMode, self.hasElementInButtonScope(.p) {
			self.closePElement()
		}
		_ = self.insertElementAndDisableFrameset(name: "table", attrs: attrs)
		self.insertionMode = .inTable
	}

	private func rejectSelectContentStartTagInBody() {
		self.emitError("unexpected-start-tag-in-select")
	}

	private func processVoidStartTagInBody(name: String, attrs: [String: String]) {
		self.reconstructActiveFormattingElements()
		self.insertElementAndPop(name: name, attrs: attrs)
		self.framesetOk = false
	}

	private func processInputStartTagInBody(attrs: [String: String]) {
		self.reconstructActiveFormattingElements()
		self.insertElementAndPop(name: "input", attrs: attrs)
		if !self.isHiddenInput(attrs) {
			self.framesetOk = false
		}
	}

	private func isHiddenInput(_ attrs: [String: String]) -> Bool {
		guard let type = self.attributeValue(in: attrs, matchingLowercaseName: "type") else {
			return false
		}

		return type.asciiCaseInsensitiveEquals("hidden")
	}

	private func processMediaStartTagInBody(name: String, attrs: [String: String]) {
		self.insertElementAndPop(name: name, attrs: attrs)
	}

	private func processHrStartTagInBody(attrs: [String: String]) {
		self.closePElementIfInButtonScope()
		self.insertElementAndPop(name: "hr", attrs: attrs)
		self.framesetOk = false
	}

	private func processImageStartTagInBody(attrs: [String: String], selfClosing: Bool) {
		self.emitError("unexpected-start-tag")
		self.processStartTag(name: "img", attrs: attrs, selfClosing: selfClosing)
	}

	private func processTextareaStartTagInBody(attrs: [String: String]) {
		self.insertElementAndSwitchToTextMode(name: "textarea", attrs: attrs)
		self.skipNextNewline = true // Ignore first newline after textarea
		self.framesetOk = false
	}

	private func processXmpStartTagInBody(attrs: [String: String]) {
		self.closePElementIfInButtonScope()
		self.reconstructActiveFormattingElements()
		self.framesetOk = false
		self.insertElementAndSwitchToTextMode(name: "xmp", attrs: attrs)
	}

	private func processRawtextStartTagInBody(name: String, attrs: [String: String], framesetOk: Bool? = nil) {
		if let framesetOk {
			self.framesetOk = framesetOk
		}
		self.insertElementAndSwitchToTextMode(name: name, attrs: attrs)
	}

	private func processSelectStartTagInBody(attrs: [String: String]) {
		_ = self.insertElementAfterReconstructingFormatting(name: "select", attrs: attrs)
		// Insert marker to prevent reconstruction of formatting elements from outside select
		self.insertMarker()
		self.framesetOk = false
		if self.isTableInsertionMode {
			self.insertionMode = .inSelectInTable
		}
		else {
			self.insertionMode = .inSelect
		}
	}

	private var isTableInsertionMode: Bool {
		self.insertionMode == .inTable
			|| self.insertionMode == .inTableBody
			|| self.insertionMode == .inRow
			|| self.insertionMode == .inCell
			|| self.insertionMode == .inCaption
	}

	private func processOptionStartTagInBody(name: String, attrs: [String: String]) {
		if self.currentNode?.tagId == .option {
			self.popCurrentElement()
		}
		_ = self.insertElementAfterReconstructingFormatting(name: name, attrs: attrs)
	}

	private func processRubyBaseStartTagInBody(name: String, attrs: [String: String]) {
		self.processRubyScopedStartTagInBody(name: name, attrs: attrs)
	}

	private func processRubyTextStartTagInBody(name: String, attrs: [String: String]) {
		self.processRubyScopedStartTagInBody(name: name, attrs: attrs, impliedEndTagException: "rtc")
	}

	private func processRubyScopedStartTagInBody(
		name: String,
		attrs: [String: String],
		impliedEndTagException: String? = nil
	) {
		if self.hasElementInScope(.ruby) {
			self.generateImpliedEndTags(except: impliedEndTagException)
		}
		_ = self.insertElement(name: name, attrs: attrs)
	}

	private func processForeignStartTagInBody(
		name: String,
		namespace: Namespace,
		attrs: [String: String],
		selfClosing: Bool
	) {
		self.reconstructActiveFormattingElements()
		self.insertForeignElement(name: name, namespace: namespace, attrs: attrs, selfClosing: selfClosing)
	}

	@discardableResult
	private func insertForeignElement(
		name: String,
		namespace: Namespace,
		attrs: [String: String],
		selfClosing: Bool
	) -> Node {
		let adjustedAttrs = self.adjustForeignAttributes(attrs, namespace: namespace)
		let element = self.insertElement(name: name, namespace: namespace, attrs: adjustedAttrs)
		if selfClosing {
			self.popCurrentElement()
		}
		return element
	}

	private func ignoreTableStartTagInBody() {
		self.emitError("unexpected-start-tag")
	}

	private func processGenericStartTagInBody(name: String, attrs: [String: String]) {
		_ = self.insertElementAfterReconstructingFormatting(name: name, attrs: attrs)
	}

	@discardableResult
	private func insertElementAfterReconstructingFormatting(name: String, attrs: [String: String]) -> Node {
		self.reconstructActiveFormattingElements()
		return self.insertElement(name: name, attrs: attrs)
	}

	private func insertElementAndPop(name: String, attrs: [String: String]) {
		_ = self.insertElement(name: name, attrs: attrs)
		self.popCurrentElement()
	}

	private func insertElementAndDisableFrameset(name: String, attrs: [String: String]) -> Node {
		let element = self.insertElement(name: name, attrs: attrs)
		self.framesetOk = false
		return element
	}

	private func processEndTag(name: String) {
		self.processEndTag(EndTagToken(name: name))
	}

	private func processEndTag(_ tag: EndTagToken) {
		let name = tag.name

		// Flush pending table character tokens before processing any non-character token
		self.flushPendingTableCharacterTokens()

		// Check for foreign content processing
		// Per WHATWG spec: use foreign content rules only when adjusted current node
		// is in MathML/SVG namespace. Unlike start tags, there are no integration point
		// exceptions for end tags - they're handled within processForeignContentEndTag.
		if let node = adjustedCurrentNode, let ns = node.namespace, ns == .svg || ns == .math {
			if self.processForeignContentEndTag(name: name) {
				return // Handled by foreign content rules
			}
			// Fall through to normal processing if not handled
		}

		switch self.insertionMode {
			case .initial:
				// Parse error - end tag in initial mode sets quirks mode
				self.emitError("expected-doctype-but-got-end-tag")
				self.quirksMode = true
				self.insertionMode = .beforeHtml
				self.processEndTag(tag)

			case .beforeHtml:
				self.processEndTagBeforeHtml(tag)

			case .beforeHead:
				self.processEndTagBeforeHead(tag)

			case .inHead:
				self.processEndTagInHead(tag)

			case .inHeadNoscript:
				self.processEndTagInHeadNoscript(tag)

			case .afterHead:
				self.processEndTagAfterHead(tag)

			case .inBody:
				self.processEndTagInBody(tag)

			case .text:
				self.processEndTagInText()

			case .afterBody:
				self.processEndTagAfterBody(name: name)

			case .afterAfterBody:
				self.reprocessUnexpectedEndTagAfterBody(name: name)

			case .inCell:
				self.processEndTagInCell(tag)

			case .inRow:
				self.processEndTagInRow(tag)

			case .inTableBody:
				self.processEndTagInTableBody(tag)

			case .inColumnGroup:
				self.processEndTagInColumnGroup(tag)

			case .inTable:
				self.processEndTagInTable(tag)

			case .inCaption:
				self.processEndTagInCaption(tag)

			case .inFrameset:
				self.processEndTagInFrameset(name: name)

			case .afterFrameset:
				self.processEndTagAfterFrameset(name: name)

			case .afterAfterFrameset:
				self.emitError("unexpected-end-tag-after-frameset")

			case .inTemplate:
				self.processEndTagInTemplate(tag)

			case .inSelect:
				self.processEndTagInSelect(tag)

			case .inSelectInTable:
				self.processEndTagInSelectInTable(tag)

			default:
				self.processEndTagInBody(tag)
		}
	}

	private func processEndTagInText() {
		self.popCurrentElement()
		self.insertionMode = self.originalInsertionMode
	}

	private func processEndTagBeforeHtml(_ tag: EndTagToken) {
		switch tag.tagId {
			case .head, .body, .html, .br:
				self.insertHtmlElement()
				self.insertionMode = .beforeHead
				self.processEndTag(tag)
			default:
				self.emitError("unexpected-end-tag")
		}
	}

	private func processEndTagBeforeHead(_ tag: EndTagToken) {
		switch tag.tagId {
			case .head, .body, .html, .br:
				self.insertHeadElement()
				self.insertionMode = .inHead
				self.processEndTag(tag)
			default:
				self.emitError("unexpected-end-tag")
		}
	}

	private func processEndTagInHead(_ tag: EndTagToken) {
		switch tag.tagId {
			case .head:
				self.popCurrentElement()
				self.insertionMode = .afterHead

			case .body, .html, .br:
				self.popCurrentElement()
				self.insertionMode = .afterHead
				self.processEndTag(tag)

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.emitError("unexpected-end-tag")
		}
	}

	private func processEndTagInHeadNoscript(_ tag: EndTagToken) {
		switch tag.tagId {
			case .noscript:
				self.popCurrentElement()
				self.insertionMode = .inHead

			case .br:
				self.emitError("unexpected-end-tag")
				self.popCurrentElement()
				self.insertionMode = .inHead
				self.processEndTag(tag)

			default:
				self.emitError("unexpected-end-tag")
		}
	}

	private func processEndTagAfterHead(_ tag: EndTagToken) {
		switch tag.tagId {
			case .body, .html, .br:
				self.insertBodyElement()
				self.insertionMode = .inBody
				self.processEndTag(tag)

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.emitError("unexpected-end-tag")
		}
	}

	private func processEndTagAfterBody(name: String) {
		if name == "html" {
			self.insertionMode = .afterAfterBody
		}
		else {
			self.reprocessUnexpectedEndTagAfterBody(name: name)
		}
	}

	private func reprocessUnexpectedEndTagAfterBody(name: String) {
		self.emitError("unexpected-end-tag-after-body")
		self.insertionMode = .inBody
		self.processEndTag(name: name)
	}

	private func processEndTagInFrameset(name: String) {
		if name == "frameset" {
			if self.currentNode?.tagId == .html {
				self.emitError("unexpected-end-tag")
				return
			}
			self.popCurrentElement()
			if self.currentNode?.tagId != .frameset {
				self.insertionMode = .afterFrameset
			}
		}
		else {
			self.emitError("unexpected-end-tag-in-frameset")
		}
	}

	private func processEndTagAfterFrameset(name: String) {
		if name == "html" {
			self.insertionMode = .afterAfterFrameset
		}
		else {
			self.emitError("unexpected-end-tag-after-frameset")
		}
	}

	private func processEndTagInSelectInTable(_ tag: EndTagToken) {
		switch tag.tagId {
			case .caption, .table, .tbody, .tfoot, .thead, .tr, .td, .th:
				self.emitError("unexpected-end-tag-in-select")
				if !self.hasElementInTableScope(tag.name) {
					return
				}
				self.closeOpenSelectAndResetInsertionMode()
				self.processEndTag(tag)

			default:
				self.processEndTagUsingModeIfUnchanged(.inSelect, name: tag.name)
		}
	}

	private func processEndTagInSelect(_ tag: EndTagToken) {
		switch tag.tagId {
			case .optgroup:
				self.closeCurrentOptgroupInSelect()

			case .option:
				self.closeCurrentOptionInSelect()

			case .select:
				if !self.hasElementInSelectScope(.select) {
					self.emitError("unexpected-end-tag")
					return
				}
				self.popUntil(.select)
				self.clearActiveFormattingElementsToLastMarker()
				self.resetInsertionMode()

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.processOtherEndTagInSelect(tag)
		}
	}

	private func closeCurrentOptgroupInSelect() {
		if self.currentNodeHasTagId(.option), self.previousOpenElementHasTagId(.optgroup) {
			self.popCurrentElement()
		}
		self.closeCurrentElement(.optgroup)
	}

	private func closeCurrentOptionInSelect() {
		self.closeCurrentElement(.option)
	}

	private func closeCurrentElement(_ tagId: TagID) {
		if self.currentNodeHasTagId(tagId) {
			self.popCurrentElement()
		}
		else {
			self.emitError("unexpected-end-tag")
		}
	}

	private func currentNodeHasTagId(_ tagId: TagID) -> Bool {
		self.currentNode?.tagId == tagId
	}

	private func previousOpenElementHasTagId(_ tagId: TagID) -> Bool {
		self.openElements.count >= 2 && self.openElements[self.openElements.count - 2].tagId == tagId
	}

	private func processOtherEndTagInSelect(_ tag: EndTagToken) {
		let normalized = self.normalizedSelectFallbackTag(tag)

		if self.isFormattingElementTag(normalized.tagId) {
			self.adoptionAgency(name: tag.name, tagId: normalized.tagId)
		}
		else if self.isSelectFallbackFormElementTag(normalized.tagId) {
			self.closeElementIfAfterSelectBoundary(normalized.name)
		}
		else {
			self.emitError("unexpected-end-tag")
		}
	}

	private func normalizedSelectFallbackTag(_ tag: StartTagToken) -> (name: String, tagId: TagID) {
		self.normalizedSelectFallbackTag(name: tag.name, tagId: tag.tagId)
	}

	private func normalizedSelectFallbackTag(_ tag: EndTagToken) -> (name: String, tagId: TagID) {
		self.normalizedSelectFallbackTag(name: tag.name, tagId: tag.tagId)
	}

	private func normalizedSelectFallbackTag(name: String, tagId: TagID) -> (name: String, tagId: TagID) {
		if tagId != .unknown {
			return (name, tagId)
		}
		let normalizedName = self.normalizedFallbackTagName(name)
		return (normalizedName, TagID.from(normalizedName))
	}

	private func normalizedFallbackTagName(_ name: String) -> String {
		return self.lowercaseIfNeeded(name)
	}

	private func closeElementIfAfterSelectBoundary(_ name: String) {
		guard self.elementIsAfterSelectBoundary(name) else {
			self.emitError("unexpected-end-tag")
			return
		}

		self.popUntilElementNamedAnyNamespace(name)
	}

	private func elementIsAfterSelectBoundary(_ name: String) -> Bool {
		var sawTargetBeforeSelect = false
		var sawSelect = false
		for node in self.openElements {
			if node.name == name {
				if sawSelect {
					return true
				}
				sawTargetBeforeSelect = true
			}
			if node.tagId == .select, !sawSelect {
				sawSelect = true
			}
		}
		return sawTargetBeforeSelect && !sawSelect
	}

	private func processEndTagInTable(_ tag: EndTagToken) {
		switch tag.tagId {
			case .table:
				guard self.requireElementInTableScope(.table) else { return }
				self.closeCurrentTable()

			case .body, .caption, .col, .colgroup, .html, .tbody,
			     .td, .tfoot, .th, .thead, .tr:
				self.emitError("unexpected-end-tag")

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.emitError("unexpected-end-tag")
				self.processEndTagInBodyWithFosterParenting(tag)
		}
	}

	private func closeCurrentTable() {
		self.popUntil(.table)
		self.resetInsertionMode()
	}

	private func processEndTagInCell(_ tag: EndTagToken) {
		switch tag.tagId {
			case .td, .th:
				guard self.requireElementInTableScope(tag.name) else { return }
				self.closeExplicitTableCellEndTag(tag.name)

			case .body, .caption, .col, .colgroup, .html:
				self.emitError("unexpected-end-tag")

			case .table, .tbody, .tfoot, .thead, .tr:
				guard self.requireElementInTableScope(tag.name) else { return }
				self.closeCell()
				self.processEndTag(tag)

			default:
				self.processEndTagInBody(tag)
		}
	}

	private func closeExplicitTableCellEndTag(_ name: String) {
		self.generateImpliedEndTags()
		if self.currentNode?.name != name {
			self.emitError("end-tag-too-early")
		}
		self.popUntil(name)
		self.clearActiveFormattingElementsToLastMarker()
		self.insertionMode = .inRow
	}

	private func processEndTagInRow(_ tag: EndTagToken) {
		switch tag.tagId {
			case .tr:
				guard self.requireElementInTableScope(.tr) else { return }
				self.closeTableRow()

			case .table:
				guard self.requireElementInTableScope(.tr) else { return }
				self.closeTableRowAndReprocessEndTag(tag)

			case .tbody, .tfoot, .thead:
				guard self.requireElementInTableScope(tag.name) else { return }
				if !self.hasElementInTableScope(.tr) {
					return
				}
				self.closeTableRowAndReprocessEndTag(tag)

			case .body, .caption, .col, .colgroup, .html, .td, .th:
				self.emitError("unexpected-end-tag")

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.processEndTagUsingModeIfUnchanged(.inTable, name: tag.name)
		}
	}

	private func closeTableRow() {
		self.clearStackBackToTableRowContext()
		self.popCurrentElement()
		self.insertionMode = .inTableBody
	}

	private func closeTableRowAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag, after: self.closeTableRow)
	}

	private func closeTableRowAndReprocessEndTag(_ tag: EndTagToken) {
		self.reprocessEndTag(tag, after: self.closeTableRow)
	}

	private func processEndTagInTableBody(_ tag: EndTagToken) {
		switch tag.tagId {
			case .tbody, .tfoot, .thead:
				guard self.requireElementInTableScope(tag.name) else { return }
				self.closeTableBody()

			case .table:
				guard self.requireOpenTableSection() else {
					self.emitError("unexpected-end-tag")
					return
				}
				self.closeTableBodyAndReprocessEndTag(tag)

			case .body, .caption, .col, .colgroup, .html, .td, .th, .tr:
				self.emitError("unexpected-end-tag")

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.processEndTagUsingModeIfUnchanged(.inTable, name: tag.name)
		}
	}

	private func closeTableBody() {
		self.clearStackBackToTableBodyContext()
		self.popCurrentElement()
		self.insertionMode = .inTable
	}

	private func closeTableBodyAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag, after: self.closeTableBody)
	}

	private func closeTableBodyAndReprocessEndTag(_ tag: EndTagToken) {
		self.reprocessEndTag(tag, after: self.closeTableBody)
	}

	private func requireOpenTableSection() -> Bool {
		self.hasTableSectionElementInTableScope
	}

	private func processEndTagInColumnGroup(_ tag: EndTagToken) {
		switch tag.tagId {
			case .colgroup:
				if !self.closeColumnGroup() {
					self.emitError("unexpected-end-tag")
				}

			case .col:
				self.emitError("unexpected-end-tag")

			case .template:
				self.processEndTagInBody(tag)

			default:
				self.closeColumnGroupAndReprocessEndTag(tag)
		}
	}

	private func closeColumnGroupAndReprocessEndTag(_ tag: EndTagToken) {
		if self.closeColumnGroup() {
			self.processEndTag(tag)
			return
		}
		self.emitError("unexpected-end-tag")
	}

	private func closeColumnGroup() -> Bool {
		guard self.currentNode?.tagId == .colgroup else {
			return false
		}
		self.popCurrentElement()
		self.insertionMode = .inTable
		return true
	}

	private func processEndTagInCaption(_ tag: EndTagToken) {
		switch tag.tagId {
			case .caption:
				guard self.requireElementInTableScope(.caption) else { return }
				self.closeCaption()

			case .table:
				guard self.requireElementInTableScope(.caption) else { return }
				self.closeCaptionAndReprocessEndTag(tag)

			case .body, .col, .colgroup, .html, .tbody, .td, .tfoot, .th, .thead, .tr:
				self.emitError("unexpected-end-tag")

			default:
				self.processEndTagInBody(tag)
		}
	}

	private func closeCaption() {
		self.generateImpliedEndTags()
		if self.currentNode?.tagId != .caption {
			self.emitError("end-tag-too-early")
		}
		self.popUntil(.caption)
		self.clearActiveFormattingElementsToLastMarker()
		self.insertionMode = .inTable
	}

	private func closeCaptionAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag, after: self.closeCaption)
	}

	private func closeCaptionAndReprocessEndTag(_ tag: EndTagToken) {
		self.reprocessEndTag(tag, after: self.closeCaption)
	}

	private func requireElementInTableScope(_ name: String) -> Bool {
		if self.hasElementInTableScope(name) {
			return true
		}
		self.emitError("unexpected-end-tag")
		return false
	}

	private func requireElementInTableScope(_ tagId: TagID) -> Bool {
		if self.hasElementInTableScope(tagId) {
			return true
		}
		self.emitError("unexpected-end-tag")
		return false
	}

	private func processEndTagInTemplate(_ tag: EndTagToken) {
		switch tag.tagId {
			case .template:
				self.processEndTagInBody(tag)
			default:
				self.emitError("unexpected-end-tag-in-template")
		}
	}

	private func processEndTagInBody(_ tag: EndTagToken) {
		switch tag.tagId {
			case .body:
				self.processBodyEndTagInBody()

			case .html:
				self.processHtmlEndTagInBody()

			case .address, .article, .aside, .blockquote, .button, .center,
			     .details, .dialog, .div, .dl, .fieldset, .figcaption,
			     .figure, .footer, .header, .listing, .main, .menu, .nav,
			     .ol, .pre, .search, .section, .summary, .ul:
				self.processBlockStructureEndTagInBody(tag)

			case .form:
				self.processFormEndTagInBody()

			case .p:
				self.processPEndTagInBody()

			case .li:
				self.processListItemEndTagInBody()

			case .dd, .dt:
				self.processDefinitionListItemEndTagInBody(tag)

			case .h1, .h2, .h3, .h4, .h5, .h6:
				self.processHeadingEndTagInBody(tag)

			case .a, .b, .big, .code, .em, .font, .i, .nobr,
			     .s, .small, .strike, .strong, .tt, .u:
				self.adoptionAgency(tag)

			case .applet, .marquee, .object:
				self.processFormattingScopeEndTagInBody(tag)

			case .br:
				self.processBrEndTagInBody()

			case .template:
				self.processTemplateEndTagInBody()

			default:
				self.processFallbackEndTagInBody(tag)
		}
	}

	private func processFallbackEndTagInBody(_ tag: EndTagToken) {
		switch tag.name {
			case "dir", "hgroup":
				self.processBlockStructureEndTagInBody(tag)

			default:
				self.anyOtherEndTag(name: tag.name)
		}
	}

	private func processBodyEndTagInBody() {
		if !self.hasElementInScope(.body) {
			self.emitError("unexpected-end-tag")
			return
		}
		self.insertionMode = .afterBody
	}

	private func processHtmlEndTagInBody() {
		if !self.hasElementInScope(.body) {
			self.emitError("unexpected-end-tag")
			return
		}
		self.insertionMode = .afterBody
		self.processEndTag(name: "html")
	}

	private func processBlockStructureEndTagInBody(_ tag: EndTagToken) {
		if tag.tagId == .unknown {
			self.closeScopedElementInBody(tag.name)
		}
		else {
			self.closeScopedElementInBody(tag.tagId)
		}
	}

	private func processFormEndTagInBody() {
		let node = self.formElement
		self.formElement = nil
		if node == nil || !self.hasElementInScope(.form) {
			self.emitError("unexpected-end-tag")
			return
		}
		self.closeFormElement(node)
	}

	private func closeFormElement(_ node: Node?) {
		self.generateImpliedEndTags()
		if self.currentNode !== node {
			self.emitError("end-tag-too-early")
		}
		if let node = node {
			self.removeFirstOpenElement(matching: node)
		}
	}

	private func processPEndTagInBody() {
		if !self.hasElementInButtonScope(.p) {
			self.emitError("unexpected-end-tag")
			_ = self.insertElement(name: "p", attrs: [:])
		}
		self.closePElement()
	}

	private func processListItemEndTagInBody() {
		if !self.hasElementInListItemScope(.li) {
			self.emitError("unexpected-end-tag")
			return
		}
		self.closeListItemElement()
	}

	private func processDefinitionListItemEndTagInBody(_ tag: EndTagToken) {
		self.closeScopedElementInBody(tag.tagId, impliedEndTagException: tag.name)
	}

	private func processHeadingEndTagInBody(_ tag: EndTagToken) {
		if !self.hasAnyHeadingElementInScope {
			self.emitError("unexpected-end-tag")
			return
		}
		self.closeHeadingElement(tag)
	}

	private var hasAnyHeadingElementInScope: Bool {
		self.hasHeadingElementInScope
	}

	private func closeListItemElement() {
		self.closeInBodyAfterImpliedEndTags(
			impliedEndTagException: "li",
			isExpectedCurrent: { $0.tagId == .li },
			popTarget: { self.popUntil(.li) }
		)
	}

	private func closeHeadingElement(_ tag: EndTagToken) {
		self.closeInBodyAfterImpliedEndTags(
			isExpectedCurrent: { $0.tagId == tag.tagId },
			popTarget: { self.popUntilElementAnyNamespace { self.isHeadingTag($0.tagId) } }
		)
	}

	private func processFormattingScopeEndTagInBody(_ tag: EndTagToken) {
		self.closeScopedElementInBody(
			tag.tagId, clearFormattingToLastMarker: true)
	}

	private func closeScopedElementInBody(
		_ name: String,
		impliedEndTagException: String? = nil,
		clearFormattingToLastMarker: Bool = false
	) {
		if !self.hasElementInScope(name) {
			self.emitError("unexpected-end-tag")
			return
		}
		self.closeInBodyAfterImpliedEndTags(
			impliedEndTagException: impliedEndTagException,
			isExpectedCurrent: { $0.name == name },
			popTarget: { self.popUntil(name) }
		)
		if clearFormattingToLastMarker {
			self.clearActiveFormattingElementsToLastMarker()
		}
	}

	private func closeScopedElementInBody(
		_ tagId: TagID,
		impliedEndTagException: String? = nil,
		clearFormattingToLastMarker: Bool = false
	) {
		if !self.hasElementInScope(tagId) {
			self.emitError("unexpected-end-tag")
			return
		}
		self.closeInBodyAfterImpliedEndTags(
			impliedEndTagException: impliedEndTagException,
			isExpectedCurrent: { $0.tagId == tagId },
			popTarget: { self.popUntil(tagId) }
		)
		if clearFormattingToLastMarker {
			self.clearActiveFormattingElementsToLastMarker()
		}
	}

	private func closeInBodyAfterImpliedEndTags(
		impliedEndTagException: String? = nil,
		isExpectedCurrent: (Node) -> Bool,
		popTarget: () -> Void
	) {
		self.generateImpliedEndTags(except: impliedEndTagException)
		guard let currentNode = self.currentNode, isExpectedCurrent(currentNode) else {
			self.emitError("end-tag-too-early")
			popTarget()
			return
		}
		popTarget()
	}

	private func processBrEndTagInBody() {
		self.emitError("unexpected-end-tag")
		self.processVoidStartTagInBody(name: "br", attrs: [:])
	}

	private func processTemplateEndTagInBody() {
		// Per spec: check if template is on the stack of open elements (not in scope!)
		// Only match HTML namespace templates, not SVG/MathML ones
		if !self.hasHTMLTemplateOnOpenElementStack() {
			self.emitError("unexpected-end-tag")
			return
		}
		self.closeHTMLTemplateElement()
	}

	private func closeHTMLTemplateElement() {
		self.generateImpliedEndTags()
		if self.currentNode?.tagId != .template {
			self.emitError("end-tag-too-early")
		}
		self.popUntilHTMLTemplate()
		self.finishTemplateClose()
	}

	private func hasTemplateOnOpenElementStack(htmlNamespaceOnly: Bool) -> Bool {
		htmlNamespaceOnly ? self.hasHTMLTemplateOnOpenElementStack() : self.hasTemplateTagOnOpenElementStack()
	}

	private func hasHTMLTemplateOnOpenElementStack() -> Bool {
		self.hasOpenHTMLElement(.template)
	}

	private func hasTemplateTagOnOpenElementStack() -> Bool {
		self.hasOpenElement(.template)
	}

	private func popUntilHTMLTemplate() {
		self.popUntilElementAnyNamespace { self.isHTMLTemplateElement($0) }
	}

	private func isHTMLTemplateElement(_ node: Node) -> Bool {
		node.tagId == .template && self.isHTMLNamespace(node)
	}

	private func anyOtherEndTag(name: String) {
		switch self.findOtherEndTagStackMatch(named: name) {
			case .match(let index):
				self.closeMatchingOtherEndTag(named: name, at: index)
			case .blockedBySpecialElement:
				self.emitError("unexpected-end-tag")
			case .noMatch:
				break
		}
	}

	private func findOtherEndTagStackMatch(named name: String) -> OtherEndTagStackSearchResult {
		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let node = self.openElements[i]
			if node.name == name {
				return .match(i)
			}
			if self.isSpecialElement(node) {
				return .blockedBySpecialElement
			}
		}
		return .noMatch
	}

	private func closeMatchingOtherEndTag(named name: String, at stackIndex: Int) {
		self.generateImpliedEndTags(except: name)
		if self.currentNode?.name != name {
			self.emitError("end-tag-too-early")
		}
		self.popOpenElementsThroughIndex(stackIndex)
	}

	private func processComment(_ text: String) {
		self.flushPendingTableCharacterTokens()
		let comment = Node.comment(text)

		switch self.insertionMode {
			case .initial, .beforeHtml:
				self.document.appendChild(comment)

			case .afterBody:
				// In afterBody mode, append to the html element (first on stack)
				if let html = openElements.first {
					html.appendChild(comment)
				}
				else {
					self.document.appendChild(comment)
				}

			case .afterAfterBody, .afterAfterFrameset:
				// In fragment parsing, append to html element; otherwise to document
				if self.fragmentContext != nil, let html = openElements.first {
					html.appendChild(comment)
				}
				else {
					self.document.appendChild(comment)
				}

			default:
				// Use adjustedInsertionTarget to properly handle template content
				self.adjustedInsertionTarget.appendChild(comment)
		}
	}

	private func processDoctype(_ doctype: Doctype) {
		self.flushPendingTableCharacterTokens()
		if self.insertionMode != .initial {
			self.emitError("unexpected-doctype")
			return
		}

		let node = Node.doctype(doctype)
		self.document.appendChild(node)

		// Determine quirks mode based on doctype
		// Quirks mode if:
		// 1. Force-quirks flag is set
		// 2. Name is not "html"
		// 3. PUBLIC identifier exists and matches certain patterns
		// 4. SYSTEM identifier exists without PUBLIC identifier
		// 5. SYSTEM identifier is certain legacy values
		// BUT: iframeSrcdoc mode always forces no-quirks (after force_quirks check)
		if doctype.forceQuirks {
			self.quirksMode = true
		}
		else if self.iframeSrcdoc {
			// iframe srcdoc content is always in no-quirks mode per WHATWG spec
			self.quirksMode = false
		}
		else if !self.isHTMLDoctypeName(doctype.name) {
			self.quirksMode = true
		}
		else if let publicId = doctype.publicId {
			// Has PUBLIC identifier - check for known quirks-triggering patterns
			// Many legacy PUBLIC identifiers trigger quirks mode.
			if self.isQuirksPublicIdentifier(publicId) {
				self.quirksMode = true
			}
			else if publicId.asciiCaseInsensitiveHasPrefix("-//w3c//dtd html 4.01"),
			        doctype.systemId == nil
			{
				// HTML 4.01 without system identifier is quirks
				self.quirksMode = true
			}
		}
		else if doctype.systemId != nil, doctype.publicId == nil {
			// SYSTEM identifier without PUBLIC identifier triggers quirks mode
			self.quirksMode = true
		}

		self.insertionMode = .beforeHtml
	}

	private func isHTMLDoctypeName(_ name: String?) -> Bool {
		guard let name else { return false }
		return name.asciiCaseInsensitiveEquals("html")
	}

	private func isQuirksPublicIdentifier(_ publicId: String) -> Bool {
		kQuirksPublicIdPrefixes.contains { publicId.asciiCaseInsensitiveHasPrefix($0) }
	}

	private func processEOF() {
		while true {
			self.flushPendingTableCharacterTokens()
			// Generate implied end tags and finish
			switch self.insertionMode {
				case .initial:
					self.insertionMode = .beforeHtml

				case .beforeHtml:
					self.insertHtmlElement()
					self.insertionMode = .beforeHead

				case .beforeHead:
					self.insertHeadElement()
					self.insertionMode = .inHead

				case .inHead:
					self.popCurrentElement()
					self.insertionMode = .afterHead

				case .inHeadNoscript:
					self.emitError("eof-in-noscript")
					self.popCurrentElement() // noscript
					self.insertionMode = .inHead

				case .afterHead:
					self.insertBodyElement()
					self.insertionMode = .inBody

				case .text:
					self.processTextModeEOF()

				case .inTable, .inTableBody, .inRow, .inCell, .inCaption, .inColumnGroup:
					self.processTableContextEOF()

				case .inTemplate:
					if !self.closeTemplateAtEOF() {
						return
					}

				case .inBody, .inSelect, .inSelectInTable, .inFrameset, .afterBody, .afterFrameset,
				     .afterAfterBody, .afterAfterFrameset, .inTableText:
					if !self.reprocessEOFUsingTemplateModeIfNeeded() {
						return
					}
			}
		}
	}

	private func processTextModeEOF() {
		self.emitError("eof-in-script-html-comment-like-text")
		self.popCurrentElement()
		self.insertionMode = self.originalInsertionMode
	}

	private func processTableContextEOF() {
		self.emitError("eof-in-table")
		self.insertionMode = .inBody
	}

	private func reprocessEOFUsingTemplateModeIfNeeded() -> Bool {
		guard !self.templateInsertionModes.isEmpty else {
			return false
		}
		self.insertionMode = .inTemplate
		return true
	}

	private func closeTemplateAtEOF() -> Bool {
		// Check the open stack directly. Table scopes can hide templates from normal scope checks.
		guard self.hasTemplateOnOpenElementStack(htmlNamespaceOnly: false) else {
			return false
		}
		self.emitError("eof-in-template")
		self.popUntilElementAnyNamespace { $0.tagId == .template }
		self.finishTemplateClose()
		return true
	}

	private func finishTemplateClose() {
		self.clearActiveFormattingElementsToLastMarker()
		if !self.templateInsertionModes.isEmpty {
			self.templateInsertionModes.removeLast()
		}
		self.resetInsertionMode()
	}

	// MARK: - Element Insertion

	@inline(__always)
	private var currentNode: Node? {
		self.openElements.last
	}

	private func mergeAttributesOntoHtml(_ attrs: [String: String]) {
		guard let html = self.openElements.first else { return }

		self.mergeMissingAttributes(attrs, into: html)
	}

	private func mergeMissingAttributes(_ attrs: [String: String], into element: Node) {
		for (key, value) in attrs where element.attrs[key] == nil {
			element.attrs[key] = value
		}
	}

	@inline(__always)
	private var isSelectContextOnly: Bool {
		self.contextElement?.tagId == .select && !self.hasOpenElement(.select)
	}

	private func processStartTagUsingRules(
		of mode: InsertionMode,
		_ tag: StartTagToken,
		preserveTemplateMode: Bool = false
	) {
		let savedMode = self.insertionMode
		self.insertionMode = mode
		self.processStartTag(tag)

		if self.insertionMode == .text {
			self.originalInsertionMode = savedMode
		}
		else if !(preserveTemplateMode && self.insertionMode == .inTemplate) {
			self.insertionMode = savedMode
		}
	}

	private func processStartTagUsingModeIfUnchanged(
		_ mode: InsertionMode,
		name: String,
		attrs: [String: String],
		selfClosing: Bool
	) {
		self.processStartTagUsingModeIfUnchanged(
			mode, StartTagToken(name: name, attrs: attrs, selfClosing: selfClosing))
	}

	private func processStartTagUsingModeIfUnchanged(_ mode: InsertionMode, _ tag: StartTagToken) {
		self.processUsingModeIfUnchanged(mode) {
			self.processStartTag(tag)
		}
	}

	private func processEndTagUsingModeIfUnchanged(_ mode: InsertionMode, name: String) {
		self.processUsingModeIfUnchanged(mode) {
			self.processEndTag(name: name)
		}
	}

	private func processUsingModeIfUnchanged(_ mode: InsertionMode, _ body: () -> Void) {
		let savedMode = self.insertionMode
		self.insertionMode = mode
		body()
		if self.insertionMode == mode {
			self.insertionMode = savedMode
		}
	}

	private func replaceTemplateInsertionModeAndReprocessStartTag(
		_ mode: InsertionMode,
		_ tag: StartTagToken
	) {
		if !self.templateInsertionModes.isEmpty {
			self.templateInsertionModes.removeLast()
		}
		self.templateInsertionModes.append(mode)
		self.insertionMode = mode
		self.processStartTag(tag)
	}

	private func processStartTagInBodyWithFosterParenting(
		name: String,
		attrs: [String: String],
		selfClosing: Bool
	) {
		self.processStartTagInBodyWithFosterParenting(
			StartTagToken(name: name, attrs: attrs, selfClosing: selfClosing))
	}

	private func processStartTagInBodyWithFosterParenting(_ tag: StartTagToken) {
		self.withFosterParenting {
			self.processStartTagInBody(tag)
		}
	}

	private func processEndTagInBodyWithFosterParenting(name: String) {
		self.processEndTagInBodyWithFosterParenting(EndTagToken(name: name))
	}

	private func processEndTagInBodyWithFosterParenting(_ tag: EndTagToken) {
		self.withFosterParenting {
			self.processEndTagInBody(tag)
		}
	}

	private func withFosterParenting(_ body: () -> Void) {
		let wasEnabled = self.fosterParentingEnabled
		self.fosterParentingEnabled = true
		body()
		self.fosterParentingEnabled = wasEnabled
	}

	/// Leaves a virtual select fragment context before reprocessing the current token in body mode.
	@discardableResult
	private func closeSelectOrContextForReprocessing() -> Bool {
		guard self.isSelectContextOnly else { return false }

		self.contextElement = nil
		self.insertionMode = .inBody
		return true
	}

	private func closeOpenSelectAndResetInsertionMode() {
		self.popUntil(.select)
		self.resetInsertionMode()
	}

	/// Returns the adjusted insertion target, redirecting to templateContent for template elements
	/// When stack is empty, finds html element per Python justhtml _current_node_or_html behavior
	@inline(__always)
	private var adjustedInsertionTarget: Node {
		if let current = currentNode {
			// If current node is a template, insert into its content document fragment
			if current.tagId == .template, let content = current.templateContent {
				return content
			}
			return current
		}

		// Stack is empty - find html element in document children
		// (matches Python's _current_node_or_html behavior)
		for child in self.document.children {
			if child.tagId == .html {
				return child
			}
		}
		// Fallback to document if no html element found
		return self.document
	}

	private func createElement(name: String, namespace: Namespace = .html, attrs: [String: String])
		-> Node
	{
		let tagId = TagID.from(name)
		if namespace == .html {
			if tagId == .select {
				self.sawSelectElement = true
			}
			else if tagId == .selectedcontent {
				self.sawSelectedcontentElement = true
			}
		}
		return Node(name: name, tagId: tagId, namespace: namespace, attrs: attrs)
	}

	/// Adjust attributes for foreign content (SVG/MathML)
	private func adjustForeignAttributes(_ attrs: [String: String], namespace: Namespace) -> [String:
		String]
	{
		var adjusted: [String: String]? = nil
		for (name, value) in attrs {
			let adjustedName = self.adjustedForeignAttributeName(name, namespace: namespace)
			if adjustedName == name {
				if adjusted != nil {
					adjusted![name] = value
				}
				continue
			}

			if adjusted == nil {
				adjusted = attrs
			}
			adjusted!.removeValue(forKey: name)
			adjusted![adjustedName] = value
		}

		return adjusted ?? attrs
	}

	private func adjustedForeignAttributeName(_ name: String, namespace: Namespace) -> String {
		if let adjustedName = self.exactForeignAttributeAdjustment(name, namespace: namespace) {
			return adjustedName
		}

		if !self.containsASCIIUppercase(name) {
			return name
		}

		let lowercaseName = self.lowercaseIfNeeded(name)

		// Foreign attribute adjustments (xmlns, xlink, xml namespace prefixes)
		// These apply to both SVG and MathML.
		if let foreignAdjusted = FOREIGN_ATTRIBUTE_ADJUSTMENTS[lowercaseName] {
			return foreignAdjusted
		}

		if namespace == .svg, let svgAdjusted = SVG_ATTRIBUTE_ADJUSTMENTS[lowercaseName] {
			return svgAdjusted
		}

		if namespace == .math, let mathAdjusted = MATHML_ATTRIBUTE_ADJUSTMENTS[lowercaseName] {
			return mathAdjusted
		}

		return name
	}

	private func exactForeignAttributeAdjustment(_ name: String, namespace: Namespace) -> String? {
		if let foreignAdjusted = FOREIGN_ATTRIBUTE_ADJUSTMENTS[name] {
			return foreignAdjusted
		}

		if namespace == .svg, let svgAdjusted = SVG_ATTRIBUTE_ADJUSTMENTS[name] {
			return svgAdjusted
		}

		if namespace == .math, let mathAdjusted = MATHML_ATTRIBUTE_ADJUSTMENTS[name] {
			return mathAdjusted
		}

		return nil
	}

	private func containsASCIIUppercase(_ name: String) -> Bool {
		for scalar in name.unicodeScalars {
			if scalar.value >= 65 && scalar.value <= 90 {
				return true
			}
		}
		return false
	}

	private func lowercaseIfNeeded(_ name: String) -> String {
		if !self.containsASCIIUppercase(name) {
			return name
		}
		return name.lowercased()
	}

	@discardableResult
	private func insertElement(name: String, namespace: Namespace = .html, attrs: [String: String])
		-> Node
	{
		let element = self.createElement(name: name, namespace: namespace, attrs: attrs)
		self.insertNode(element)

		// DoS protection: limit nesting depth
		// If we've hit the limit, don't push onto stack - element becomes effectively void
		// This prevents stack overflow on extremely deeply nested documents
		if self.openElements.count < self.maxNestingDepth {
			self.openElements.append(element)
		}
		// Note: element is still in the DOM, just won't receive children
		// Content will be inserted into the parent element instead

		return element
	}

	private func insertNode(_ node: Node) {
		// Per spec: foster parenting only applies when the target is a table element
		// (table, tbody, tfoot, thead, tr). If we're inside a formatting element,
		// insert normally into that element.
		if self.fosterParentingEnabled {
			let target = self.adjustedInsertionTarget
			if self.isTableRelatedElement(target) {
				self.fosterParentNode(node)
			}
			else {
				target.appendChild(node)
			}
		}
		else {
			self.adjustedInsertionTarget.appendChild(node)
		}
	}

	/// Foster parent insertion - used when we need to insert nodes outside of a table
	private func fosterParentNode(_ node: Node) {
		let location = self.fosterParentingLocation()

		// If last template is after last table, or there's no table, use template contents
		if let templateIndex = location.templateIndex,
		   self.templateAtIndexWinsFosterParenting(templateIndex, tableIndex: location.tableIndex),
		   let content = openElements[templateIndex].templateContent
		{
			content.appendChild(node)
			return
		}

		// If no table found in the stack
		guard let tableIndex = location.tableIndex else {
			// For fragment parsing or when there's no table, insert in document or first element
			if !self.openElements.isEmpty {
				self.openElements[0].appendChild(node)
			}
			else {
				// Fragment parsing - insert directly into document
				self.document.appendChild(node)
			}
			return
		}

		self.insertNodeUsingTableFosterParenting(node, tableIndex: tableIndex)
	}

	private func fosterParentingLocation() -> (tableIndex: Int?, templateIndex: Int?) {
		var tableIndex: Int? = nil
		var templateIndex: Int? = nil

		for index in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let element = self.openElements[index]
			if element.tagId == .table, tableIndex == nil {
				tableIndex = index
			}
			if element.tagId == .template, templateIndex == nil {
				templateIndex = index
			}
		}
		return (tableIndex, templateIndex)
	}

	private func templateAtIndexWinsFosterParenting(_ templateIndex: Int, tableIndex: Int?) -> Bool {
		guard let tableIndex else { return true }
		return templateIndex > tableIndex
	}

	private func insertNodeUsingTableFosterParenting(_ node: Node, tableIndex: Int) {
		let tableElement = self.openElements[tableIndex]

		// If table's parent is an element, insert before table
		if let parent = tableElement.parent {
			if let tableChildIndex = parent.indexOfChild(tableElement) {
				parent.insertChild(node, at: tableChildIndex)
			}
			return
		}

		// Otherwise, insert at the end of the element before table in the stack
		if tableIndex > 0 {
			self.openElements[tableIndex - 1].appendChild(node)
		}
		else {
			// Table is first in stack, insert into document
			self.document.appendChild(node)
		}
	}

	private func insertCharacter(_ ch: Character) {
		let target = self.adjustedInsertionTarget

		// Per spec: foster parenting for text only applies when the target is a table element
		if self.fosterParentingEnabled,
		   self.isTableRelatedElement(target)
		{
			self.insertCharacterWithFosterParenting(ch)
			return
		}

		self.appendText(String(ch), to: target)
	}

	/// Insert a string of text directly (batch insertion for performance)
	@inline(__always)
	private func insertText(_ text: String) {
		guard !text.isEmpty else { return }

		let target = self.adjustedInsertionTarget

		// Per spec: foster parenting for text only applies when the target is a table element
		if self.fosterParentingEnabled,
		   self.isTableRelatedElement(target)
		{
			// Fall back to character-by-character for foster parenting
			for ch in text {
				self.insertCharacterWithFosterParenting(ch)
			}
			return
		}

		self.appendText(text, to: target)
	}

	private func insertCharacterWithFosterParenting(_ ch: Character) {
		let text = String(ch)
		let location = self.fosterParentingLocation()

		// If last template is after last table, or there's no table, use template contents
		if let templateIndex = location.templateIndex,
		   self.templateAtIndexWinsFosterParenting(templateIndex, tableIndex: location.tableIndex),
		   let content = openElements[templateIndex].templateContent
		{
			self.appendText(text, to: content)
			return
		}

		// If no table found
		guard let tableIndex = location.tableIndex else {
			let target = self.adjustedInsertionTarget
			self.appendText(text, to: target)
			return
		}

		self.insertTextUsingTableFosterParenting(text, tableIndex: tableIndex)
	}

	private func insertTextUsingTableFosterParenting(_ text: String, tableIndex: Int) {
		let tableElement = self.openElements[tableIndex]

		// Insert before the table
		if let parent = tableElement.parent {
			// Check if there's a text node right before the table that we can merge with
			if let tableIdx = parent.indexOfChild(tableElement) {
				if tableIdx > 0 {
					let prevNode = parent.children[tableIdx - 1]
					if self.appendTextIfPossible(text, to: prevNode) {
						return
					}
				}
				let textNode = Node.text(text)
				parent.insertChild(textNode, at: tableIdx)
			}
		}
		else {
			// Table has no parent - use the element before table in stack
			if tableIndex > 0 {
				let target = self.openElements[tableIndex - 1]
				self.appendText(text, to: target)
			}
		}
	}

	private func appendText(_ text: String, to target: Node) {
		if let lastChild = target.children.last, self.appendTextIfPossible(text, to: lastChild) {
			return
		}

		let textNode = Node.text(text)
		target.appendChild(textNode)
	}

	private func appendTextIfPossible(_ text: String, to node: Node) -> Bool {
		guard node.tagId == .text else { return false }
		if case var .text(existing) = node.data {
			node.data = nil
			existing.append(text)
			node.data = .text(existing)
			return true
		}
		return false
	}

	private func popCurrentElement() {
		if !self.openElements.isEmpty {
			self.openElements.removeLast()
		}
	}

	private func popUntil(_ name: String) {
		// In fragment parsing, if the target element is only the context element
		// (not on the actual stack), we should pop until we reach the html element
		// Only match HTML namespace elements
		let isContextOnly =
			self.contextElement?.name == name
				&& !self.hasOpenHTMLElement(named: name)

		while let current = currentNode {
			// Only match HTML namespace elements
			if current.name == name, self.isHTMLNamespace(current) {
				self.popCurrentElement()
				break
			}
			// In fragment parsing with context-only target, stop at html element
			if isContextOnly, current.name == "html" {
				break
			}
			self.popCurrentElement()
		}
	}

	private func popUntil(_ tagId: TagID) {
		// In fragment parsing, if the target element is only the context element
		// (not on the actual stack), we should pop until we reach the html element.
		let isContextOnly =
			self.contextElement?.tagId == tagId
				&& !self.hasOpenHTMLElement(tagId)

		while let current = currentNode {
			if current.tagId == tagId, self.isHTMLNamespace(current) {
				self.popCurrentElement()
				break
			}
			if isContextOnly, current.tagId == .html {
				break
			}
			self.popCurrentElement()
		}
	}

	private func popUntilElementNamedAnyNamespace(_ name: String) {
		self.popUntilElementAnyNamespace { $0.name == name }
	}

	private func popUntilElementAnyNamespace(where shouldStopAfterPopping: (Node) -> Bool) {
		while let current = currentNode {
			self.popCurrentElement()
			if shouldStopAfterPopping(current) {
				break
			}
		}
	}

	/// Clear the stack back to a table context (table, template, or html)
	private func clearStackBackToTableContext() {
		self.clearStackBackToContext { self.isTableContextElement($0) }
	}

	/// Clear the stack back to a table body context (tbody, tfoot, thead, template, or html)
	private func clearStackBackToTableBodyContext() {
		self.clearStackBackToContext { self.isTableBodyContextElement($0) }
	}

	/// Clear the stack back to a table row context (tr, template, or html)
	private func clearStackBackToTableRowContext() {
		// Per Python justhtml: requires both name match AND HTML namespace
		self.clearStackBackToContext {
			self.isHTMLNamespace($0) && self.isTableRowContextElement($0)
		}
	}

	private func clearStackBackToContext(_ isContextElement: (Node) -> Bool) {
		self.popUntilCurrentElement(where: isContextElement)
	}

	private func popUntilCurrentElement(where shouldStopBeforePopping: (Node) -> Bool) {
		while let current = currentNode {
			if shouldStopBeforePopping(current) {
				break
			}
			self.popCurrentElement()
		}
	}

	private func popWhileCurrentElement(where shouldPop: (Node) -> Bool) {
		while let current = currentNode, shouldPop(current) {
			self.popCurrentElement()
		}
	}

	/// Close the current cell (td or th)
	private func closeCell() {
		self.generateImpliedEndTags()
		if let current = currentNode, current.tagId != .td, current.tagId != .th {
			self.emitError("end-tag-too-early")
		}
		self.popUntilHTMLTableCell()
		self.clearActiveFormattingElementsToLastMarker()
		self.insertionMode = .inRow
	}

	private func popUntilHTMLTableCell() {
		// Per Python justhtml: if no HTML td/th exists, may pop to empty stack.
		self.popUntilElementAnyNamespace {
			($0.tagId == .td || $0.tagId == .th) && self.isHTMLNamespace($0)
		}
	}

	private func closeCellAndReprocessStartTag(_ tag: StartTagToken) {
		self.reprocessStartTag(tag, after: self.closeCell)
	}

	private func reprocessStartTag(
		name: String,
		attrs: [String: String],
		selfClosing: Bool,
		after closeCurrentContext: () -> Void
	) {
		self.reprocessStartTag(
			StartTagToken(name: name, attrs: attrs, selfClosing: selfClosing),
			after: closeCurrentContext)
	}

	private func reprocessStartTag(_ tag: StartTagToken, after closeCurrentContext: () -> Void) {
		closeCurrentContext()
		self.processStartTag(tag)
	}

	private func reprocessEndTag(_ name: String, after closeCurrentContext: () -> Void) {
		self.reprocessEndTag(EndTagToken(name: name), after: closeCurrentContext)
	}

	private func reprocessEndTag(_ tag: EndTagToken, after closeCurrentContext: () -> Void) {
		closeCurrentContext()
		self.processEndTag(tag)
	}

	private func insertHtmlElement() {
		let html = self.createElement(name: "html", attrs: [:])
		self.document.appendChild(html)
		self.openElements.append(html)
	}

	private func insertHeadElement() {
		let head = self.insertElement(name: "head", attrs: [:])
		self.headElement = head
	}

	private func insertBodyElement() {
		let body = self.insertElement(name: "body", attrs: [:])
		self.bodyElement = body
	}

	// MARK: - Scope Checking

	private enum ScopeBoundaryKind {
		case general
		case listItem
		case button
	}

	private func hasElementInScope(_ name: String) -> Bool {
		return self.hasElementInScope(name, scope: .general)
	}

	private func hasElementInSelectScope(_ tagId: TagID) -> Bool {
		// In select scope, everything except optgroup and option is a scope marker.
		for node in self.openElements.reversed() {
			if node.tagId == tagId {
				return true
			}
			if node.tagId != .optgroup, node.tagId != .option {
				// Per spec: In fragment parsing, if context element matches, consider it in scope.
				return self.contextElement?.tagId == tagId
			}
		}
		return self.contextElement?.tagId == tagId
	}

	private func hasElementInTableScope(_ name: String) -> Bool {
		if let tagId = self.tableScopeTagID(for: name) {
			return self.hasElementInTableScope(tagId)
		}

		for node in self.openElements.reversed() {
			if node.name == name, self.isHTMLNamespace(node) {
				return true
			}
			if self.isTableScopeTerminator(node) {
				return false
			}
		}
		if let ctx = contextElement, ctx.name == name, self.isHTMLNamespace(ctx) {
			return true
		}
		return false
	}

	private func tableScopeTagID(for name: String) -> TagID? {
		switch name {
			case "html": return .html
			case "table": return .table
			case "template": return .template
			case "td": return .td
			case "th": return .th
			case "tr": return .tr
			case "tbody": return .tbody
			case "thead": return .thead
			case "tfoot": return .tfoot
			case "caption": return .caption
			case "col": return .col
			case "colgroup": return .colgroup
			default: return nil
		}
	}

	private func hasElementInScope(_ name: String, scope: ScopeBoundaryKind) -> Bool {
		for node in self.openElements.reversed() {
			// Per WHATWG spec, only match HTML namespace elements when checking scope
			if node.name == name, self.isHTMLNamespace(node) {
				return true
			}
			// Scope boundary elements can be in any namespace
			// HTML elements in scopeElements, or MathML/SVG integration points
			if self.isScopeBoundary(node, scope: scope) {
				return false
			}
		}
		// Check context element for fragment parsing
		if let ctx = contextElement, ctx.name == name, self.isHTMLNamespace(ctx) {
			return true
		}
		return false
	}

	// MARK: - TagID-based Scope Checking (fast integer comparisons)

	@inline(__always)
	private func hasElementInScope(_ tagId: TagID) -> Bool {
		return self.hasElementInScope(tagId, scope: .general)
	}

	@inline(__always)
	private func hasElementInButtonScope(_ tagId: TagID) -> Bool {
		return self.hasElementInScope(tagId, scope: .button)
	}

	@inline(__always)
	private func hasElementInListItemScope(_ tagId: TagID) -> Bool {
		return self.hasElementInScope(tagId, scope: .listItem)
	}

	private var hasTableCellElementInTableScope: Bool {
		for node in self.openElements.reversed() {
			if node.tagId == .td || node.tagId == .th {
				return true
			}
			if self.isTableScopeTerminator(node) {
				return false
			}
		}
		return self.contextElement?.tagId == .td || self.contextElement?.tagId == .th
	}

	private var hasTableSectionElementInTableScope: Bool {
		for node in self.openElements.reversed() {
			let isHTML = self.isHTMLNamespace(node)
			if isHTML, self.isTableSectionTag(node.tagId) {
				return true
			}
			if self.isTableScopeTerminator(node) {
				return false
			}
		}
		if let ctx = contextElement, self.isHTMLNamespace(ctx) {
			return self.isTableSectionTag(ctx.tagId)
		}
		return false
	}

	private var hasHeadingElementInScope: Bool {
		for node in self.openElements.reversed() {
			if self.isHTMLNamespace(node), self.isHeadingTag(node.tagId) {
				return true
			}
			if self.isScopeBoundary(node, scope: .general) {
				return false
			}
		}
		if let ctx = contextElement, self.isHTMLNamespace(ctx) {
			return self.isHeadingTag(ctx.tagId)
		}
		return false
	}

	private func isHeadingTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .h1, .h2, .h3, .h4, .h5, .h6:
				return true
			default:
				return false
		}
	}

	private func isTableRelatedElement(_ node: Node) -> Bool {
		switch node.tagId {
			case .table, .tbody, .tfoot, .thead, .tr:
				return true
			default:
				return false
		}
	}

	private func isSelectInTableBoundaryTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .caption, .table, .tbody, .tfoot, .thead, .tr, .td, .th:
				return true
			default:
				return false
		}
	}

	private func isSelectFallbackFormElementTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .p, .div, .span, .button, .datalist, .selectedcontent, .menuitem:
				return true
			default:
				return false
		}
	}

	private func isTableContextElement(_ node: Node) -> Bool {
		switch node.tagId {
			case .table, .template, .html:
				return true
			default:
				return false
		}
	}

	private func isTableBodyContextElement(_ node: Node) -> Bool {
		switch node.tagId {
			case .tbody, .tfoot, .thead, .template, .html:
				return true
			default:
				return false
		}
	}

	private func isTableRowContextElement(_ node: Node) -> Bool {
		switch node.tagId {
			case .tr, .template, .html:
				return true
			default:
				return false
		}
	}

	private func isFormattingElementTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .a, .b, .big, .code, .em, .font, .i, .nobr,
			     .s, .small, .strike, .strong, .tt, .u:
				return true
			default:
				return false
		}
	}

	@inline(__always)
	private func hasElementInTableScope(_ tagId: TagID) -> Bool {
		for node in self.openElements.reversed() {
			let isHTML = self.isHTMLNamespace(node)
			if node.tagId == tagId, isHTML || tagId == .td || tagId == .th || tagId == .tr {
				return true
			}
			if self.isTableScopeTerminator(node) {
				return false
			}
		}
		if let ctx = contextElement, ctx.tagId == tagId {
			let isHTML = self.isHTMLNamespace(ctx)
			if isHTML || tagId == .td || tagId == .th || tagId == .tr {
				return true
			}
		}
		return false
	}

	@inline(__always)
	private func hasElementInScope(_ tagId: TagID, scope: ScopeBoundaryKind) -> Bool {
		for node in self.openElements.reversed() {
			if node.tagId == tagId, self.isHTMLNamespace(node) {
				return true
			}
			if self.isScopeBoundary(node, scope: scope) {
				return false
			}
		}
		if let ctx = contextElement, ctx.tagId == tagId, self.isHTMLNamespace(ctx) {
			return true
		}
		return false
	}

	@inline(__always)
	private func isScopeBoundary(_ node: Node, scope: ScopeBoundaryKind) -> Bool {
		guard self.isScopeBoundaryTag(node.tagId, scope: scope) else { return false }

		if self.isMathMLScopeBoundaryTag(node.tagId) {
			return node.namespace == .math
		}
		if self.isSVGIntegrationPointTag(node.tagId) {
			return node.namespace == .svg
		}
		return true
	}

	@inline(__always)
	private func isScopeBoundaryTag(_ tagId: TagID, scope: ScopeBoundaryKind) -> Bool {
		switch tagId {
			case .applet, .caption, .html, .table, .td, .th, .marquee, .object,
			     .template, .mi, .mo, .mn, .ms, .mtext, .annotationXml,
			     .foreignObject, .desc, .title:
				return true
			case .ol, .ul:
				return scope == .listItem
			case .button:
				return scope == .button
			default:
				return false
		}
	}


	private func isTableScopeTerminator(_ node: Node) -> Bool {
		self.isHTMLNamespace(node) && self.isTableScopeTerminatorTag(node.tagId)
	}

	private func isTableScopeTerminatorTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .html, .table, .template:
				return true
			default:
				return false
		}
	}

	private func isTableSectionTag(_ tagId: TagID) -> Bool {
		tagId == .tbody || tagId == .thead || tagId == .tfoot
	}

	private func isMathMLScopeBoundaryTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .mi, .mo, .mn, .ms, .mtext, .annotationXml:
				return true
			default:
				return false
		}
	}

	private func isMathMLTextIntegrationPointTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .mi, .mo, .mn, .ms, .mtext:
				return true
			default:
				return false
		}
	}

	private func isSVGIntegrationPointTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .foreignObject, .desc, .title:
				return true
			default:
				return false
		}
	}

	@inline(__always)
	private func isHTMLNamespace(_ node: Node) -> Bool {
		self.isHTMLNamespace(node.namespace)
	}

	@inline(__always)
	private func isHTMLNamespace(_ namespace: Namespace?) -> Bool {
		namespace == nil || namespace == .html
	}

	// MARK: - Implied End Tags

	private func generateImpliedEndTags(except: String? = nil) {
		self.popWhileCurrentElement { current in
			self.isImpliedEndTag(current.tagId) && current.name != except
		}
	}

	private func isImpliedEndTag(_ tagId: TagID) -> Bool {
		switch tagId {
			case .dd, .dt, .li, .optgroup, .option, .p, .rb, .rp, .rt, .rtc:
				return true
			default:
				return false
		}
	}

	private func closePElement() {
		self.generateImpliedEndTags(except: "p")
		if self.currentNode?.tagId != .p {
			self.emitError("expected-p-end-tag")
		}
		self.popUntil(.p)
	}

	// MARK: - Formatting Elements

	private func pushFormattingElement(_ element: Node) {
		// Noah's Ark clause: If there are already 3 elements with the same tag name
		// and attributes in the list before the last marker, remove the earliest one
		var matchCount = 0
		var earliestMatchIndex: Int?

		for i in stride(from: self.activeFormattingElements.count - 1, through: 0, by: -1) {
			guard let entry = activeFormattingElements[i] else {
				break // Hit marker, stop searching
			}

			// Check if same tag name and attributes
			if entry.name == element.name, entry.attrs == element.attrs {
				earliestMatchIndex = i // Keep updating while walking backward to find earliest.
				matchCount += 1
			}
		}

		// If we already have 3 matching elements, remove the earliest one
		if matchCount >= 3, let idx = earliestMatchIndex {
			self.activeFormattingElements.remove(at: idx)
		}

		self.activeFormattingElements.append(element)
	}

	private func insertMarker() {
		self.activeFormattingElements.append(nil)
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
		if self.activeFormattingElements.isEmpty { return }

		// 2. If the last entry is a marker or is already in open elements, return
		guard let lastEntry = activeFormattingElements.last else { return }

		if lastEntry == nil { return } // marker
		if let elem = lastEntry, self.hasOpenElement(elem) {
			return
		}

		// 3. Rewind: find the first entry that's either a marker or in open elements
		var entryIndex = self.activeFormattingElements.count - 1
		while entryIndex > 0 {
			entryIndex -= 1
			if let entry = activeFormattingElements[entryIndex] {
				if self.hasOpenElement(entry) {
					entryIndex += 1
					break
				}
			}
			else {
				// Hit a marker
				entryIndex += 1
				break
			}
		}

		// 4. Advance: create and insert elements
		while entryIndex < self.activeFormattingElements.count {
			guard let entry = activeFormattingElements[entryIndex] else {
				entryIndex += 1
				continue
			}

			// Create new element with same name and attributes
			let newElement = self.insertElement(
				name: entry.name, namespace: entry.namespace ?? .html, attrs: entry.attrs)

			// Replace the entry in the list
			self.activeFormattingElements[entryIndex] = newElement

			entryIndex += 1
		}
	}

	private func adoptionAgency(_ tag: EndTagToken) {
		self.adoptionAgency(name: tag.name, tagId: tag.tagId)
	}

	private func adoptionAgency(name: String, tagId: TagID = .unknown) {
		let hasKnownTagId = tagId != .unknown

		// Step 1: If current node is the subject and not in active formatting, just pop it
		if let current = currentNode,
		   hasKnownTagId ? current.tagId == tagId : current.name == name
		{
			let hasFormattingEntry = hasKnownTagId
				? self.activeFormattingElementIndex(tagId) != nil
				: self.hasActiveFormattingEntry(name)
			if !hasFormattingEntry {
				if hasKnownTagId {
					self.popUntil(tagId)
				}
				else {
					self.popUntil(name)
				}
				return
			}
		}

		// Step 2: Outer loop (max 8 iterations)
		for _ in 0 ..< 8 {
			// Step 3: Find formatting element in active formatting list
			let formattingElementIndex = hasKnownTagId
				? self.activeFormattingElementIndex(tagId)
				: self.activeFormattingElementIndex(named: name)

			guard let feIndex = formattingElementIndex,
			      let formattingElement = activeFormattingElements[feIndex]
			else {
				// No formatting element found - use any other end tag handling
				self.anyOtherEndTag(name: name)
				return
			}

			// Step 4: Check if formatting element is in open elements
			guard let feStackIndex = self.openElementIndex(matching: formattingElement) else {
				self.emitError("adoption-agency-1.3")
				self.activeFormattingElements.remove(at: feIndex)
				return
			}

			// Step 5: Check if formatting element is in scope
			if !(hasKnownTagId ? self.hasElementInScope(tagId) : self.hasElementInScope(name)) {
				self.emitError("adoption-agency-1.3")
				return
			}

			// Step 6: If formatting element is not current node, emit error
			if self.currentNode !== formattingElement {
				self.emitError("adoption-agency-1.3")
			}

			// Steps 7-8: Find the furthest block, or pop through the formatting element.
			guard let (fb, fbIndex) = self.furthestBlockAfterFormattingElement(at: feStackIndex) else {
				self.popThroughOpenElement(at: feStackIndex)
				self.activeFormattingElements.remove(at: feIndex)
				return
			}

			// Step 9: Common ancestor
			// Safety check - formatting element must have a parent
			if feStackIndex == 0 {
				// No common ancestor - just pop to formatting element
				self.popThroughOpenElement(at: feStackIndex)
				self.activeFormattingElements.remove(at: feIndex)
				return
			}
			let commonAncestor = self.openElements[feStackIndex - 1]

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
				if nodeIndex < 0 || nodeIndex >= self.openElements.count {
					break
				}
				node = self.openElements[nodeIndex]

				// Step 12.2: If node is formatting element, break
				if node === formattingElement {
					break
				}

				// Step 12.3: Find node's entry in active formatting
				var nodeFormattingIndex = self.activeFormattingElementIndex(matching: node)

				// Step 12.4: If inner loop counter > 3 and node is in active formatting, remove it
				if innerLoopCounter > 3, let nfi = nodeFormattingIndex {
					self.activeFormattingElements.remove(at: nfi)
					if nfi < bookmark {
						bookmark -= 1
					}
					nodeFormattingIndex = nil
				}

				// Step 12.5: If node is not in active formatting, remove from stack and continue
				guard let nfi = nodeFormattingIndex else {
					self.openElements.remove(at: nodeIndex)
					// After removal, elements shift down, so nodeIndex now points to what was nodeIndex+1.
					// The next decrement at the loop start will correctly move to the element that was above.
					continue
				}

				// Step 12.6: Create new element and replace in both lists
				let newElement = Node(
					name: node.name, namespace: node.namespace ?? .html, attrs: node.attrs)

				// Replace in active formatting
				self.activeFormattingElements[nfi] = newElement

				// Replace in open elements
				self.openElements[nodeIndex] = newElement
				node = newElement

				// Step 12.7: If last node is furthest block, update bookmark
				if lastNode === fb {
					bookmark = nfi + 1
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
			self.insertAdoptionAgencyLastNode(lastNode, into: commonAncestor)

			// Step 14: Create new formatting element
			let newFormattingElement = Node(
				name: formattingElement.name, namespace: formattingElement.namespace ?? .html,
				attrs: formattingElement.attrs)

			// Step 15: Move children of furthest block to new formatting element
			self.moveChildren(from: fb, to: newFormattingElement)

			// Step 16: Append new formatting element to furthest block
			fb.appendChild(newFormattingElement)

			// Steps 17-18: Replace the old formatting element in both parser stacks.
			self.replaceFormattingElementAfterAdoptionAgency(
				formattingElement,
				with: newFormattingElement,
				activeFormattingIndex: feIndex,
				bookmark: bookmark,
				furthestBlock: fb)
		}
	}

	/// Check if there's an entry for the given name in active formatting elements (before any marker)
	private func hasActiveFormattingEntry(_ name: String) -> Bool {
		self.activeFormattingElementIndex(named: name) != nil
	}

	/// Finds the most recent active formatting element with this tag before the last marker.
	private func activeFormattingElementIndex(named name: String) -> Int? {
		self.activeFormattingElementIndexFromEnd(stopAtMarker: true) { $0.name == name }
	}

	private func activeFormattingElementIndex(_ tagId: TagID) -> Int? {
		self.activeFormattingElementIndexFromEnd(stopAtMarker: true) { $0.tagId == tagId }
	}

	private func activeFormattingElementIndexFromEnd(
		stopAtMarker: Bool,
		where matches: (Node) -> Bool
	) -> Int? {
		for i in stride(from: self.activeFormattingElements.count - 1, through: 0, by: -1) {
			guard let elem = activeFormattingElements[i] else {
				if stopAtMarker {
					return nil
				}
				continue
			}

			if matches(elem) {
				return i
			}
		}
		return nil
	}

	private func activeFormattingElementIndex(matching node: Node) -> Int? {
		self.activeFormattingElements.firstIndex {
			guard let elem = $0 else { return false }
			return elem === node
		}
	}

	private func furthestBlockAfterFormattingElement(at formattingElementStackIndex: Int) -> (
		node: Node, index: Int
	)? {
		for i in (formattingElementStackIndex + 1) ..< self.openElements.count {
			let node = self.openElements[i]
			if self.isSpecialElementForAdoptionAgency(node) {
				return (node, i)
			}
		}
		return nil
	}

	private func isSpecialElementForAdoptionAgency(_ node: Node) -> Bool {
		if self.isHTMLNamespace(node) {
			return self.isSpecialElement(node)
		}
		if node.namespace == .svg {
			return self.isSVGIntegrationPointTag(node.tagId)
		}
		if node.namespace == .math {
			return self.isMathMLScopeBoundaryTag(node.tagId)
		}
		return false
	}

	private func isDefinitionListItemRecoveryBoundary(_ node: Node) -> Bool {
		guard self.isSpecialElement(node) else { return false }
		return node.tagId != .address && node.tagId != .div && node.tagId != .p
	}

	private func isSpecialElement(_ node: Node) -> Bool {
		if SPECIAL_ELEMENTS_ID.contains(node.tagId) {
			return true
		}
		return SPECIAL_ELEMENTS.contains(node.name)
	}

	private func popThroughOpenElement(at stackIndex: Int) {
		self.popOpenElementsThroughIndex(stackIndex)
	}

	private func popOpenElementsThroughIndex(_ stackIndex: Int) {
		while self.openElements.count > stackIndex {
			self.popCurrentElement()
		}
	}

	private func insertAdoptionAgencyLastNode(_ node: Node, into commonAncestor: Node) {
		if let parent = node.parent {
			parent.removeChild(node)
		}
		if commonAncestor.tagId == .template, let content = commonAncestor.templateContent {
			content.appendChild(node)
		}
		else if self.fosterParentingEnabled,
		        self.isTableRelatedElement(commonAncestor)
		{
			self.fosterParentNode(node)
		}
		else {
			commonAncestor.appendChild(node)
		}
	}

	private func moveChildren(from source: Node, to destination: Node) {
		source.moveChildren(to: destination)
	}

	private func replaceFormattingElementAfterAdoptionAgency(
		_ formattingElement: Node,
		with newFormattingElement: Node,
		activeFormattingIndex: Int,
		bookmark: Int,
		furthestBlock: Node
	) {
		self.activeFormattingElements.remove(at: activeFormattingIndex)
		self.activeFormattingElements.insert(
			newFormattingElement,
			at: min(bookmark, self.activeFormattingElements.count))

		self.removeFirstOpenElement(matching: formattingElement)
		if let newFurthestBlockIndex = self.openElementIndex(matching: furthestBlock) {
			self.openElements.insert(newFormattingElement, at: newFurthestBlockIndex + 1)
		}
	}

	private func hasOpenElement(_ node: Node) -> Bool {
		self.openElementIndex(matching: node) != nil
	}

	private func hasOpenElement(_ tagId: TagID) -> Bool {
		self.openElementIndex(matchingTagId: tagId) != nil
	}

	private func hasOpenHTMLElement(named name: String) -> Bool {
		self.openElementIndex(matchingHTMLName: name) != nil
	}

	private func hasOpenHTMLElement(_ tagId: TagID) -> Bool {
		self.openElementIndex(matchingHTMLTagId: tagId) != nil
	}

	private func openElementIndex(matching node: Node) -> Int? {
		self.openElements.firstIndex { $0 === node }
	}

	private func lastOpenElementIndex(matching node: Node) -> Int? {
		self.openElements.lastIndex { $0 === node }
	}

	private func openElementIndex(matchingTagId tagId: TagID) -> Int? {
		self.openElements.firstIndex { $0.tagId == tagId }
	}

	private func openElementIndex(matchingHTMLName name: String) -> Int? {
		self.openElements.firstIndex { $0.name == name && self.isHTMLNamespace($0) }
	}

	private func openElementIndex(matchingHTMLTagId tagId: TagID) -> Int? {
		self.openElements.firstIndex { $0.tagId == tagId && self.isHTMLNamespace($0) }
	}

	@discardableResult
	private func removeFirstOpenElement(matching node: Node) -> Bool {
		guard let index = self.openElementIndex(matching: node) else {
			return false
		}
		self.openElements.remove(at: index)
		return true
	}

	@discardableResult
	private func removeLastOpenElement(matching node: Node) -> Bool {
		guard let index = self.lastOpenElementIndex(matching: node) else {
			return false
		}
		self.openElements.remove(at: index)
		return true
	}

	// MARK: - Foreign Content

	/// Elements that break out of foreign content back to HTML
	private static let foreignContentBreakoutElements: Set<String> = [
		"b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl", "dt",
		"em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i", "img", "li",
		"listing", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small", "span",
		"strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var",
	]

	/// Get the adjusted current node per WHATWG spec
	/// In fragment case with only one element on stack, use the context element instead
	private var adjustedCurrentNode: Node? {
		// If we're in fragment parsing and the stack only has the html element,
		// use the context element for namespace decisions
		if self.contextElement != nil, self.openElements.count == 1 {
			return self.contextElement
		}
		return self.openElements.last
	}

	/// Check if we should process start tags in foreign content mode
	/// Returns false only for HTML integration points (SVG foreignObject/desc/title or MathML annotation-xml with encoding)
	/// because MathML text integration points still process MOST start tags as foreign content
	private func shouldProcessInForeignContent() -> Bool {
		guard let node = adjustedCurrentNode else { return false }

		guard let ns = node.namespace else { return false }

		// Check if we're in an SVG HTML integration point (foreignObject, desc, title)
		// These process start tags as HTML
		if self.isSVGHtmlIntegrationPoint(node) {
			return false
		}

		if self.isMathMLAnnotationXmlHTMLIntegrationPoint(node) {
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

		return self.isMathMLTextIntegrationPoint(currentNode)
	}

	/// Check if current node is an SVG HTML integration point
	private func isInSVGHtmlIntegrationPoint() -> Bool {
		guard let currentNode = openElements.last else { return false }

		return self.isSVGHtmlIntegrationPoint(currentNode)
	}

	/// Check if current node is a MathML annotation-xml HTML integration point
	/// annotation-xml with encoding="text/html" or "application/xhtml+xml" is an HTML integration point
	private func isInMathMLAnnotationXmlIntegrationPoint() -> Bool {
		guard let currentNode = openElements.last else { return false }

		return self.isMathMLAnnotationXmlHTMLIntegrationPoint(currentNode)
	}

	private func isMathMLAnnotationXmlHTMLIntegrationPoint(_ node: Node) -> Bool {
		guard node.namespace == .math, node.tagId == .annotationXml else { return false }

		guard let encoding = self.attributeValue(in: node.attrs, matchingLowercaseName: "encoding") else {
			return false
		}

		return self.isHTMLIntegrationPointEncoding(encoding)
	}

	private func attributeValue(in attrs: [String: String], matchingLowercaseName name: String) -> String? {
		if let value = attrs[name] {
			return value
		}

		return attrs.first { key, _ in
			key != name && self.nameMatchesLowercase(key, name)
		}?.value
	}

	private func isHTMLIntegrationPointEncoding(_ encoding: String) -> Bool {
		return encoding.asciiCaseInsensitiveEquals("text/html")
			|| encoding.asciiCaseInsensitiveEquals("application/xhtml+xml")
	}

	/// Process an end tag in foreign content per WHATWG spec
	/// Returns true if handled, false if should fall through to normal processing
	private func processForeignContentEndTag(name: String) -> Bool {
		let lowercaseName = self.lowercaseIfNeeded(name)

		// Special handling for </br> and </p> - break out and reprocess as end tag
		if lowercaseName == "br" || lowercaseName == "p" {
			self.emitError("unexpected-end-tag")
			self.popForeignContentForEndTagRecovery()
			// Reprocess the end tag in HTML mode - return false to let normal processing handle it
			return false
		}

		switch self.findForeignContentEndTagStackMatch(named: lowercaseName) {
			case .foreignMatch(let index):
				self.popOpenElementsThroughIndex(index)
				return true
			case .htmlBoundaryOrNoMatch:
				return false
		}
	}

	private func findForeignContentEndTagStackMatch(named lowercaseName: String) -> ForeignContentEndTagSearchResult {
		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let node = self.openElements[i]

			// Check if this element matches (case-insensitive for foreign, case-sensitive for HTML)
			if self.nameMatchesLowercase(node.name, lowercaseName) {
				// Only pop if the element is in a foreign namespace
				// HTML elements should be handled by normal processing
				if self.isHTMLNamespace(node) {
					return .htmlBoundaryOrNoMatch
				}
				return .foreignMatch(i)
			}

			// If we hit an HTML element that doesn't match, let normal processing handle it
			if self.isHTMLNamespace(node) {
				return .htmlBoundaryOrNoMatch
			}
		}

		// No matching element found, let normal processing handle it
		return .htmlBoundaryOrNoMatch
	}

	private func nameMatchesLowercase(_ name: String, _ lowercaseName: String) -> Bool {
		name == lowercaseName || name.asciiCaseInsensitiveEquals(lowercaseName)
	}

	/// Process a start tag in foreign content
	/// Returns true if handled, false if should fall through to normal processing
	private func processForeignContentStartTag(
		name: String, attrs: [String: String], selfClosing: Bool
	) -> Bool {
		let lowercaseName = self.lowercaseIfNeeded(name)

		// In MathML text integration points (mi, mo, mn, ms, mtext), only mglyph and malignmark
		// stay in MathML - everything else should be processed as HTML
		if let adjNode = adjustedCurrentNode,
		   self.isMathMLTextIntegrationPoint(adjNode),
		   lowercaseName != "mglyph" && lowercaseName != "malignmark"
		{
			return false
		}

		if self.isForeignContentBreakoutStartTag(lowercaseName, attrs: attrs) {
			// If current node is MathML text integration point or SVG HTML integration point,
			// process breakout elements as HTML without popping
			if self.isForeignContentBreakoutPassthroughContext() {
				return false
			}

			self.popForeignContentForStartTagBreakout()
			// Reset insertion mode after breaking out of foreign content
			// This is critical for finding table elements (tr/td/th) from SVG/MathML on the stack
			self.resetInsertionMode()
			// Process as normal HTML
			return false
		}

		// Determine the namespace for the new element using adjusted current node
		guard let adjNode = adjustedCurrentNode,
		      let currentNs = adjNode.namespace
		else { return false }

		// SVG and MathML elements inside foreign content should use their own namespace
		var ns: Namespace = currentNs
		var adjustedName = name
		if lowercaseName == "svg" {
			ns = .svg
		}
		else if lowercaseName == "math" {
			ns = .math
		}
		else if currentNs == .svg {
			// Apply SVG tag name adjustments
			adjustedName = SVG_ELEMENT_ADJUSTMENTS[lowercaseName] ?? name
		}

		self.insertForeignElement(name: adjustedName, namespace: ns, attrs: attrs, selfClosing: selfClosing)

		return true
	}

	private func isForeignContentBreakoutStartTag(_ lowercaseName: String, attrs: [String: String]) -> Bool {
		if Self.foreignContentBreakoutElements.contains(lowercaseName) {
			return true
		}
		guard lowercaseName == "font" else { return false }

		// font only breaks out if it has color, face, or size attributes.
		return attrs.keys.contains(where: self.isForeignContentFontBreakoutAttribute)
	}

	private func isForeignContentFontBreakoutAttribute(_ name: String) -> Bool {
		switch name {
			case "color", "face", "size":
				return true
			default:
				return name.asciiCaseInsensitiveEquals("color")
					|| name.asciiCaseInsensitiveEquals("face")
					|| name.asciiCaseInsensitiveEquals("size")
		}
	}

	private func isForeignContentBreakoutPassthroughContext() -> Bool {
		guard let current = currentNode else { return false }
		return self.isSVGHtmlIntegrationPoint(current)
			|| self.isMathMLTextIntegrationPoint(current)
	}

	private func popForeignContentForEndTagRecovery() {
		self.popForeignContentUntilIntegrationPoint(stopAtMathMLTextIntegrationPoint: false)
	}

	private func popForeignContentForStartTagBreakout() {
		self.popForeignContentUntilIntegrationPoint(stopAtMathMLTextIntegrationPoint: true)
	}

	private func popForeignContentUntilIntegrationPoint(stopAtMathMLTextIntegrationPoint: Bool) {
		self.popUntilCurrentElement { current in
			guard let ns = current.namespace, ns == .svg || ns == .math else {
				return true
			}
			if self.isSVGHtmlIntegrationPoint(current) {
				return true
			}
			return stopAtMathMLTextIntegrationPoint && self.isMathMLTextIntegrationPoint(current)
		}
	}

	private func isSVGHtmlIntegrationPoint(_ node: Node) -> Bool {
		node.namespace == .svg && self.isSVGIntegrationPointTag(node.tagId)
	}

	private func isMathMLTextIntegrationPoint(_ node: Node) -> Bool {
		node.namespace == .math && self.isMathMLTextIntegrationPointTag(node.tagId)
	}

	// MARK: - Rawtext and RCDATA Parsing

	private func parseRawtext(name: String, attrs: [String: String]) {
		self.insertElementAndSwitchToTextMode(name: name, attrs: attrs)
	}

	private func parseRCDATA(name: String, attrs: [String: String]) {
		self.insertElementAndSwitchToTextMode(name: name, attrs: attrs)
	}

	private func insertElementAndSwitchToTextMode(name: String, attrs: [String: String]) {
		_ = self.insertElement(name: name, attrs: attrs)
		self.originalInsertionMode = self.insertionMode
		self.insertionMode = .text
	}

	// MARK: - Insertion Mode Reset

	private func initialInsertionModeForFragmentContext(_ name: String) -> InsertionMode {
		switch name {
			case "select":
				// Per html5lib behavior: select fragments use inBody mode, not inSelect.
				// This allows unknown elements to be inserted inside select context.
				return .inBody

			case "td", "th":
				return .inBody // For fragment parsing, treat as inBody
			case "tr":
				return .inRow

			case "tbody", "thead", "tfoot":
				return .inTableBody

			case "caption":
				return .inCaption

			case "colgroup":
				return .inColumnGroup

			case "table":
				return .inTable

			case "template":
				return .inTemplate

			case "head", "body":
				return .inBody // For fragment parsing, treat head as inBody

			case "frameset":
				return .inFrameset

			case "html":
				return .beforeHead

			default:
				return .inBody
		}
	}

	private func resetInsertionMode() {
		var last = false

		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			var node = self.openElements[i]
			if i == 0 {
				last = true
				if let ctx = contextElement {
					node = ctx
				}
			}

			// Per WHATWG spec: most reset checks only apply to HTML namespace elements
			let isHTML = self.isHTMLResetNode(node)

			switch self.resetInsertionModeDecision(for: node, at: i, last: last, isHTML: isHTML) {
				case .use(let mode):
					self.insertionMode = mode
					return
				case .continueSearch:
					break
				case .skipElement:
					continue
				case .stop:
					return
			}

			if last {
				self.insertionMode = .inBody
				return
			}
		}
	}

	private func resetInsertionModeDecision(
		for node: Node,
		at index: Int,
		last: Bool,
		isHTML: Bool
	) -> ResetInsertionModeDecision {
		switch node.tagId {
			case .select:
				guard isHTML else { return .skipElement }
				return .use(self.resetModeForSelect(at: index, last: last))

			case .td, .th:
				// Note: Per Python justhtml behavior, td/th match regardless of namespace
				// This allows IN_CELL mode when SVG elements with these names are on stack
				if !last {
					return .use(.inCell)
				}

			case .tr:
				// Note: Per Python justhtml behavior, tr matches regardless of namespace
				// This allows IN_ROW mode when SVG elements with tr name are on stack
				return .use(.inRow)

			case .tbody, .thead, .tfoot:
				if isHTML {
					return .use(.inTableBody)
				}

			case .caption:
				if isHTML {
					return .use(.inCaption)
				}

			case .colgroup:
				if isHTML {
					return .use(.inColumnGroup)
				}

			case .table:
				if isHTML {
					return .use(.inTable)
				}

			case .template:
				// Template doesn't check namespace per spec
				if let mode = templateInsertionModes.last {
					return .use(mode)
				}
				return .stop

			case .head:
				if !last, isHTML {
					return .use(.inHead)
				}

			case .body:
				if isHTML {
					return .use(.inBody)
				}

			case .frameset:
				if isHTML {
					return .use(.inFrameset)
				}

			case .html:
				if isHTML {
					return .use(self.resetModeForHtmlElement())
				}

			default:
				break
			}

		return .continueSearch
	}

	private func isHTMLResetNode(_ node: Node) -> Bool {
		self.isHTMLNamespace(node)
	}

	private func resetModeForSelect(at index: Int, last: Bool) -> InsertionMode {
		if last {
			// In fragment parsing, select context uses inBody (matching
			// resetInsertionModeForFragment). The select element is only
			// the virtual context element, not actually on the stack.
			return .inBody
		}
		return self.hasTableAncestorBeforeTemplate(startingBefore: index) ? .inSelectInTable : .inSelect
	}

	private func hasTableAncestorBeforeTemplate(startingBefore index: Int) -> Bool {
		guard index > 0 else { return false }

		for j in stride(from: index - 1, through: 0, by: -1) {
			let ancestor = self.openElements[j]
			if ancestor.tagId == .template {
				// Template breaks the chain - use inSelect
				return false
			}
			if ancestor.tagId == .table {
				return true
			}
		}
		return false
	}

	private func resetModeForHtmlElement() -> InsertionMode {
		self.headElement == nil ? .beforeHead : .afterHead
	}

	// MARK: - Utilities

	@inline(__always)
	private func isWhitespace(_ ch: Character) -> Bool {
		return ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}"
	}

	@inline(__always)
	private func scanTextForNullAndNonWhitespace(_ text: String) -> (hasNull: Bool, hasNonWhitespace: Bool) {
		var hasNonWhitespace = false

		for byte in text.utf8 {
			switch byte {
				case 0x00:
					return (true, hasNonWhitespace)

				case 0x09, 0x0A, 0x0C, 0x0D, 0x20:
					continue

				default:
					hasNonWhitespace = true
			}
		}

		return (false, hasNonWhitespace)
	}

	@inline(__always)
	private func containsNullByte(_ text: String) -> Bool {
		for byte in text.utf8 {
			if byte == 0x00 {
				return true
			}
		}
		return false
	}

	private func emitError(_ code: String) {
		if self.collectErrors {
			self.errors.append(
				ParseError(
					code: code,
					line: self.tokenizer?.currentLine,
					column: self.tokenizer?.currentColumn
				)
			)
		}
	}
}

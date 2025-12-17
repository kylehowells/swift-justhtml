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

// MARK: - Tag Name Sets (for fast O(1) lookups)

private let kTableSectionTags: Set<String> = ["tbody", "tfoot", "thead"]
private let kTableRowTags: Set<String> = ["tbody", "tfoot", "thead", "tr"]
private let kTableCellTags: Set<String> = ["td", "th"]
private let kTableRelatedTags: Set<String> = ["table", "tbody", "tfoot", "thead", "tr"]
private let kTableAllTags: Set<String> = ["table", "tbody", "tfoot", "thead", "tr", "td", "th"]
private let kTableBoundaryTags: Set<String> = ["caption", "table", "tbody", "tfoot", "thead", "tr", "td", "th"]
private let kHeadingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
private let kListItemTags: Set<String> = ["dd", "dt"]
private let kHeadMetaTags: Set<String> = ["base", "basefont", "bgsound", "link", "meta"]
private let kHeadStyleTags: Set<String> = ["noframes", "style"]
private let kTemplateScriptTags: Set<String> = ["script", "template"]
private let kVoidElementTags: Set<String> = ["area", "br", "embed", "img", "keygen", "wbr"]
private let kFormattingScope: Set<String> = ["applet", "marquee", "object"]
private let kBreakoutTags: Set<String> = ["head", "body", "html", "br"]
private let kTableContextTags: Set<String> = ["table", "template", "html"]
private let kTableBodyContextTags: Set<String> = ["tbody", "tfoot", "thead", "template", "html"]
private let kRowContextTags: Set<String> = ["tr", "template", "html"]
private let kSelectContentTags: Set<String> = ["input", "textarea"]
private let kOptionTags: Set<String> = ["optgroup", "option"]
private let kRubyBaseTags: Set<String> = ["rb", "rtc"]
private let kRubyTextTags: Set<String> = ["rp", "rt"]
private let kSVGIntegrationTags: Set<String> = ["foreignObject", "desc", "title"]
private let kMathMLIntegrationTags: Set<String> = ["mi", "mo", "mn", "ms", "mtext", "annotation-xml"]
private let kMediaTags: Set<String> = ["param", "source", "track"]
private let kFormElementTags: Set<String> = ["p", "div", "span", "button", "datalist", "selectedcontent", "menuitem"]
private let kHeadInBodyTags: Set<String> = ["basefont", "bgsound", "link", "meta", "noframes", "style"]
private let kHeadNoscriptTags: Set<String> = ["head", "noscript"]
private let kTableRowCellTags: Set<String> = ["td", "th", "tr"]
private let kTableCaptionTags: Set<String> = ["caption", "col", "colgroup", "tbody", "tfoot", "thead"]
private let kTableCaptionRowTags: Set<String> = ["caption", "col", "colgroup", "tbody", "tfoot", "thead", "tr"]
private let kTableAllCellTags: Set<String> = ["caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr"]
private let kTableCaptionGroupTags: Set<String> = ["caption", "colgroup", "tbody", "tfoot", "thead"]
private let kPreListingTags: Set<String> = ["pre", "listing"]
private let kAddressDivPTags: Set<String> = ["address", "div", "p"]
private let kBodyHtmlBrTags: Set<String> = ["body", "html", "br"]
private let kBodyCaptionHtmlTags: Set<String> = ["body", "caption", "col", "colgroup", "html"]
private let kBodyCaptionCellTags: Set<String> = ["body", "caption", "col", "colgroup", "html", "td", "th"]
private let kBodyCaptionRowTags: Set<String> = ["body", "caption", "col", "colgroup", "html", "td", "th", "tr"]

// MARK: - TagID Sets (fast integer comparisons)

private let kTableSectionTagIDs: Set<TagID> = [.tbody, .tfoot, .thead]
private let kTableRowTagIDs: Set<TagID> = [.tbody, .tfoot, .thead, .tr]
private let kTableCellTagIDs: Set<TagID> = [.td, .th]
private let kTableRelatedTagIDs: Set<TagID> = [.table, .tbody, .tfoot, .thead, .tr]
private let kTableAllTagIDs: Set<TagID> = [.table, .tbody, .tfoot, .thead, .tr, .td, .th]
private let kTableBoundaryTagIDs: Set<TagID> = [.caption, .table, .tbody, .tfoot, .thead, .tr, .td, .th]
private let kHeadingTagIDs: Set<TagID> = [.h1, .h2, .h3, .h4, .h5, .h6]
private let kListItemTagIDs: Set<TagID> = [.dd, .dt]
private let kHeadMetaTagIDs: Set<TagID> = [.base, .basefont, .bgsound, .link, .meta]
private let kHeadStyleTagIDs: Set<TagID> = [.noframes, .style]
private let kTemplateScriptTagIDs: Set<TagID> = [.script, .template]
private let kVoidElementTagIDs: Set<TagID> = [.area, .br, .embed, .img, .keygen, .wbr]
private let kFormattingScopeTagIDs: Set<TagID> = [.applet, .marquee, .object]
private let kBreakoutTagIDs: Set<TagID> = [.head, .body, .html, .br]
private let kTableContextTagIDs: Set<TagID> = [.table, .template, .html]
private let kTableBodyContextTagIDs: Set<TagID> = [.tbody, .tfoot, .thead, .template, .html]
private let kRowContextTagIDs: Set<TagID> = [.tr, .template, .html]
private let kSelectContentTagIDs: Set<TagID> = [.input, .textarea]
private let kOptionTagIDs: Set<TagID> = [.optgroup, .option]
private let kRubyBaseTagIDs: Set<TagID> = [.rb, .rtc]
private let kRubyTextTagIDs: Set<TagID> = [.rp, .rt]
private let kSVGIntegrationTagIDs: Set<TagID> = [.foreignObject, .desc, .title]
private let kMathMLIntegrationTagIDs: Set<TagID> = [.mi, .mo, .mn, .ms, .mtext, .annotationXml]
private let kMediaTagIDs: Set<TagID> = [.param, .source, .track]
private let kFormElementTagIDs: Set<TagID> = [.p, .div, .span, .button, .datalist, .selectedcontent, .menuitem]
private let kHeadInBodyTagIDs: Set<TagID> = [.basefont, .bgsound, .link, .meta, .noframes, .style]
private let kHeadNoscriptTagIDs: Set<TagID> = [.head, .noscript]
private let kTableRowCellTagIDs: Set<TagID> = [.td, .th, .tr]
private let kTableCaptionTagIDs: Set<TagID> = [.caption, .col, .colgroup, .tbody, .tfoot, .thead]
private let kTableCaptionRowTagIDs: Set<TagID> = [.caption, .col, .colgroup, .tbody, .tfoot, .thead, .tr]
private let kTableAllCellTagIDs: Set<TagID> = [.caption, .col, .colgroup, .tbody, .td, .tfoot, .th, .thead, .tr]
private let kTableCaptionGroupTagIDs: Set<TagID> = [.caption, .colgroup, .tbody, .tfoot, .thead]
private let kPreListingTagIDs: Set<TagID> = [.pre, .listing]
private let kAddressDivPTagIDs: Set<TagID> = [.address, .div, .p]
private let kBodyHtmlBrTagIDs: Set<TagID> = [.body, .html, .br]
private let kBodyCaptionHtmlTagIDs: Set<TagID> = [.body, .caption, .col, .colgroup, .html]
private let kBodyCaptionCellTagIDs: Set<TagID> = [.body, .caption, .col, .colgroup, .html, .td, .th]
private let kBodyCaptionRowTagIDs: Set<TagID> = [.body, .caption, .col, .colgroup, .html, .td, .th, .tr]

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

	/// Pending table character tokens
	private var pendingTableCharacterTokens: String = ""

	// Error collection
	public var errors: [ParseError] = []
	private var collectErrors: Bool

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
		scripting: Bool = false
	) {
		self.fragmentContext = fragmentContext
		self.iframeSrcdoc = iframeSrcdoc
		self.collectErrors = collectErrors
		self.scripting = scripting

		if fragmentContext != nil {
			self.document = Node(name: "#document-fragment")
		}
		else {
			self.document = Node(name: "#document")
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

		switch ctx.name {
			case "select":
				// Per html5lib behavior: select fragments use inBody mode, not inSelect
				// This allows unknown elements to be inserted inside select context
				self.insertionMode = .inBody

			case "td", "th":
				self.insertionMode = .inBody // For fragment parsing, treat as inBody
			case "tr":
				self.insertionMode = .inRow

			case "tbody", "thead", "tfoot":
				self.insertionMode = .inTableBody

			case "caption":
				self.insertionMode = .inCaption

			case "colgroup":
				self.insertionMode = .inColumnGroup

			case "table":
				self.insertionMode = .inTable

			case "template":
				self.insertionMode = .inTemplate

			case "head":
				self.insertionMode = .inBody // For fragment parsing, treat as inBody
			case "body":
				self.insertionMode = .inBody

			case "frameset":
				self.insertionMode = .inFrameset

			case "html":
				self.insertionMode = .beforeHead

			default:
				self.insertionMode = .inBody
		}
	}

	/// Finish parsing and return the root
	public func finish() -> Node {
		// Populate selectedcontent elements with content from selected option
		self.populateSelectedcontent(self.document)
		return self.document
	}

	/// Populate selectedcontent elements with content from the selected option
	/// Per HTML5 spec: selectedcontent mirrors the content of the selected option,
	/// or the first option if none is selected.
	private func populateSelectedcontent(_ root: Node) {
		// Find all select elements
		var selects: [Node] = []
		self.findElements(root, name: "select", result: &selects)

		for select in selects {
			// Find selectedcontent element in this select
			guard let selectedcontent = findElement(select, name: "selectedcontent") else {
				continue
			}

			// Find all option elements
			var options: [Node] = []
			self.findElements(select, name: "option", result: &options)
			if options.isEmpty {
				continue
			}

			// Find selected option or use first one
			var selectedOption: Node? = nil
			for opt in options {
				if opt.attrs["selected"] != nil {
					selectedOption = opt
					break
				}
			}
			if selectedOption == nil {
				selectedOption = options.first
			}

			// Clone content from selected option to selectedcontent
			if let source = selectedOption {
				self.cloneChildren(from: source, to: selectedcontent)
			}
		}
	}

	/// Recursively find all elements with given name
	private func findElements(_ node: Node, name: String, result: inout [Node]) {
		if node.name == name {
			result.append(node)
		}
		for child in node.children {
			self.findElements(child, name: name, result: &result)
		}
		// Also search in template content
		if let content = node.templateContent {
			for child in content.children {
				self.findElements(child, name: name, result: &result)
			}
		}
	}

	/// Find first element with given name
	private func findElement(_ node: Node, name: String) -> Node? {
		if node.name == name {
			return node
		}
		for child in node.children {
			if let found = findElement(child, name: name) {
				return found
			}
		}
		// Also search in template content
		if let content = node.templateContent {
			for child in content.children {
				if let found = findElement(child, name: name) {
					return found
				}
			}
		}
		return nil
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
			// Check if text contains any null characters
			if !text.contains("\0") {
				self.reconstructActiveFormattingElements()
				self.insertText(text)
				// Set framesetOk = false if there's any non-whitespace
				for ch in text {
					if !self.isWhitespace(ch) {
						self.framesetOk = false
						break
					}
				}
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
			if ch == "\0" {
				self.emitError("unexpected-null-character")
				// Drop null character
			}
			else if ch == "\u{0C}" {
				// Form feed is invalid in integration points - emit error and drop
				self.emitError("invalid-codepoint")
			}
			else if self.isWhitespace(ch) {
				self.reconstructActiveFormattingElements()
				self.insertCharacter(ch)
			}
			else {
				self.reconstructActiveFormattingElements()
				self.insertCharacter(ch)
				self.framesetOk = false
			}
			return
		}

		// Check for foreign content - process characters according to foreign content rules
		if self.shouldProcessInForeignContent() {
			if ch == "\0" {
				self.emitError("unexpected-null-character")
				self.insertCharacter("\u{FFFD}")
			}
			else if ch == "\u{0C}" {
				// Form feed is invalid in foreign content - emit error and drop
				self.emitError("invalid-codepoint")
			}
			else {
				self.insertCharacter(ch)
				if !self.isWhitespace(ch) {
					self.framesetOk = false
				}
			}
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
				if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else if self.isWhitespace(ch) {
					self.reconstructActiveFormattingElements()
					self.insertCharacter(ch)
				}
				else {
					self.reconstructActiveFormattingElements()
					self.insertCharacter(ch)
					self.framesetOk = false
				}

			case .text:
				self.insertCharacter(ch)

			case .afterBody:
				if self.isWhitespace(ch) {
					// Process as in body
					self.insertCharacter(ch)
				}
				else {
					self.emitError("unexpected-char-after-body")
					self.insertionMode = .inBody
					self.processCharacter(ch)
				}

			case .afterAfterBody:
				if self.isWhitespace(ch) {
					// Process as in body
					self.insertCharacter(ch)
				}
				else {
					self.emitError("unexpected-char-after-body")
					self.insertionMode = .inBody
					self.processCharacter(ch)
				}

			case .inFrameset:
				if self.isWhitespace(ch) {
					self.insertCharacter(ch)
				}
				else if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else {
					self.emitError("unexpected-char-in-frameset")
					// Ignore
				}

			case .afterFrameset:
				if self.isWhitespace(ch) {
					self.insertCharacter(ch)
				}
				else if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else {
					self.emitError("unexpected-char-after-frameset")
					// Ignore
				}

			case .afterAfterFrameset:
				if self.isWhitespace(ch) {
					// Process as in body
					self.insertCharacter(ch)
				}
				else if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else {
					self.emitError("unexpected-char-after-frameset")
					// Ignore
				}

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
				// Switch to inTableText mode and buffer characters
				if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else if ch == "\u{0C}" {
					// Form feed is invalid in table text - emit error and drop
					self.emitError("invalid-codepoint-in-table-text")
				}
				else {
					self.pendingTableCharacterTokens.append(ch)
					self.originalInsertionMode = self.insertionMode
					self.insertionMode = .inTableText
				}

			case .inTableText:
				// Buffer characters in table text mode
				if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else if ch == "\u{0C}" {
					// Form feed is invalid in table text - emit error and drop
					self.emitError("invalid-codepoint-in-table-text")
				}
				else {
					self.pendingTableCharacterTokens.append(ch)
				}

			case .inCell, .inCaption:
				// Process using inBody rules
				if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else if self.isWhitespace(ch) {
					self.reconstructActiveFormattingElements()
					self.insertCharacter(ch)
				}
				else {
					self.reconstructActiveFormattingElements()
					self.insertCharacter(ch)
					self.framesetOk = false
				}

			case .inSelect, .inSelectInTable:
				// Characters in select go directly into the select
				if ch == "\0" {
					self.emitError("unexpected-null-character")
				}
				else if ch == "\u{0C}" {
					// Form feed is invalid in select - emit error and drop
					self.emitError("invalid-codepoint-in-select")
				}
				else {
					// Reconstruct active formatting elements for proper formatting element handling
					self.reconstructActiveFormattingElements()
					self.insertCharacter(ch)
				}

			default:
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

		// Check if all characters are whitespace
		let allWhitespace = self.pendingTableCharacterTokens.allSatisfy { self.isWhitespace($0) }

		if allWhitespace {
			// Insert whitespace normally into the table
			for ch in self.pendingTableCharacterTokens {
				self.insertCharacter(ch)
			}
		}
		else {
			// Foster parent all characters (including whitespace)
			self.emitError("unexpected-char-in-table")
			self.fosterParentingEnabled = true
			for ch in self.pendingTableCharacterTokens {
				self.reconstructActiveFormattingElements()
				self.insertCharacter(ch)
				if !self.isWhitespace(ch) {
					self.framesetOk = false
				}
			}
			self.fosterParentingEnabled = false
		}

		self.pendingTableCharacterTokens = ""
		self.insertionMode = self.originalInsertionMode
	}

	private func processStartTag(name: String, attrs: [String: String], selfClosing: Bool) {
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
			let isTableMode = [
				InsertionMode.inTable, .inTableBody, .inRow, .inCell, .inCaption, .inColumnGroup,
			].contains(self.insertionMode)
			if isTableMode, !self.hasElementInTableScope(.table) {
				// Temporarily use IN_BODY mode for this tag
				let savedMode = self.insertionMode
				self.insertionMode = .inBody
				self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				// Restore mode if no mode change was requested
				if self.insertionMode == .inBody {
					self.insertionMode = savedMode
				}
				return
			}
		}

		switch self.insertionMode {
			case .initial:
				// Parse error - start tag in initial mode sets quirks mode
				self.emitError("expected-doctype-but-got-start-tag")
				self.quirksMode = true
				self.insertionMode = .beforeHtml
				self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)

			case .beforeHtml:
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

			case .beforeHead:
				if name == "html" {
					// Merge attributes
					if let html = openElements.first {
						for (key, value) in attrs where html.attrs[key] == nil {
							html.attrs[key] = value
						}
					}
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

			case .inHead:
				if name == "html" {
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if kHeadMetaTags.contains(name) {
					_ = self.insertElement(name: name, attrs: attrs)
					self.popCurrentElement()
				}
				else if name == "title" {
					self.parseRCDATA(name: name, attrs: attrs)
				}
				else if name == "noscript" {
					if self.scripting {
						self.parseRawtext(name: name, attrs: attrs)
					}
					else {
						_ = self.insertElement(name: name, attrs: attrs)
						self.insertionMode = .inHeadNoscript
					}
				}
				else if kHeadStyleTags.contains(name) {
					self.parseRawtext(name: name, attrs: attrs)
				}
				else if name == "script" {
					self.parseRawtext(name: name, attrs: attrs)
				}
				else if name == "template" {
					// Insert template element
					let element = self.insertElement(name: name, attrs: attrs)
					// Create content document fragment
					element.templateContent = Node(name: "#document-fragment")
					// Push onto template modes stack
					self.templateInsertionModes.append(.inTemplate)
					self.insertionMode = .inTemplate
				}
				else if name == "head" {
					self.emitError("unexpected-start-tag")
				}
				else {
					self.popCurrentElement() // head
					self.insertionMode = .afterHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .inHeadNoscript:
				if name == "html" {
					// Process using in body rules (merge attributes)
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if kHeadInBodyTags.contains(name) {
					// Process using in head rules
					let savedMode = self.insertionMode
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					// If parseRawtext switched to text mode, update originalInsertionMode
					if self.insertionMode == .text {
						self.originalInsertionMode = savedMode
					}
					else {
						self.insertionMode = savedMode
					}
				}
				else if kHeadNoscriptTags.contains(name) {
					self.emitError("unexpected-start-tag")
				}
				else {
					// Pop noscript and reprocess
					self.emitError("unexpected-start-tag")
					self.popCurrentElement()
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .afterHead:
				if name == "html" {
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "body" {
					let element = self.insertElement(name: name, attrs: attrs)
					self.bodyElement = element
					self.framesetOk = false
					self.insertionMode = .inBody
				}
				else if name == "frameset" {
					_ = self.insertElement(name: name, attrs: attrs)
					self.insertionMode = .inFrameset
				}
				else if [
					"base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template",
					"title",
				].contains(name) {
					self.emitError("unexpected-start-tag")
					if let head = headElement {
						self.openElements.append(head)
					}
					// Process using "in head" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					// If parseRawtext/parseRCDATA switched to .text mode, update originalInsertionMode
					// so the end tag returns to afterHead, not inHead
					// Also don't reset if template set us to inTemplate mode
					if self.insertionMode == .text {
						self.originalInsertionMode = savedMode
					}
					else if self.insertionMode != .inTemplate {
						self.insertionMode = savedMode
					}
					if let idx = openElements.lastIndex(where: { $0 === headElement }) {
						self.openElements.remove(at: idx)
					}
				}
				else if name == "head" {
					self.emitError("unexpected-start-tag")
				}
				else {
					self.insertBodyElement()
					self.insertionMode = .inBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .inBody:
				self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)

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
				}
				else {
					self.emitError("unexpected-start-tag-after-body")
					self.insertionMode = .inBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .afterAfterBody:
				if name == "html" {
					// Merge attributes
					if let html = openElements.first {
						for (key, value) in attrs where html.attrs[key] == nil {
							html.attrs[key] = value
						}
					}
				}
				else {
					self.emitError("unexpected-start-tag-after-body")
					self.insertionMode = .inBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .inTable:
				if name == "caption" {
					self.clearStackBackToTableContext()
					self.insertMarker()
					_ = self.insertElement(name: name, attrs: attrs)
					self.insertionMode = .inCaption
				}
				else if name == "colgroup" {
					self.clearStackBackToTableContext()
					_ = self.insertElement(name: name, attrs: attrs)
					self.insertionMode = .inColumnGroup
				}
				else if name == "col" {
					self.clearStackBackToTableContext()
					_ = self.insertElement(name: "colgroup", attrs: [:])
					self.insertionMode = .inColumnGroup
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if kTableSectionTags.contains(name) {
					self.clearStackBackToTableContext()
					_ = self.insertElement(name: name, attrs: attrs)
					self.insertionMode = .inTableBody
				}
				else if kTableRowCellTags.contains(name) {
					self.clearStackBackToTableContext()
					_ = self.insertElement(name: "tbody", attrs: [:])
					self.insertionMode = .inTableBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "table" {
					self.emitError("unexpected-start-tag-implies-end-tag")
					if self.hasElementInTableScope(.table) {
						self.popUntil("table")
						self.resetInsertionMode()
						self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					}
				}
				else if kTemplateScriptTags.contains(name) || name == "style" {
					// Process using "in head" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .text {
						self.originalInsertionMode = savedMode
					}
					else if self.insertionMode != .inTemplate {
						// Don't restore if we're now in template mode
						self.insertionMode = savedMode
					}
				}
				else if name == "input" {
					if attrs["type"]?.lowercased() == "hidden" {
						self.emitError("unexpected-hidden-input-in-table")
						_ = self.insertElement(name: name, attrs: attrs)
						self.popCurrentElement()
					}
					else {
						// Foster parenting - insert in body instead
						self.emitError("unexpected-start-tag-in-table")
						self.fosterParentingEnabled = true
						self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
						self.fosterParentingEnabled = false
					}
				}
				else if name == "form" {
					self.emitError("unexpected-start-tag-in-table")
					if self.formElement == nil, !self.hasElementInScope(.template) {
						let element = self.insertElement(name: name, attrs: attrs)
						self.formElement = element
						self.popCurrentElement()
					}
				}
				else {
					// Foster parenting - process using "in body" rules
					self.emitError("unexpected-start-tag-in-table")
					self.fosterParentingEnabled = true
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
					self.fosterParentingEnabled = false
				}

			case .inTableBody:
				if name == "tr" {
					self.clearStackBackToTableBodyContext()
					_ = self.insertElement(name: name, attrs: attrs)
					self.insertionMode = .inRow
				}
				else if kTableCellTags.contains(name) {
					self.emitError("unexpected-cell-in-table-body")
					self.clearStackBackToTableBodyContext()
					_ = self.insertElement(name: "tr", attrs: [:])
					self.insertionMode = .inRow
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if kTableCaptionTags.contains(name) {
					if !self.hasElementInTableScope(.tbody), !self.hasElementInTableScope(.thead),
					   !self.hasElementInTableScope(.tfoot)
					{
						self.emitError("unexpected-start-tag")
						return
					}
					self.clearStackBackToTableBodyContext()
					self.popCurrentElement()
					self.insertionMode = .inTable
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "table" {
					// Nested table - close current table and insert new one
					// Don't restore mode since we're creating a completely new table context
					self.emitError("unexpected-start-tag-implies-end-tag")
					if self.hasElementInTableScope(.table) {
						self.popUntil("table")
						self.resetInsertionMode()
						self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					}
				}
				else {
					// Process using "in table" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inTable
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .inTable {
						self.insertionMode = savedMode
					}
				}

			case .inRow:
				if kTableCellTags.contains(name) {
					self.clearStackBackToTableRowContext()
					_ = self.insertElement(name: name, attrs: attrs)
					self.insertionMode = .inCell
					self.insertMarker()
				}
				else if kTableCaptionRowTags.contains(name) {
					if !self.hasElementInTableScope(.tr) {
						self.emitError("unexpected-start-tag")
						return
					}
					self.clearStackBackToTableRowContext()
					self.popCurrentElement()
					self.insertionMode = .inTableBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "table" {
					// Nested table - close current table and insert new one
					// Don't restore mode since we're creating a completely new table context
					self.emitError("unexpected-start-tag-implies-end-tag")
					if self.hasElementInTableScope(.table) {
						self.popUntil("table")
						self.resetInsertionMode()
						self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					}
				}
				else {
					// Process using "in table" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inTable
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .inTable {
						self.insertionMode = savedMode
					}
				}

			case .inCell:
				if kTableAllCellTags.contains(name)
				{
					if !self.hasElementInTableScope(.td), !self.hasElementInTableScope(.th) {
						self.emitError("unexpected-start-tag")
						return
					}
					self.closeCell()
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else {
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .inColumnGroup:
				if name == "html" {
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "col" {
					_ = self.insertElement(name: name, attrs: attrs)
					self.popCurrentElement()
				}
				else if name == "template" {
					// Process using "in head" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .text {
						self.originalInsertionMode = savedMode
					}
					else if self.insertionMode != .inTemplate {
						self.insertionMode = savedMode
					}
				}
				else {
					// Close colgroup and reprocess
					if self.currentNode?.tagId == .colgroup {
						self.popCurrentElement()
						self.insertionMode = .inTable
						self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					}
					else {
						self.emitError("unexpected-start-tag")
					}
				}

			case .inCaption:
				// Table structure tags close the caption
				if ["caption", "col", "colgroup", "table", "tbody", "td", "tfoot", "th", "thead", "tr"]
					.contains(name)
				{
					self.emitError("unexpected-start-tag-implies-end-tag")
					if !self.hasElementInTableScope(.caption) {
						// Fragment parsing - no caption on stack
						if name == "table" {
							// Handle in body mode for <table>
							self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
						}
						// Ignore other table structure elements
						return
					}
					self.generateImpliedEndTags()
					if self.currentNode?.tagId != .caption {
						self.emitError("end-tag-too-early")
					}
					self.popUntil("caption")
					self.clearActiveFormattingElementsToLastMarker()
					self.insertionMode = .inTable
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else {
					// Process using inBody rules
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .inFrameset:
				if name == "html" {
					// Process using in body rules per WHATWG spec
					self.insertionMode = .inBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					return
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

			case .afterFrameset:
				if name == "html" {
					// Process using in body rules per WHATWG spec
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "noframes" {
					self.parseRawtext(name: name, attrs: attrs)
				}
				else {
					self.emitError("unexpected-start-tag-after-frameset")
				}

			case .afterAfterFrameset:
				if name == "html" {
					// Process using in body rules per WHATWG spec
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "noframes" {
					self.parseRawtext(name: name, attrs: attrs)
				}
				else {
					self.emitError("unexpected-start-tag-after-frameset")
				}

			case .inTemplate:
				// Handle start tags in "in template" insertion mode
				if [
					"base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template",
					"title",
				].contains(name) {
					// Process using "in head" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .text {
						self.originalInsertionMode = savedMode
					}
					else {
						self.insertionMode = savedMode
					}
				}
				else if kTableCaptionGroupTags.contains(name) {
					// Pop template mode and push inTable
					if !self.templateInsertionModes.isEmpty {
						self.templateInsertionModes.removeLast()
					}
					self.templateInsertionModes.append(.inTable)
					self.insertionMode = .inTable
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "col" {
					// Pop template mode and push inColumnGroup
					if !self.templateInsertionModes.isEmpty {
						self.templateInsertionModes.removeLast()
					}
					self.templateInsertionModes.append(.inColumnGroup)
					self.insertionMode = .inColumnGroup
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "tr" {
					// Pop template mode and push inTableBody
					if !self.templateInsertionModes.isEmpty {
						self.templateInsertionModes.removeLast()
					}
					self.templateInsertionModes.append(.inTableBody)
					self.insertionMode = .inTableBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if kTableCellTags.contains(name) {
					// Pop template mode and push inRow
					if !self.templateInsertionModes.isEmpty {
						self.templateInsertionModes.removeLast()
					}
					self.templateInsertionModes.append(.inRow)
					self.insertionMode = .inRow
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else {
					// Pop template mode and push inBody
					if !self.templateInsertionModes.isEmpty {
						self.templateInsertionModes.removeLast()
					}
					self.templateInsertionModes.append(.inBody)
					self.insertionMode = .inBody
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}

			case .inSelect:
				if name == "html" {
					// Process using "in body" rules
					self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if name == "option" {
					if let current = currentNode, current.name == "option" {
						self.popCurrentElement()
					}
					self.reconstructActiveFormattingElements()
					_ = self.insertElement(name: name, attrs: attrs)
				}
				else if name == "optgroup" {
					if let current = currentNode, current.name == "option" {
						self.popCurrentElement()
					}
					if let current = currentNode, current.name == "optgroup" {
						self.popCurrentElement()
					}
					_ = self.insertElement(name: name, attrs: attrs)
				}
				else if name == "hr" || name == "keygen" {
					// hr and keygen are inserted inside select as self-closing elements
					if let current = currentNode, current.name == "option" {
						self.popCurrentElement()
					}
					if let current = currentNode, current.name == "optgroup" {
						self.popCurrentElement()
					}
					_ = self.insertElement(name: name, attrs: attrs)
					self.popCurrentElement()
				}
				else if name == "plaintext" {
					// plaintext is inserted and switches tokenizer to plaintext mode
					if let current = currentNode, current.name == "option" {
						self.popCurrentElement()
					}
					if let current = currentNode, current.name == "optgroup" {
						self.popCurrentElement()
					}
					_ = self.insertElement(name: name, attrs: attrs)
					self.tokenizer?.switchToPlaintext()
				}
				else if name == "select" {
					self.emitError("unexpected-start-tag-in-select")
					// Per browser behavior, check if select is anywhere on the stack, not using strict scope
					if self.openElements.contains(where: { $0.name == "select" }) {
						self.popUntil("select")
						self.resetInsertionMode()
					}
				}
				else if kSelectContentTags.contains(name) {
					self.emitError("unexpected-start-tag-in-select")
					if !self.hasElementInSelectScope("select") {
						// Ignore the token
						return
					}
					// In fragment parsing, if select is only the context element,
					// we conceptually close it by clearing the context and going to inBody
					let selectIsContextOnly =
						self.contextElement?.name == "select"
							&& !self.openElements.contains { $0.name == "select" }
					if selectIsContextOnly {
						self.contextElement = nil
						// Go directly to inBody without creating implicit head/body
						self.insertionMode = .inBody
					}
					else {
						self.popUntil("select")
						self.resetInsertionMode()
					}
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else if kTemplateScriptTags.contains(name) {
					// Process using "in head" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inHead
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .text {
						// Script processing set up text mode, update originalInsertionMode to return to select
						self.originalInsertionMode = savedMode
					}
					else if self.insertionMode != .inTemplate {
						// Restore unless template took us to inTemplate mode
						self.insertionMode = savedMode
					}
				}
				else if name == "svg" {
					// Insert SVG element in SVG namespace
					let adjustedAttrs = self.adjustForeignAttributes(attrs, namespace: .svg)
					_ = self.insertElement(name: name, namespace: .svg, attrs: adjustedAttrs)
					if selfClosing {
						self.popCurrentElement()
					}
				}
				else if name == "math" {
					// Insert MathML element in MathML namespace
					let adjustedAttrs = self.adjustForeignAttributes(attrs, namespace: .math)
					_ = self.insertElement(name: name, namespace: .math, attrs: adjustedAttrs)
					if selfClosing {
						self.popCurrentElement()
					}
				}
				else if FORMATTING_ELEMENTS.contains(name.lowercased()) {
					// Handle formatting elements in select mode
					// Per HTML5 spec: reconstruct, insert, and add to active formatting
					self.reconstructActiveFormattingElements()
					let element = self.insertElement(name: name, attrs: attrs)
					self.pushFormattingElement(element)
				}
				else if kFormElementTags.contains(
					name.lowercased())
				{
					// Per HTML5 spec: these elements are allowed inside select
					self.reconstructActiveFormattingElements()
					_ = self.insertElement(name: name, attrs: attrs)
					if selfClosing {
						self.popCurrentElement()
					}
				}
				else if name.lowercased() == "br" || name.lowercased() == "img" {
					// Per HTML5 spec: br and img are inserted as void elements in select
					self.reconstructActiveFormattingElements()
					_ = self.insertElement(name: name, attrs: attrs)
					self.popCurrentElement()
				}
				else if [
					"caption", "col", "colgroup", "table", "tbody", "td", "tfoot", "th", "thead", "tr",
				]
				.contains(name.lowercased()) {
					// Per WHATWG spec: table structure elements close the select and reprocess
					self.emitError("unexpected-start-tag-implies-end-tag")
					// In fragment parsing, if select is only the context element,
					// we conceptually close it by clearing the context and going to inBody
					let selectIsContextOnly =
						self.contextElement?.name == "select"
							&& !self.openElements.contains { $0.name == "select" }
					if selectIsContextOnly {
						self.contextElement = nil
						self.insertionMode = .inBody
					}
					else {
						self.popUntil("select")
						self.resetInsertionMode()
					}
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else {
					// Per HTML5 spec: unknown elements in inSelect mode are ignored
					// (fragment parsing uses inBody mode which allows insertion)
					self.emitError("unexpected-start-tag-in-select")
				}

			case .inSelectInTable:
				// Table-related start tags close the select and reprocess
				if kTableBoundaryTags.contains(name) {
					self.emitError("unexpected-start-tag-in-select")
					// In fragment parsing, if select is only the context element,
					// we conceptually close it by clearing the context and going to inBody
					let selectIsContextOnly =
						self.contextElement?.name == "select"
							&& !self.openElements.contains { $0.name == "select" }
					if selectIsContextOnly {
						self.contextElement = nil
						self.insertionMode = .inBody
					}
					else {
						self.popUntil("select")
						self.resetInsertionMode()
					}
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
				}
				else {
					// Process using "in select" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inSelect
					self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
					if self.insertionMode == .inSelect {
						self.insertionMode = savedMode
					}
				}

			default:
				self.processStartTagInBody(name: name, attrs: attrs, selfClosing: selfClosing)
		}
	}

	private func processStartTagInBody(name: String, attrs: [String: String], selfClosing: Bool) {
		if name == "html" {
			self.emitError("unexpected-start-tag")
			// Don't merge attributes if inside a template
			if self.templateInsertionModes.isEmpty, let html = openElements.first {
				for (key, value) in attrs where html.attrs[key] == nil {
					html.attrs[key] = value
				}
			}
		}
		else if [
			"base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template",
			"title",
		].contains(name) || (name == "noscript" && self.scripting) {
			// Process using "in head" rules
			let savedMode = self.insertionMode
			self.insertionMode = .inHead
			self.processStartTag(name: name, attrs: attrs, selfClosing: selfClosing)
			// If parseRawtext/parseRCDATA switched to .text mode, update originalInsertionMode
			if self.insertionMode == .text {
				self.originalInsertionMode = savedMode
			}
			else if self.insertionMode != .inTemplate {
				// Don't restore if we're now in template mode
				self.insertionMode = savedMode
			}
		}
		else if name == "body" {
			self.emitError("unexpected-start-tag")
			// Don't merge attributes if inside a template
			if self.templateInsertionModes.isEmpty,
			   self.openElements.count >= 2, self.openElements[1].name == "body"
			{
				self.framesetOk = false
				for (key, value) in attrs where self.openElements[1].attrs[key] == nil {
					openElements[1].attrs[key] = value
				}
			}
		}
		else if name == "frameset" {
			self.emitError("unexpected-start-tag")
			// Check conditions for allowing frameset
			if self.openElements.count > 1, self.openElements[1].name == "body", self.framesetOk {
				// Remove the body element from its parent
				if let body = openElements.count > 1 ? openElements[1] : nil {
					body.parent?.removeChild(body)
				}
				// Pop all nodes except html
				while self.openElements.count > 1 {
					self.popCurrentElement()
				}
				// Insert frameset
				_ = self.insertElement(name: name, attrs: attrs)
				self.insertionMode = .inFrameset
			}
			// Otherwise ignore
		}
		else if [
			"address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div",
			"dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "main", "menu", "nav",
			"ol", "p", "search", "section", "summary", "ul",
		].contains(name) {
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if kHeadingTags.contains(name) {
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			if let current = currentNode, kHeadingTags.contains(current.name) {
				self.emitError("unexpected-start-tag")
				self.popCurrentElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if kPreListingTags.contains(name) {
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
			self.framesetOk = false
			self.skipNextNewline = true // Ignore first newline after pre/listing
		}
		else if name == "form" {
			if self.formElement != nil {
				self.emitError("unexpected-start-tag")
			}
			else {
				if self.hasElementInButtonScope(.p) {
					self.closePElement()
				}
				let element = self.insertElement(name: name, attrs: attrs)
				self.formElement = element
			}
		}
		else if name == "li" {
			self.framesetOk = false
			// Close any open li elements in list item scope
			for node in self.openElements.reversed() {
				if node.name == "li" {
					self.generateImpliedEndTags(except: "li")
					if self.currentNode?.tagId != .li {
						self.emitError("end-tag-too-early")
					}
					self.popUntil("li")
					break
				}
				// Stop at list item scope boundary elements
				if LIST_ITEM_SCOPE_ELEMENTS.contains(node.name) {
					break
				}
			}
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if kListItemTags.contains(name) {
			self.framesetOk = false
			// Close any open dd or dt elements in scope
			// Per spec: stop at special elements EXCEPT address, div, and p
			for node in self.openElements.reversed() {
				if node.name == "dd" || node.name == "dt" {
					self.generateImpliedEndTags(except: node.name)
					if self.currentNode?.name != node.name {
						self.emitError("end-tag-too-early")
					}
					self.popUntil(node.name)
					break
				}
				// Stop at special elements, but NOT address, div, or p
				if SPECIAL_ELEMENTS.contains(node.name),
				   !kAddressDivPTags.contains(node.name)
				{
					break
				}
			}
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if name == "plaintext" {
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
			// Switch tokenizer to PLAINTEXT state
		}
		else if name == "button" {
			if self.hasElementInScope(.button) {
				self.emitError("unexpected-start-tag")
				self.generateImpliedEndTags()
				self.popUntil("button")
			}
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
			self.framesetOk = false
		}
		else if name == "a" {
			// Check for active 'a' element and run adoption agency if found
			if self.hasActiveFormattingEntry("a") {
				self.emitError("unexpected-start-tag")
				self.adoptionAgency(name: "a")
				// Also remove from active formatting elements and open elements
				// (adoption agency may have already done this, but be safe)
				for i in stride(from: self.activeFormattingElements.count - 1, through: 0, by: -1) {
					if let elem = activeFormattingElements[i], elem.name == "a" {
						self.activeFormattingElements.remove(at: i)
						self.openElements.removeAll { $0 === elem }
						break
					}
				}
			}
			self.reconstructActiveFormattingElements()
			let element = self.insertElement(name: name, attrs: attrs)
			self.pushFormattingElement(element)
		}
		else if name == "nobr" {
			// Special handling for nobr - must check scope BEFORE other formatting elements logic
			if self.hasElementInScope(.nobr) {
				self.emitError("unexpected-start-tag-implies-end-tag")
				// Run adoption agency to close the existing nobr
				self.adoptionAgency(name: "nobr")
				// Explicitly remove nobr from active formatting and open elements
				for i in stride(from: self.activeFormattingElements.count - 1, through: 0, by: -1) {
					if let elem = activeFormattingElements[i], elem.name == "nobr" {
						self.activeFormattingElements.remove(at: i)
						self.openElements.removeAll { $0 === elem }
						break
					}
				}
			}
			self.reconstructActiveFormattingElements()
			let element = self.insertElement(name: name, attrs: attrs)
			self.pushFormattingElement(element)
		}
		else if FORMATTING_ELEMENTS.contains(name) {
			self.reconstructActiveFormattingElements()
			let element = self.insertElement(name: name, attrs: attrs)
			self.pushFormattingElement(element)
		}
		else if kFormattingScope.contains(name) {
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
			self.insertMarker()
			self.framesetOk = false
		}
		else if name == "table" {
			// Only close p element if NOT in quirks mode
			if !self.quirksMode, self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
			self.framesetOk = false
			self.insertionMode = .inTable
		}
		else if kVoidElementTags.contains(name) {
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
			self.popCurrentElement()
			self.framesetOk = false
		}
		else if name == "input" {
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
			self.popCurrentElement()
			if attrs["type"]?.lowercased() != "hidden" {
				self.framesetOk = false
			}
		}
		else if kMediaTags.contains(name) {
			_ = self.insertElement(name: name, attrs: attrs)
			self.popCurrentElement()
		}
		else if name == "hr" {
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			_ = self.insertElement(name: name, attrs: attrs)
			self.popCurrentElement()
			self.framesetOk = false
		}
		else if name == "image" {
			self.emitError("unexpected-start-tag")
			// Treat as "img"
			self.processStartTag(name: "img", attrs: attrs, selfClosing: selfClosing)
		}
		else if name == "textarea" {
			_ = self.insertElement(name: name, attrs: attrs)
			self.skipNextNewline = true // Ignore first newline after textarea
			self.framesetOk = false
			self.originalInsertionMode = self.insertionMode
			self.insertionMode = .text
		}
		else if name == "xmp" {
			if self.hasElementInButtonScope(.p) {
				self.closePElement()
			}
			self.reconstructActiveFormattingElements()
			self.framesetOk = false
			self.parseRawtext(name: name, attrs: attrs)
		}
		else if name == "iframe" {
			self.framesetOk = false
			self.parseRawtext(name: name, attrs: attrs)
		}
		else if name == "noembed" {
			self.parseRawtext(name: name, attrs: attrs)
		}
		else if name == "select" {
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
			// Insert marker to prevent reconstruction of formatting elements from outside select
			self.insertMarker()
			self.framesetOk = false
			// Check if we're in a table context
			if self.insertionMode == .inTable || self.insertionMode == .inTableBody
				|| self.insertionMode == .inRow || self.insertionMode == .inCell
				|| self.insertionMode == .inCaption
			{
				self.insertionMode = .inSelectInTable
			}
			else {
				self.insertionMode = .inSelect
			}
		}
		else if kOptionTags.contains(name) {
			if self.currentNode?.tagId == .option {
				self.popCurrentElement()
			}
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if kRubyBaseTags.contains(name) {
			if self.hasElementInScope(.ruby) {
				self.generateImpliedEndTags()
			}
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if kRubyTextTags.contains(name) {
			if self.hasElementInScope(.ruby) {
				self.generateImpliedEndTags(except: "rtc")
			}
			_ = self.insertElement(name: name, attrs: attrs)
		}
		else if name == "math" {
			self.reconstructActiveFormattingElements()
			let adjustedAttrs = self.adjustForeignAttributes(attrs, namespace: .math)
			_ = self.insertElement(name: name, namespace: .math, attrs: adjustedAttrs)
			if selfClosing {
				self.popCurrentElement()
			}
		}
		else if name == "svg" {
			self.reconstructActiveFormattingElements()
			let adjustedAttrs = self.adjustForeignAttributes(attrs, namespace: .svg)
			_ = self.insertElement(name: name, namespace: .svg, attrs: adjustedAttrs)
			if selfClosing {
				self.popCurrentElement()
			}
		}
		else if [
			"caption", "col", "colgroup", "frame", "head", "tbody", "td", "tfoot", "th", "thead", "tr",
		].contains(name) {
			self.emitError("unexpected-start-tag")
			// Ignore
		}
		else {
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: name, attrs: attrs)
		}
	}

	private func processEndTag(name: String) {
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
				self.processEndTag(name: name)

			case .beforeHtml:
				if kBreakoutTags.contains(name) {
					self.insertHtmlElement()
					self.insertionMode = .beforeHead
					self.processEndTag(name: name)
				}
				else {
					self.emitError("unexpected-end-tag")
				}

			case .beforeHead:
				if kBreakoutTags.contains(name) {
					self.insertHeadElement()
					self.insertionMode = .inHead
					self.processEndTag(name: name)
				}
				else {
					self.emitError("unexpected-end-tag")
				}

			case .inHead:
				if name == "head" {
					self.popCurrentElement()
					self.insertionMode = .afterHead
				}
				else if kBodyHtmlBrTags.contains(name) {
					self.popCurrentElement() // head
					self.insertionMode = .afterHead
					self.processEndTag(name: name)
				}
				else if name == "template" {
					// Process template end tag using in body rules
					self.processEndTagInBody(name: name)
				}
				else {
					self.emitError("unexpected-end-tag")
				}

			case .inHeadNoscript:
				if name == "noscript" {
					self.popCurrentElement()
					self.insertionMode = .inHead
				}
				else if name == "br" {
					self.emitError("unexpected-end-tag")
					self.popCurrentElement()
					self.insertionMode = .inHead
					self.processEndTag(name: name)
				}
				else {
					self.emitError("unexpected-end-tag")
				}

			case .afterHead:
				if name == "body" || name == "html" || name == "br" {
					self.insertBodyElement()
					self.insertionMode = .inBody
					self.processEndTag(name: name)
				}
				else if name == "template" {
					// Process template end tag using in body rules
					self.processEndTagInBody(name: name)
				}
				else {
					self.emitError("unexpected-end-tag")
				}

			case .inBody:
				self.processEndTagInBody(name: name)

			case .text:
				if name == "script" {
					self.popCurrentElement()
					self.insertionMode = self.originalInsertionMode
				}
				else {
					self.popCurrentElement()
					self.insertionMode = self.originalInsertionMode
				}

			case .afterBody:
				if name == "html" {
					self.insertionMode = .afterAfterBody
				}
				else {
					self.emitError("unexpected-end-tag-after-body")
					self.insertionMode = .inBody
					self.processEndTag(name: name)
				}

			case .afterAfterBody:
				self.emitError("unexpected-end-tag-after-body")
				self.insertionMode = .inBody
				self.processEndTag(name: name)

			case .inCell:
				if kTableCellTags.contains(name) {
					if !self.hasElementInTableScope(name) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.generateImpliedEndTags()
					if self.currentNode?.name != name {
						self.emitError("end-tag-too-early")
					}
					self.popUntil(name)
					self.clearActiveFormattingElementsToLastMarker()
					self.insertionMode = .inRow
				}
				else if kBodyCaptionHtmlTags.contains(name) {
					self.emitError("unexpected-end-tag")
					// Ignore
				}
				else if kTableRelatedTags.contains(name) {
					if !self.hasElementInTableScope(name) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.closeCell()
					self.processEndTag(name: name)
				}
				else {
					self.processEndTagInBody(name: name)
				}

			case .inRow:
				if name == "tr" {
					if !self.hasElementInTableScope(.tr) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.clearStackBackToTableRowContext()
					self.popCurrentElement()
					self.insertionMode = .inTableBody
				}
				else if name == "table" {
					if !self.hasElementInTableScope(.tr) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.clearStackBackToTableRowContext()
					self.popCurrentElement()
					self.insertionMode = .inTableBody
					self.processEndTag(name: name)
				}
				else if kTableSectionTags.contains(name) {
					if !self.hasElementInTableScope(name) {
						self.emitError("unexpected-end-tag")
						return
					}
					if !self.hasElementInTableScope(.tr) {
						return
					}
					self.clearStackBackToTableRowContext()
					self.popCurrentElement()
					self.insertionMode = .inTableBody
					self.processEndTag(name: name)
				}
				else if kBodyCaptionCellTags.contains(name) {
					self.emitError("unexpected-end-tag")
					// Ignore
				}
				else if name == "template" {
					// Template end tag is handled directly without mode restoration
					self.processEndTagInBody(name: name)
				}
				else {
					// Process using "in table" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inTable
					self.processEndTag(name: name)
					if self.insertionMode == .inTable {
						self.insertionMode = savedMode
					}
				}

			case .inTableBody:
				if kTableSectionTags.contains(name) {
					if !self.hasElementInTableScope(name) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.clearStackBackToTableBodyContext()
					self.popCurrentElement()
					self.insertionMode = .inTable
				}
				else if name == "table" {
					if !self.hasElementInTableScope(.tbody), !self.hasElementInTableScope(.thead),
					   !self.hasElementInTableScope(.tfoot)
					{
						self.emitError("unexpected-end-tag")
						return
					}
					self.clearStackBackToTableBodyContext()
					self.popCurrentElement()
					self.insertionMode = .inTable
					self.processEndTag(name: name)
				}
				else if kBodyCaptionRowTags.contains(name) {
					self.emitError("unexpected-end-tag")
					// Ignore
				}
				else if name == "template" {
					// Template end tag is handled directly without mode restoration
					self.processEndTagInBody(name: name)
				}
				else {
					// Process using "in table" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inTable
					self.processEndTag(name: name)
					if self.insertionMode == .inTable {
						self.insertionMode = savedMode
					}
				}

			case .inColumnGroup:
				if name == "colgroup" {
					if self.currentNode?.tagId == .colgroup {
						self.popCurrentElement()
						self.insertionMode = .inTable
					}
					else {
						self.emitError("unexpected-end-tag")
					}
				}
				else if name == "col" {
					self.emitError("unexpected-end-tag")
					// Ignore
				}
				else if name == "template" {
					self.processEndTagInBody(name: name)
				}
				else {
					// Close colgroup and reprocess
					if self.currentNode?.tagId == .colgroup {
						self.popCurrentElement()
						self.insertionMode = .inTable
						self.processEndTag(name: name)
					}
					else {
						self.emitError("unexpected-end-tag")
					}
				}

			case .inTable:
				if name == "table" {
					if !self.hasElementInTableScope(.table) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.popUntil("table")
					self.resetInsertionMode()
				}
				else if [
					"body", "caption", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr",
				].contains(name) {
					self.emitError("unexpected-end-tag")
					// Ignore
				}
				else if name == "template" {
					self.processEndTagInBody(name: name)
				}
				else {
					// Foster parent: process using in body rules
					self.emitError("unexpected-end-tag")
					self.fosterParentingEnabled = true
					self.processEndTagInBody(name: name)
					self.fosterParentingEnabled = false
				}

			case .inCaption:
				if name == "caption" {
					if !self.hasElementInTableScope(.caption) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.generateImpliedEndTags()
					if self.currentNode?.tagId != .caption {
						self.emitError("end-tag-too-early")
					}
					self.popUntil("caption")
					self.clearActiveFormattingElementsToLastMarker()
					self.insertionMode = .inTable
				}
				else if name == "table" {
					if !self.hasElementInTableScope(.caption) {
						self.emitError("unexpected-end-tag")
						return
					}
					self.generateImpliedEndTags()
					if self.currentNode?.tagId != .caption {
						self.emitError("end-tag-too-early")
					}
					self.popUntil("caption")
					self.clearActiveFormattingElementsToLastMarker()
					self.insertionMode = .inTable
					self.processEndTag(name: name)
				}
				else if ["body", "col", "colgroup", "html", "tbody", "td", "tfoot", "th", "thead", "tr"]
					.contains(name)
				{
					self.emitError("unexpected-end-tag")
					// Ignore
				}
				else {
					self.processEndTagInBody(name: name)
				}

			case .inFrameset:
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

			case .afterFrameset:
				if name == "html" {
					self.insertionMode = .afterAfterFrameset
				}
				else {
					self.emitError("unexpected-end-tag-after-frameset")
				}

			case .afterAfterFrameset:
				self.emitError("unexpected-end-tag-after-frameset")
    // Ignore

			case .inTemplate:
				// In template mode, only template end tag is processed
				if name == "template" {
					// Process using in body rules
					self.processEndTagInBody(name: name)
				}
				else {
					// All other end tags are parse errors and ignored
					self.emitError("unexpected-end-tag-in-template")
				}

			case .inSelect:
				if name == "optgroup" {
					// If current node is option and previous is optgroup, pop option first
					if let current = currentNode, current.name == "option",
					   openElements.count >= 2, openElements[openElements.count - 2].name == "optgroup"
					{
						self.popCurrentElement()
					}
					if let current = currentNode, current.name == "optgroup" {
						self.popCurrentElement()
					}
					else {
						self.emitError("unexpected-end-tag")
					}
				}
				else if name == "option" {
					if let current = currentNode, current.name == "option" {
						self.popCurrentElement()
					}
					else {
						self.emitError("unexpected-end-tag")
					}
				}
				else if name == "select" {
					if !self.hasElementInSelectScope("select") {
						self.emitError("unexpected-end-tag")
						return
					}
					self.popUntil("select")
					// Clear the marker we inserted when opening select
					self.clearActiveFormattingElementsToLastMarker()
					self.resetInsertionMode()
				}
				else if name == "template" {
					self.processEndTagInBody(name: name)
				}
				else if name == "a" || FORMATTING_ELEMENTS.contains(name.lowercased()) {
					// Handle formatting element end tags with adoption agency
					// Per HTML5 spec: formatting elements in select use adoption agency
					self.adoptionAgency(name: name)
				}
				else if kFormElementTags.contains(
					name.lowercased())
				{
					// Per HTML5 spec: these end tags in select mode close the element if it's on the stack
					// But we must not pop across the select boundary
					let lowered = name.lowercased()
					var selectIndex: Int? = nil
					var targetIndex: Int? = nil
					for (i, node) in self.openElements.enumerated() {
						if node.name == "select", selectIndex == nil {
							selectIndex = i
						}
						if node.name == lowered {
							targetIndex = i // Track the LAST occurrence
						}
					}
					// Only pop if target exists and is AFTER (or at same level as) select
					if let target = targetIndex, selectIndex == nil || target > selectIndex! {
						while let current = currentNode, current.name != lowered {
							self.popCurrentElement()
							if self.openElements.isEmpty { break }
						}
						if let current = currentNode, current.name == lowered {
							self.popCurrentElement()
						}
					}
					else {
						self.emitError("unexpected-end-tag")
					}
				}
				else {
					// Per HTML5 spec: unknown end tags in inSelect mode are ignored
					self.emitError("unexpected-end-tag")
				}

			case .inSelectInTable:
				// Table-related end tags close the select and reprocess
				if kTableBoundaryTags.contains(name) {
					self.emitError("unexpected-end-tag-in-select")
					if !self.hasElementInTableScope(name) {
						// Ignore the token
						return
					}
					// Close the select
					self.popUntil("select")
					self.resetInsertionMode()
					// Reprocess the end tag
					self.processEndTag(name: name)
				}
				else {
					// Process using "in select" rules
					let savedMode = self.insertionMode
					self.insertionMode = .inSelect
					self.processEndTag(name: name)
					if self.insertionMode == .inSelect {
						self.insertionMode = savedMode
					}
				}

			default:
				self.processEndTagInBody(name: name)
		}
	}

	private func processEndTagInBody(name: String) {
		if name == "body" {
			if !self.hasElementInScope(.body) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.insertionMode = .afterBody
		}
		else if name == "html" {
			if !self.hasElementInScope(.body) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.insertionMode = .afterBody
			self.processEndTag(name: name)
		}
		else if [
			"address", "article", "aside", "blockquote", "button", "center", "details", "dialog", "dir",
			"div", "dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "listing",
			"main", "menu", "nav", "ol", "pre", "search", "section", "summary", "ul",
		].contains(name) {
			if !self.hasElementInScope(name) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags()
			if self.currentNode?.name != name {
				self.emitError("end-tag-too-early")
			}
			self.popUntil(name)
		}
		else if name == "form" {
			let node = self.formElement
			self.formElement = nil
			if node == nil || !self.hasElementInScope(.form) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags()
			if self.currentNode !== node {
				self.emitError("end-tag-too-early")
			}
			if let node = node, let idx = openElements.firstIndex(where: { $0 === node }) {
				self.openElements.remove(at: idx)
			}
		}
		else if name == "p" {
			if !self.hasElementInButtonScope(.p) {
				self.emitError("unexpected-end-tag")
				_ = self.insertElement(name: "p", attrs: [:])
			}
			self.closePElement()
		}
		else if name == "li" {
			if !self.hasElementInListItemScope(.li) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags(except: "li")
			if self.currentNode?.tagId != .li {
				self.emitError("end-tag-too-early")
			}
			self.popUntil("li")
		}
		else if kListItemTags.contains(name) {
			if !self.hasElementInScope(name) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags(except: name)
			if self.currentNode?.name != name {
				self.emitError("end-tag-too-early")
			}
			self.popUntil(name)
		}
		else if kHeadingTags.contains(name) {
			if !self.hasElementInScope(.h1), !self.hasElementInScope(.h2),
			   !self.hasElementInScope(.h3),
			   !self.hasElementInScope(.h4), !self.hasElementInScope(.h5), !self.hasElementInScope(.h6)
			{
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags()
			if self.currentNode?.name != name {
				self.emitError("end-tag-too-early")
			}
			// Pop until h1-h6
			while let current = currentNode {
				self.popCurrentElement()
				if kHeadingTags.contains(current.name) {
					break
				}
			}
		}
		else if FORMATTING_ELEMENTS.contains(name) || name == "a" {
			// Run adoption agency algorithm (simplified)
			self.adoptionAgency(name: name)
		}
		else if kFormattingScope.contains(name) {
			if !self.hasElementInScope(name) {
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags()
			if self.currentNode?.name != name {
				self.emitError("end-tag-too-early")
			}
			self.popUntil(name)
			self.clearActiveFormattingElementsToLastMarker()
		}
		else if name == "br" {
			self.emitError("unexpected-end-tag")
			// Treat as <br>
			self.reconstructActiveFormattingElements()
			_ = self.insertElement(name: "br", attrs: [:])
			self.popCurrentElement()
			self.framesetOk = false
		}
		else if name == "template" {
			// Handle template end tag
			// Per spec: check if template is on the stack of open elements (not in scope!)
			// Only match HTML namespace templates, not SVG/MathML ones
			let hasTemplate = self.openElements.contains {
				$0.name == "template" && ($0.namespace == nil || $0.namespace == .html)
			}
			if !hasTemplate {
				self.emitError("unexpected-end-tag")
				return
			}
			self.generateImpliedEndTags()
			if self.currentNode?.tagId != .template {
				self.emitError("end-tag-too-early")
			}
			// Pop elements until HTML template
			while let current = currentNode {
				let nodeName = current.name
				let isHtmlTemplate =
					nodeName == "template" && (current.namespace == nil || current.namespace == .html)
				self.popCurrentElement()
				if isHtmlTemplate {
					break
				}
			}
			// Clear active formatting elements to last marker
			while let last = activeFormattingElements.last {
				self.activeFormattingElements.removeLast()
				if last == nil { // marker
					break
				}
			}
			// Pop template insertion mode
			if !self.templateInsertionModes.isEmpty {
				self.templateInsertionModes.removeLast()
			}
			// Reset insertion mode
			self.resetInsertionMode()
		}
		else {
			// Any other end tag
			self.anyOtherEndTag(name: name)
		}
	}

	private func anyOtherEndTag(name: String) {
		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let node = self.openElements[i]
			if node.name == name {
				self.generateImpliedEndTags(except: name)
				if self.currentNode?.name != name {
					self.emitError("end-tag-too-early")
				}
				while self.openElements.count > i {
					self.popCurrentElement()
				}
				return
			}
			if SPECIAL_ELEMENTS.contains(node.name) {
				self.emitError("unexpected-end-tag")
				return
			}
		}
	}

	private func processComment(_ text: String) {
		self.flushPendingTableCharacterTokens()
		let comment = Node(name: "#comment", data: .comment(text))

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

		let node = Node(name: "!doctype", data: .doctype(doctype))
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
		else if doctype.name?.lowercased() != "html" {
			self.quirksMode = true
		}
		else if doctype.publicId != nil {
			// Has PUBLIC identifier - check for known quirks-triggering patterns
			let publicId = doctype.publicId?.lowercased() ?? ""
			let systemId = doctype.systemId?.lowercased()

			// Many legacy PUBLIC identifiers trigger quirks mode
			let quirksPublicIds = [
				"-//w3c//dtd html 3.2",
				"-//w3c//dtd html 4.0 transitional",
				"-//w3c//dtd html 4.0 frameset",
				"-//w3c//dtd html 4.01 transitional",
				"-//w3c//dtd html 4.01 frameset",
				"html", // Just "html" as public id
			]

			if quirksPublicIds.contains(where: { publicId.hasPrefix($0) }) {
				self.quirksMode = true
			}
			else if publicId.hasPrefix("-//w3c//dtd html 4.01"), systemId == nil {
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

	private func processEOF() {
		self.flushPendingTableCharacterTokens()
		// Generate implied end tags and finish
		switch self.insertionMode {
			case .initial:
				self.insertionMode = .beforeHtml
				self.processEOF()

			case .beforeHtml:
				self.insertHtmlElement()
				self.insertionMode = .beforeHead
				self.processEOF()

			case .beforeHead:
				self.insertHeadElement()
				self.insertionMode = .inHead
				self.processEOF()

			case .inHead:
				self.popCurrentElement()
				self.insertionMode = .afterHead
				self.processEOF()

			case .inHeadNoscript:
				self.emitError("eof-in-noscript")
				self.popCurrentElement() // noscript
				self.insertionMode = .inHead
				self.processEOF()

			case .afterHead:
				self.insertBodyElement()
				self.insertionMode = .inBody
				self.processEOF()

			case .text:
				// EOF in text mode (script/rawtext)
				self.emitError("eof-in-script-html-comment-like-text")
				self.popCurrentElement()
				self.insertionMode = self.originalInsertionMode
				self.processEOF()

			case .inTable, .inTableBody, .inRow, .inCell, .inCaption, .inColumnGroup:
				// EOF in table contexts - pop elements and process EOF
				self.emitError("eof-in-table")
				// For in-table modes, we should process EOF which will handle generating implied tags
				self.insertionMode = .inBody
				self.processEOF()

			case .inTemplate:
				// EOF in template - pop template and close
				// Check if template is in the stack (not in scope - table breaks scope but template is still there)
				let hasTemplate = self.openElements.contains { $0.name == "template" }
				if !hasTemplate {
					// No template in stack - stop processing
					break
				}
				self.emitError("eof-in-template")
				self.popUntil("template")
				self.clearActiveFormattingElementsToLastMarker()
				if !self.templateInsertionModes.isEmpty {
					self.templateInsertionModes.removeLast()
				}
				self.resetInsertionMode()
				self.processEOF()

			case .inBody, .inSelect, .inSelectInTable, .inFrameset, .afterBody, .afterFrameset,
			     .afterAfterBody, .afterAfterFrameset, .inTableText:
				// Per spec: if template insertion modes stack is not empty, process using in template rules
				if !self.templateInsertionModes.isEmpty {
					self.insertionMode = .inTemplate
					self.processEOF()
				}
				// Otherwise stop parsing (break)
		}
	}

	// MARK: - Element Insertion

	@inline(__always)
	private var currentNode: Node? {
		self.openElements.last
	}

	/// Returns the adjusted insertion target, redirecting to templateContent for template elements
	/// When stack is empty, finds html element per Python justhtml _current_node_or_html behavior
	@inline(__always)
	private var adjustedInsertionTarget: Node {
		if let current = currentNode {
			// If current node is a template, insert into its content document fragment
			if current.name == "template", let content = current.templateContent {
				return content
			}
			return current
		}

		// Stack is empty - find html element in document children
		// (matches Python's _current_node_or_html behavior)
		for child in self.document.children {
			if child.name == "html" {
				return child
			}
		}
		// Fallback to document if no html element found
		return self.document
	}

	private func createElement(name: String, namespace: Namespace = .html, attrs: [String: String])
		-> Node
	{
		return Node(name: name, namespace: namespace, attrs: attrs)
	}

	/// Adjust attributes for foreign content (SVG/MathML)
	private func adjustForeignAttributes(_ attrs: [String: String], namespace: Namespace) -> [String:
		String]
	{
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
	private func insertElement(name: String, namespace: Namespace = .html, attrs: [String: String])
		-> Node
	{
		let element = self.createElement(name: name, namespace: namespace, attrs: attrs)
		self.insertNode(element)
		self.openElements.append(element)
		return element
	}

	private func insertNode(_ node: Node) {
		// Per spec: foster parenting only applies when the target is a table element
		// (table, tbody, tfoot, thead, tr). If we're inside a formatting element,
		// insert normally into that element.
		if self.fosterParentingEnabled {
			let target = self.adjustedInsertionTarget
			if kTableRelatedTags.contains(target.name) {
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
		// Find last table and last template in the stack
		var lastTableIndex: Int? = nil
		var lastTemplateIndex: Int? = nil

		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let element = self.openElements[i]
			if element.name == "table", lastTableIndex == nil {
				lastTableIndex = i
			}
			if element.name == "template", lastTemplateIndex == nil {
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
			if !self.openElements.isEmpty {
				self.openElements[0].appendChild(node)
			}
			else {
				// Fragment parsing - insert directly into document
				self.document.appendChild(node)
			}
			return
		}

		let tableElement = self.openElements[tableIndex]

		// If table's parent is an element, insert before table
		if let parent = tableElement.parent {
			parent.insertBefore(node, reference: tableElement)
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
		   kTableRelatedTags.contains(target.name)
		{
			self.insertCharacterWithFosterParenting(ch)
			return
		}

		// Merge with previous text node if possible
		if let lastChild = target.children.last, lastChild.name == "#text" {
			if case var .text(existing) = lastChild.data {
				existing.append(ch)
				lastChild.data = .text(existing)
				return
			}
		}

		let textNode = Node(name: "#text", data: .text(String(ch)))
		target.appendChild(textNode)
	}

	/// Insert a string of text directly (batch insertion for performance)
	@inline(__always)
	private func insertText(_ text: String) {
		guard !text.isEmpty else { return }

		let target = self.adjustedInsertionTarget

		// Per spec: foster parenting for text only applies when the target is a table element
		if self.fosterParentingEnabled,
		   kTableRelatedTags.contains(target.name)
		{
			// Fall back to character-by-character for foster parenting
			for ch in text {
				self.insertCharacterWithFosterParenting(ch)
			}
			return
		}

		// Merge with previous text node if possible
		if let lastChild = target.children.last, lastChild.name == "#text" {
			if case var .text(existing) = lastChild.data {
				existing.append(text)
				lastChild.data = .text(existing)
				return
			}
		}

		let textNode = Node(name: "#text", data: .text(text))
		target.appendChild(textNode)
	}

	private func insertCharacterWithFosterParenting(_ ch: Character) {
		// Find the foster parent location (before the table)
		var lastTableIndex: Int? = nil
		var lastTemplateIndex: Int? = nil

		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let element = self.openElements[i]
			if element.name == "table", lastTableIndex == nil {
				lastTableIndex = i
			}
			if element.name == "template", lastTemplateIndex == nil {
				lastTemplateIndex = i
			}
		}

		// If last template is after last table, or there's no table, use template contents
		if let templateIndex = lastTemplateIndex {
			if lastTableIndex == nil || templateIndex > lastTableIndex! {
				if let content = openElements[templateIndex].templateContent {
					// Merge with previous text node if possible
					if let lastChild = content.children.last, lastChild.name == "#text" {
						if case let .text(existing) = lastChild.data {
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
			let target = self.adjustedInsertionTarget
			if let lastChild = target.children.last, lastChild.name == "#text" {
				if case let .text(existing) = lastChild.data {
					lastChild.data = .text(existing + String(ch))
					return
				}
			}
			let textNode = Node(name: "#text", data: .text(String(ch)))
			target.appendChild(textNode)
			return
		}

		let tableElement = self.openElements[tableIndex]

		// Insert before the table
		if let parent = tableElement.parent {
			// Check if there's a text node right before the table that we can merge with
			if let tableIdx = parent.children.firstIndex(where: { $0 === tableElement }),
			   tableIdx > 0
			{
				let prevNode = parent.children[tableIdx - 1]
				if prevNode.name == "#text" {
					if case let .text(existing) = prevNode.data {
						prevNode.data = .text(existing + String(ch))
						return
					}
				}
			}
			let textNode = Node(name: "#text", data: .text(String(ch)))
			parent.insertBefore(textNode, reference: tableElement)
		}
		else {
			// Table has no parent - use the element before table in stack
			if tableIndex > 0 {
				let target = self.openElements[tableIndex - 1]
				if let lastChild = target.children.last, lastChild.name == "#text" {
					if case let .text(existing) = lastChild.data {
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
				&& !self.openElements.contains {
					$0.name == name && ($0.namespace == nil || $0.namespace == .html)
				}

		while let current = currentNode {
			// Only match HTML namespace elements
			if current.name == name, current.namespace == nil || current.namespace == .html {
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

	/// Clear the stack back to a table context (table, template, or html)
	private func clearStackBackToTableContext() {
		while let current = currentNode {
			if kTableContextTags.contains(current.name) {
				break
			}
			self.popCurrentElement()
		}
	}

	/// Clear the stack back to a table body context (tbody, tfoot, thead, template, or html)
	private func clearStackBackToTableBodyContext() {
		while let current = currentNode {
			if kTableBodyContextTags.contains(current.name) {
				break
			}
			self.popCurrentElement()
		}
	}

	/// Clear the stack back to a table row context (tr, template, or html)
	private func clearStackBackToTableRowContext() {
		// Per Python justhtml: requires both name match AND HTML namespace
		while let current = currentNode {
			let isHTML = current.namespace == nil || current.namespace == .html
			if kRowContextTags.contains(current.name), isHTML {
				break
			}
			self.popCurrentElement()
		}
	}

	/// Close the current cell (td or th)
	private func closeCell() {
		self.generateImpliedEndTags()
		if let current = currentNode, current.tagId != .td, current.tagId != .th {
			self.emitError("end-tag-too-early")
		}
		// Pop until td or th in HTML namespace
		// Per Python justhtml: if no HTML td/th exists, may pop to empty stack
		while let current = currentNode {
			let name = current.name
			let isHTML = current.namespace == nil || current.namespace == .html
			self.popCurrentElement()
			if (name == "td" || name == "th"), isHTML {
				break
			}
		}
		self.clearActiveFormattingElementsToLastMarker()
		self.insertionMode = .inRow
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

	private func hasElementInScope(_ name: String) -> Bool {
		return self.hasElementInScope(name, scopeElements: SCOPE_ELEMENTS)
	}

	private func hasElementInButtonScope(_ name: String) -> Bool {
		return self.hasElementInScope(name, scopeElements: BUTTON_SCOPE_ELEMENTS)
	}

	private func hasElementInSelectScope(_ name: String) -> Bool {
		// In select scope, everything except optgroup and option is a scope marker
		// This is unusual - most scope definitions have limited markers, but select scope
		// treats everything except optgroup/option as markers
		for node in self.openElements.reversed() {
			if node.name == name {
				return true
			}
			if node.tagId != .optgroup, node.tagId != .option {
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
		return self.hasElementInScope(name, scopeElements: LIST_ITEM_SCOPE_ELEMENTS)
	}

	private func hasElementInTableScope(_ name: String) -> Bool {
		// Special case: td/th/tr match by name only per Python justhtml behavior
		// This allows closing SVG/MathML cells/rows when HTML table handling is triggered
		let matchByNameOnly = (name == "td" || name == "th" || name == "tr")

		for node in self.openElements.reversed() {
			let isHTML = node.namespace == nil || node.namespace == .html

			if node.name == name {
				// For td/th, match by name regardless of namespace
				// For other elements, require HTML namespace
				if matchByNameOnly || isHTML {
					return true
				}
			}
			// Scope terminators require HTML namespace
			if isHTML, TABLE_SCOPE_ELEMENTS.contains(node.name) {
				return false
			}
		}
		// Check context element for fragment parsing
		if let ctx = contextElement, ctx.name == name {
			if matchByNameOnly || (ctx.namespace == nil || ctx.namespace == .html) {
				return true
			}
		}
		return false
	}

	private func hasElementInScope(_ name: String, scopeElements: Set<String>) -> Bool {
		for node in self.openElements.reversed() {
			// Per WHATWG spec, only match HTML namespace elements when checking scope
			if node.name == name, node.namespace == nil || node.namespace == .html {
				return true
			}
			// Scope boundary elements can be in any namespace
			// HTML elements in scopeElements, or MathML/SVG integration points
			if scopeElements.contains(node.name) {
				// For MathML/SVG scope boundaries, check namespace
				// Use module-level kMathMLIntegrationTags and kSVGIntegrationTags
				if kMathMLIntegrationTags.contains(node.name) {
					if node.namespace == .math {
						return false
					}
				}
				else if kSVGIntegrationTags.contains(node.name) {
					if node.namespace == .svg {
						return false
					}
				}
				else {
					// HTML scope boundary element
					return false
				}
			}
		}
		// Check context element for fragment parsing
		if let ctx = contextElement, ctx.name == name, ctx.namespace == nil || ctx.namespace == .html {
			return true
		}
		return false
	}

	// MARK: - TagID-based Scope Checking (fast integer comparisons)

	@inline(__always)
	private func hasElementInScope(_ tagId: TagID) -> Bool {
		return self.hasElementInScope(tagId, scopeElements: SCOPE_ELEMENTS_ID)
	}

	@inline(__always)
	private func hasElementInButtonScope(_ tagId: TagID) -> Bool {
		return self.hasElementInScope(tagId, scopeElements: BUTTON_SCOPE_ELEMENTS_ID)
	}

	@inline(__always)
	private func hasElementInListItemScope(_ tagId: TagID) -> Bool {
		return self.hasElementInScope(tagId, scopeElements: LIST_ITEM_SCOPE_ELEMENTS_ID)
	}

	@inline(__always)
	private func hasElementInTableScope(_ tagId: TagID) -> Bool {
		for node in self.openElements.reversed() {
			let isHTML = node.namespace == nil || node.namespace == .html
			if node.tagId == tagId, isHTML || tagId == .td || tagId == .th || tagId == .tr {
				return true
			}
			if isHTML, TABLE_SCOPE_ELEMENTS_ID.contains(node.tagId) {
				return false
			}
		}
		if let ctx = contextElement, ctx.tagId == tagId {
			let isHTML = ctx.namespace == nil || ctx.namespace == .html
			if isHTML || tagId == .td || tagId == .th || tagId == .tr {
				return true
			}
		}
		return false
	}

	@inline(__always)
	private func hasElementInScope(_ tagId: TagID, scopeElements: Set<TagID>) -> Bool {
		for node in self.openElements.reversed() {
			if node.tagId == tagId, node.namespace == nil || node.namespace == .html {
				return true
			}
			if scopeElements.contains(node.tagId) {
				if kMathMLIntegrationTagIDs.contains(node.tagId) {
					if node.namespace == .math {
						return false
					}
				}
				else if kSVGIntegrationTagIDs.contains(node.tagId) {
					if node.namespace == .svg {
						return false
					}
				}
				else {
					return false
				}
			}
		}
		if let ctx = contextElement, ctx.tagId == tagId, ctx.namespace == nil || ctx.namespace == .html {
			return true
		}
		return false
	}

	// MARK: - Implied End Tags

	private func generateImpliedEndTags(except: String? = nil) {
		while let current = currentNode {
			if IMPLIED_END_TAGS.contains(current.name), current.name != except {
				self.popCurrentElement()
			}
			else {
				break
			}
		}
	}

	private func closePElement() {
		self.generateImpliedEndTags(except: "p")
		if self.currentNode?.tagId != .p {
			self.emitError("expected-p-end-tag")
		}
		self.popUntil("p")
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
				if earliestMatchIndex == nil {
					earliestMatchIndex = i
				}
				else {
					earliestMatchIndex = i // Keep updating to find earliest
				}
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
		if let elem = lastEntry, openElements.contains(where: { $0 === elem }) {
			return
		}

		// 3. Rewind: find the first entry that's either a marker or in open elements
		var entryIndex = self.activeFormattingElements.count - 1
		while entryIndex > 0 {
			entryIndex -= 1
			if let entry = activeFormattingElements[entryIndex] {
				if self.openElements.contains(where: { $0 === entry }) {
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

	private func adoptionAgency(name: String) {
		// Step 1: If current node is the subject and not in active formatting, just pop it
		if let current = currentNode, current.name == name {
			if !self.hasActiveFormattingEntry(name) {
				self.popUntil(name)
				return
			}
		}

		// Step 2: Outer loop (max 8 iterations)
		for _ in 0 ..< 8 {
			// Step 3: Find formatting element in active formatting list
			var formattingElementIndex: Int?
			for i in stride(from: self.activeFormattingElements.count - 1, through: 0, by: -1) {
				guard let elem = activeFormattingElements[i] else {
					break // Hit marker
				}

				if elem.name == name {
					formattingElementIndex = i
					break
				}
			}

			guard let feIndex = formattingElementIndex,
			      let formattingElement = activeFormattingElements[feIndex]
			else {
				// No formatting element found - use any other end tag handling
				self.anyOtherEndTag(name: name)
				return
			}

			// Step 4: Check if formatting element is in open elements
			guard let feStackIndex = openElements.firstIndex(where: { $0 === formattingElement }) else {
				self.emitError("adoption-agency-1.3")
				self.activeFormattingElements.remove(at: feIndex)
				return
			}

			// Step 5: Check if formatting element is in scope
			if !self.hasElementInScope(name) {
				self.emitError("adoption-agency-1.3")
				return
			}

			// Step 6: If formatting element is not current node, emit error
			if self.currentNode !== formattingElement {
				self.emitError("adoption-agency-1.3")
			}

			// Step 7: Find furthest block (first special element after formatting element)
			// Special elements must be in the correct namespace:
			// - HTML elements in SPECIAL_ELEMENTS
			// - SVG elements: foreignObject, desc, title only
			// - MathML elements: mi, mo, mn, ms, mtext, annotation-xml
			var furthestBlock: Node?
			var furthestBlockIndex: Int?
			for i in (feStackIndex + 1) ..< self.openElements.count {
				let node = self.openElements[i]
				let isSpecial: Bool
				if node.namespace == nil || node.namespace == .html {
					isSpecial = SPECIAL_ELEMENTS.contains(node.name)
				}
				else if node.namespace == .svg {
					isSpecial = kSVGIntegrationTags.contains(node.name)
				}
				else if node.namespace == .math {
					isSpecial = kMathMLIntegrationTags.contains(node.name)
				}
				else {
					isSpecial = false
				}
				if isSpecial {
					furthestBlock = node
					furthestBlockIndex = i
					break
				}
			}

			// Step 8: If no furthest block, pop to formatting element and remove from active formatting
			guard let fb = furthestBlock, let fbIndex = furthestBlockIndex else {
				while self.openElements.count > feStackIndex {
					self.popCurrentElement()
				}
				self.activeFormattingElements.remove(at: feIndex)
				return
			}

			// Step 9: Common ancestor
			// Safety check - formatting element must have a parent
			if feStackIndex == 0 {
				// No common ancestor - just pop to formatting element
				while self.openElements.count > feStackIndex {
					self.popCurrentElement()
				}
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
				var nodeFormattingIndex: Int?
				for i in 0 ..< self.activeFormattingElements.count {
					if let elem = activeFormattingElements[i], elem === node {
						nodeFormattingIndex = i
						break
					}
				}

				// Step 12.4: If inner loop counter > 3 and node is in active formatting, remove it
				if innerLoopCounter > 3, let nfi = nodeFormattingIndex {
					self.activeFormattingElements.remove(at: nfi)
					if nfi < bookmark {
						bookmark -= 1
					}
					nodeFormattingIndex = nil
				}

				// Step 12.5: If node is not in active formatting, remove from stack and continue
				if nodeFormattingIndex == nil {
					self.openElements.remove(at: nodeIndex)
					// After removal, elements shift down, so nodeIndex now points to what was nodeIndex+1.
					// The next decrement at the loop start will correctly move to the element that was above.
					continue
				}

				// Step 12.6: Create new element and replace in both lists
				let newElement = Node(
					name: node.name, namespace: node.namespace ?? .html, attrs: node.attrs)

				// Replace in active formatting
				self.activeFormattingElements[nodeFormattingIndex!] = newElement

				// Replace in open elements
				self.openElements[nodeIndex] = newElement
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
			// But if foster parenting is enabled and common ancestor is a table element,
			// use foster parenting instead
			if commonAncestor.name == "template", let content = commonAncestor.templateContent {
				content.appendChild(lastNode)
			}
			else if self.fosterParentingEnabled,
			        kTableRelatedTags.contains(commonAncestor.name)
			{
				self.fosterParentNode(lastNode)
			}
			else {
				commonAncestor.appendChild(lastNode)
			}

			// Step 14: Create new formatting element
			let newFormattingElement = Node(
				name: formattingElement.name, namespace: formattingElement.namespace ?? .html,
				attrs: formattingElement.attrs)

			// Step 15: Move children of furthest block to new formatting element
			while !fb.children.isEmpty {
				let child = fb.children[0]
				fb.removeChild(child)
				newFormattingElement.appendChild(child)
			}

			// Step 16: Append new formatting element to furthest block
			fb.appendChild(newFormattingElement)

			// Step 17: Remove formatting element from active formatting and insert new at bookmark
			self.activeFormattingElements.remove(at: feIndex)
			if bookmark > self.activeFormattingElements.count {
				bookmark = self.activeFormattingElements.count
			}
			self.activeFormattingElements.insert(newFormattingElement, at: bookmark)

			// Step 18: Remove formatting element from open elements and insert new after furthest block
			self.openElements.removeAll { $0 === formattingElement }
			if let newFbIndex = openElements.firstIndex(where: { $0 === fb }) {
				self.openElements.insert(newFormattingElement, at: newFbIndex + 1)
			}
		}
	}

	/// Check if there's an entry for the given name in active formatting elements (before any marker)
	private func hasActiveFormattingEntry(_ name: String) -> Bool {
		for i in stride(from: self.activeFormattingElements.count - 1, through: 0, by: -1) {
			guard let elem = activeFormattingElements[i] else {
				return false // Hit marker
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
		"strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var",
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
		if ns == .svg && Self.svgHtmlIntegrationPoints.contains(node.name) {
			return false
		}

		// Check if we're in a MathML annotation-xml HTML integration point
		// annotation-xml with encoding="text/html" or "application/xhtml+xml" processes start tags as HTML
		if ns == .math && node.name == "annotation-xml" {
			if let encoding = node.attrs.first(where: { $0.key.lowercased() == "encoding" })?.value {
				let lowercased = encoding.lowercased()
				if lowercased == "text/html" || lowercased == "application/xhtml+xml" {
					return false
				}
			}
		}

		// Note: MathML text integration points (mi, mo, mn, ms, mtext) still process
		// most start tags as foreign content - only breakout elements are handled as HTML
		// So we don't return false for them here

		return ns == .svg || ns == .math
	}

	/// Check if current node is a MathML text integration point
	private func isInMathMLTextIntegrationPoint() -> Bool {
		guard let currentNode = openElements.last else { return false }

		return currentNode.namespace == .math
			&& Self.mathmlTextIntegrationPoints.contains(currentNode.name)
	}

	/// Check if current node is an SVG HTML integration point
	private func isInSVGHtmlIntegrationPoint() -> Bool {
		guard let currentNode = openElements.last else { return false }

		return currentNode.namespace == .svg && Self.svgHtmlIntegrationPoints.contains(currentNode.name)
	}

	/// Check if current node is a MathML annotation-xml HTML integration point
	/// annotation-xml with encoding="text/html" or "application/xhtml+xml" is an HTML integration point
	private func isInMathMLAnnotationXmlIntegrationPoint() -> Bool {
		guard let currentNode = openElements.last else { return false }

		guard currentNode.namespace == .math, currentNode.name == "annotation-xml" else { return false }

		// Check encoding attribute (case-insensitive)
		if let encoding = currentNode.attrs.first(where: { $0.key.lowercased() == "encoding" })?.value {
			let lowercased = encoding.lowercased()
			return lowercased == "text/html" || lowercased == "application/xhtml+xml"
		}
		return false
	}

	/// Process an end tag in foreign content per WHATWG spec
	/// Returns true if handled, false if should fall through to normal processing
	private func processForeignContentEndTag(name: String) -> Bool {
		let lowercaseName = name.lowercased()

		// Special handling for </br> and </p> - break out and reprocess as end tag
		if lowercaseName == "br" || lowercaseName == "p" {
			self.emitError("unexpected-end-tag")
			// Pop until we leave foreign content (reach SVG HTML integration point or HTML namespace)
			while let current = currentNode,
			      let ns = current.namespace,
			      ns == .svg || ns == .math,
			      !(ns == .svg && Self.svgHtmlIntegrationPoints.contains(current.name))
			{
				self.popCurrentElement()
			}
			// Reprocess the end tag in HTML mode - return false to let normal processing handle it
			return false
		}

		// Walk up the stack looking for a matching element
		// Per WHATWG: "Any other end tag" in foreign content
		for i in stride(from: self.openElements.count - 1, through: 0, by: -1) {
			let node = self.openElements[i]

			// Check if this element matches (case-insensitive for foreign, case-sensitive for HTML)
			if node.name.lowercased() == lowercaseName {
				// Only pop if the element is in a foreign namespace
				// HTML elements should be handled by normal processing
				if node.namespace == nil || node.namespace == .html {
					return false
				}
				// Pop elements until we've popped this node
				while self.openElements.count > i {
					self.popCurrentElement()
				}
				return true
			}

			// If we hit an HTML element that doesn't match, let normal processing handle it
			if node.namespace == nil || node.namespace == .html {
				return false
			}
		}

		// No matching element found, let normal processing handle it
		return false
	}

	/// Process a start tag in foreign content
	/// Returns true if handled, false if should fall through to normal processing
	private func processForeignContentStartTag(
		name: String, attrs: [String: String], selfClosing: Bool
	) -> Bool {
		let lowercaseName = name.lowercased()

		// In MathML text integration points (mi, mo, mn, ms, mtext), only mglyph and malignmark
		// stay in MathML - everything else should be processed as HTML
		if let adjNode = adjustedCurrentNode,
		   adjNode.namespace == .math && Self.mathmlTextIntegrationPoints.contains(adjNode.name),
		   lowercaseName != "mglyph" && lowercaseName != "malignmark"
		{
			return false
		}

		// Check for breakout elements
		// font only breaks out if it has color, face, or size attributes
		let isFontBreakout =
			lowercaseName == "font"
				&& (attrs.keys.contains {
					$0.lowercased() == "color" || $0.lowercased() == "face" || $0.lowercased() == "size"
				})

		if Self.foreignContentBreakoutElements.contains(lowercaseName) || isFontBreakout {
			// If current node is MathML text integration point or SVG HTML integration point,
			// process breakout elements as HTML without popping
			if let current = currentNode,
			   let ns = current.namespace,
			   (ns == .svg && Self.svgHtmlIntegrationPoints.contains(current.name))
			   || (ns == .math && Self.mathmlTextIntegrationPoints.contains(current.name))
			{
				return false
			}

			// Pop until we leave foreign content (but not HTML integration points)
			while let current = currentNode,
			      let ns = current.namespace,
			      ns == .svg || ns == .math,
			      !(ns == .svg && Self.svgHtmlIntegrationPoints.contains(current.name)),
			      !(ns == .math && Self.mathmlTextIntegrationPoints.contains(current.name))
			{
				self.popCurrentElement()
			}
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

		let adjustedAttrs = self.adjustForeignAttributes(attrs, namespace: ns)
		_ = self.insertElement(name: adjustedName, namespace: ns, attrs: adjustedAttrs)

		if selfClosing {
			self.popCurrentElement()
		}

		return true
	}

	// MARK: - Rawtext and RCDATA Parsing

	private func parseRawtext(name: String, attrs: [String: String]) {
		_ = self.insertElement(name: name, attrs: attrs)
		self.originalInsertionMode = self.insertionMode
		self.insertionMode = .text
		// TODO: Switch tokenizer to RAWTEXT state
	}

	private func parseRCDATA(name: String, attrs: [String: String]) {
		_ = self.insertElement(name: name, attrs: attrs)
		self.originalInsertionMode = self.insertionMode
		self.insertionMode = .text
		// TODO: Switch tokenizer to RCDATA state
	}

	// MARK: - Insertion Mode Reset

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
			let isHTML = node.namespace == nil || node.namespace == .html

			switch node.name {
				case "select":
					// Select doesn't check isHTML per spec
					// Per spec: check if there's a table ancestor to determine inSelect vs inSelectInTable
					if !last {
						// Check ancestors for table or template
						for j in stride(from: i - 1, through: 0, by: -1) {
							let ancestor = self.openElements[j]
							if ancestor.name == "template" {
								// Template breaks the chain - use inSelect
								break
							}
							if ancestor.name == "table" {
								self.insertionMode = .inSelectInTable
								return
							}
						}
					}
					self.insertionMode = .inSelect
					return

				case "td", "th":
					// Note: Per Python justhtml behavior, td/th match regardless of namespace
					// This allows IN_CELL mode when SVG elements with these names are on stack
					if !last {
						self.insertionMode = .inCell
						return
					}

				case "tr":
					// Note: Per Python justhtml behavior, tr matches regardless of namespace
					// This allows IN_ROW mode when SVG elements with tr name are on stack
					self.insertionMode = .inRow
					return

				case "tbody", "thead", "tfoot":
					if isHTML {
						self.insertionMode = .inTableBody
						return
					}

				case "caption":
					if isHTML {
						self.insertionMode = .inCaption
						return
					}

				case "colgroup":
					if isHTML {
						self.insertionMode = .inColumnGroup
						return
					}

				case "table":
					if isHTML {
						self.insertionMode = .inTable
						return
					}

				case "template":
					// Template doesn't check namespace per spec
					if let mode = templateInsertionModes.last {
						self.insertionMode = mode
					}
					return

				case "head":
					if !last, isHTML {
						self.insertionMode = .inHead
						return
					}

				case "body":
					if isHTML {
						self.insertionMode = .inBody
						return
					}

				case "frameset":
					if isHTML {
						self.insertionMode = .inFrameset
						return
					}

				case "html":
					if isHTML {
						if self.headElement == nil {
							self.insertionMode = .beforeHead
						}
						else {
							self.insertionMode = .afterHead
						}
						return
					}

				default:
					break
			}

			if last {
				self.insertionMode = .inBody
				return
			}
		}
	}

	// MARK: - Utilities

	@inline(__always)
	private func isWhitespace(_ ch: Character) -> Bool {
		return ch == " " || ch == "\t" || ch == "\n" || ch == "\r" || ch == "\u{0C}"
	}

	private func emitError(_ code: String) {
		if self.collectErrors {
			self.errors.append(ParseError(code: code))
		}
	}
}

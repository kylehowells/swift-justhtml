// Selector.swift - CSS selector parser and matcher

import Foundation

// Note: SelectorError is defined in Tokens.swift

/// Query a node tree using a CSS selector
public func query(_ node: Node, selector: String) throws -> [Node] {
	let parsed = try Selector.parse(selector)
	return parsed.match(node)
}

/// Check if a node matches a CSS selector
public func matches(_ node: Node, selector: String) throws -> Bool {
	let parsed = try Selector.parse(selector)
	return parsed.matches(node)
}

// MARK: - Selector

/// Represents a parsed CSS selector (or group of selectors)
indirect enum Selector {
	case simple(SimpleSelector)
	case compound([SimpleSelector])
	case complex(Selector, Combinator, Selector)
	case group([Selector])

	/// Parse a CSS selector string
	static func parse(_ input: String) throws -> Selector {
		var parser = SelectorParser(input)
		return try parser.parseSelector()
	}

	/// Find all matching nodes in the tree
	func match(_ root: Node) -> [Node] {
		var results: [Node] = []
		self.collectMatches(root, into: &results, checkRoot: true)
		return results
	}

	private func collectMatches(_ node: Node, into results: inout [Node], checkRoot: Bool) {
		if checkRoot, self.matches(node) {
			results.append(node)
		}
		for child in node.children {
			self.collectMatches(child, into: &results, checkRoot: true)
		}
		// Also check template content
		if let content = node.templateContent {
			self.collectMatches(content, into: &results, checkRoot: true)
		}
	}

	/// Check if a specific node matches this selector
	func matches(_ node: Node) -> Bool {
		switch self {
			case let .simple(simple):
				return simple.matches(node)

			case let .compound(simples):
				return simples.allSatisfy { $0.matches(node) }

			case let .complex(left, combinator, right):
				// For a complex selector, the right part must match the node
				guard right.matches(node) else { return false }

				// Then check the combinator relationship
				return combinator.check(left, node)

			case let .group(selectors):
				return selectors.contains { $0.matches(node) }
		}
	}
}

// MARK: - SimpleSelector

/// Simple selector components
indirect enum SimpleSelector {
	case universal // *
	case type(String) // tagname
	case id(String) // #id
	case `class`(String) // .class
	case attribute(AttributeSelector) // [attr], [attr=val], etc.
	case pseudoClass(PseudoClass) // :first-child, :nth-child(), etc.
	case pseudoElement(String) // ::before, ::after (not fully implemented)

	func matches(_ node: Node) -> Bool {
		switch self {
			case .universal:
				return node.name != "#document" && node.name != "#document-fragment" && node.name != "#text"
					&& node.name != "#comment"

			case let .type(name):
				return node.name == name || node.name.asciiCaseInsensitiveEquals(name)

			case let .id(id):
				return node.attrs["id"] == id

			case let .class(className):
				return node.attrs["class"]?.containsWhitespaceSeparatedWord(className) == true

			case let .attribute(attrSel):
				return attrSel.matches(node)

			case let .pseudoClass(pseudo):
				return pseudo.matches(node)

			case .pseudoElement:
				// Pseudo-elements don't match actual nodes
				return false
		}
	}
}

// MARK: - AttributeSelector

/// Attribute selector types
struct AttributeSelector {
	let name: String
	let lowercaseName: String?
	let operation: AttributeOperation?
	let value: String?
	let caseInsensitive: Bool

	func matches(_ node: Node) -> Bool {
		guard let attrValue = self.attributeValue(in: node.attrs) else {
			return false // attribute doesn't exist
		}

		guard let op = operation, let val = value else {
			return true // [attr] - attribute exists, no value check needed
		}

		switch op {
			case .equals: // [attr=val]
				return self.valuesEqual(attrValue, val)

			case .includes: // [attr~=val]
				return attrValue.containsWhitespaceSeparatedWord(val, caseInsensitive: self.caseInsensitive)

			case .dashMatch: // [attr|=val]
				return self.valuesEqual(attrValue, val) || self.hasPrefix(attrValue, val + "-")

			case .prefix: // [attr^=val]
				return self.hasPrefix(attrValue, val)

			case .suffix: // [attr$=val]
				return self.hasSuffix(attrValue, val)

			case .substring: // [attr*=val]
				return self.contains(attrValue, val)
		}
	}

	private func attributeValue(in attrs: [String: String]) -> String? {
		if let value = attrs[self.name] {
			return value
		}
		guard let lowercaseName = self.lowercaseName else {
			return nil
		}
		return attrs[lowercaseName]
	}

	private func valuesEqual(_ lhs: String, _ rhs: String) -> Bool {
		self.caseInsensitive ? lhs.asciiCaseInsensitiveEquals(rhs) : lhs == rhs
	}

	private func hasPrefix(_ value: String, _ prefix: String) -> Bool {
		guard self.caseInsensitive else { return value.hasPrefix(prefix) }
		return value.asciiCaseInsensitiveHasPrefix(prefix)
	}

	private func hasSuffix(_ value: String, _ suffix: String) -> Bool {
		guard self.caseInsensitive else { return value.hasSuffix(suffix) }
		return value.asciiCaseInsensitiveHasSuffix(suffix)
	}

	private func contains(_ value: String, _ needle: String) -> Bool {
		guard self.caseInsensitive else { return value.contains(needle) }
		return value.asciiCaseInsensitiveContains(needle)
	}
}

// MARK: - AttributeOperation

enum AttributeOperation {
	case equals // =
	case includes // ~=
	case dashMatch // |=
	case prefix // ^=
	case suffix // $=
	case substring // *=
}

// MARK: - PseudoClass

/// Pseudo-class selectors
indirect enum PseudoClass {
	case firstChild
	case lastChild
	case onlyChild
	case nthChild(Int, Int) // (an+b)
	case nthLastChild(Int, Int)
	case firstOfType
	case lastOfType
	case onlyOfType
	case nthOfType(Int, Int)
	case nthLastOfType(Int, Int)
	case empty
	case root
	case not(Selector)

	func matches(_ node: Node) -> Bool {
		switch self {
			case .firstChild:
				return node.isFirstChild

			case .lastChild:
				return node.isLastChild

			case .onlyChild:
				return node.isOnlyChild

			case let .nthChild(a, b):
				guard let index = node.childIndex else { return false }

				return self.matchesNth(index + 1, a: a, b: b) // CSS indices are 1-based

			case let .nthLastChild(a, b):
				guard let indexFromEnd = node.childIndexFromEnd else { return false }

				return self.matchesNth(indexFromEnd, a: a, b: b)

			case .firstOfType:
				return node.isFirstOfType

			case .lastOfType:
				return node.isLastOfType

			case .onlyOfType:
				return node.isOnlyOfType

			case let .nthOfType(a, b):
				guard let idx = node.typeIndex else { return false }

				return self.matchesNth(idx + 1, a: a, b: b)

			case let .nthLastOfType(a, b):
				guard let indexFromEnd = node.typeIndexFromEnd else { return false }

				return self.matchesNth(indexFromEnd, a: a, b: b)

			case .empty:
				return node.children.isEmpty || node.children.allSatisfy { $0.name == "#comment" }

			case .root:
				return node.parent?.name == "#document" || node.parent?.name == "#document-fragment"

			case let .not(selector):
				return !selector.matches(node)
		}
	}

	private func matchesNth(_ index: Int, a: Int, b: Int) -> Bool {
		if a == 0 {
			return index == b
		}
		let n = (index - b)
		if a > 0 {
			return n >= 0 && n % a == 0
		}
		else {
			return n <= 0 && n % a == 0
		}
	}
}

// MARK: - Combinator

/// Combinators between selectors
enum Combinator {
	case descendant // space
	case child // >
	case nextSibling // +
	case subsequentSibling // ~

	func check(_ left: Selector, _ node: Node) -> Bool {
		switch self {
			case .descendant:
				var current = node.parent
				while let parent = current {
					if left.matches(parent) {
						return true
					}
					current = parent.parent
				}
				return false

			case .child:
				guard let parent = node.parent else { return false }

				return left.matches(parent)

			case .nextSibling:
				guard let prev = node.previousElementSibling else { return false }

				return left.matches(prev)

			case .subsequentSibling:
				return node.hasPreviousElementSibling(matching: left)
		}
	}
}

// MARK: - Node Extensions for Selector Matching

extension Node {
	/// Index among element siblings
	fileprivate var childIndex: Int? {
		guard let parent = parent else { return nil }

		var index = 0
		for child in parent.children {
			guard child.isSelectorElement else { continue }
			if child === self {
				return index
			}
			index += 1
		}
		return nil
	}

	fileprivate var childIndexFromEnd: Int? {
		guard let parent = parent else { return nil }

		var indexFromEnd = 1
		for child in parent.children.reversed() {
			guard child.isSelectorElement else { continue }
			if child === self {
				return indexFromEnd
			}
			indexFromEnd += 1
		}
		return nil
	}

	fileprivate var isFirstChild: Bool {
		return self.childIndex == 0
	}

	fileprivate var isLastChild: Bool {
		guard let parent = parent else { return false }

		for child in parent.children.reversed() {
			guard child.isSelectorElement else { continue }
			return child === self
		}
		return false
	}

	fileprivate var isOnlyChild: Bool {
		guard let parent = parent else { return false }

		var foundElement = false
		for child in parent.children {
			guard child.isSelectorElement else { continue }
			if foundElement {
				return false
			}
			foundElement = true
			if child !== self {
				return false
			}
		}
		return foundElement
	}

	fileprivate var isFirstOfType: Bool {
		guard let parent = parent else { return false }

		for child in parent.children where child.isSelectorElement && child.name == name {
			return child === self
		}
		return false
	}

	fileprivate var isLastOfType: Bool {
		guard let parent = parent else { return false }

		for child in parent.children.reversed() where child.isSelectorElement && child.name == name {
			return child === self
		}
		return false
	}

	fileprivate var isOnlyOfType: Bool {
		guard let parent = parent else { return false }

		var foundMatchingElement = false
		for child in parent.children where child.isSelectorElement && child.name == name {
			if foundMatchingElement {
				return false
			}
			foundMatchingElement = true
			if child !== self {
				return false
			}
		}
		return foundMatchingElement
	}

	fileprivate var typeIndex: Int? {
		guard let parent = parent else { return nil }

		var index = 0
		for child in parent.children where child.isSelectorElement && child.name == name {
			if child === self {
				return index
			}
			index += 1
		}
		return nil
	}

	fileprivate var typeIndexFromEnd: Int? {
		guard let parent = parent else { return nil }

		var indexFromEnd = 1
		for child in parent.children.reversed() where child.isSelectorElement && child.name == name {
			if child === self {
				return indexFromEnd
			}
			indexFromEnd += 1
		}
		return nil
	}

	fileprivate var previousElementSibling: Node? {
		guard let parent = parent else { return nil }

		var previous: Node?
		for child in parent.children {
			if child === self {
				return previous
			}
			if child.isSelectorElement {
				previous = child
			}
		}
		return nil
	}

	fileprivate func hasPreviousElementSibling(matching selector: Selector) -> Bool {
		guard let parent = parent else { return false }

		for child in parent.children {
			if child === self {
				return false
			}
			if child.isSelectorElement && selector.matches(child) {
				return true
			}
		}
		return false
	}

	private var isSelectorElement: Bool {
		!self.name.hasPrefix("#") && self.name != "!doctype"
	}
}

// MARK: - SelectorParser

private struct SelectorParser {
	var input: String
	var position: String.Index

	init(_ input: String) {
		self.input = input
		self.position = input.startIndex
	}

	var current: Character? {
		return self.position < self.input.endIndex ? self.input[self.position] : nil
	}

	mutating func advance() {
		if self.position < self.input.endIndex {
			self.position = self.input.index(after: self.position)
		}
	}

	mutating func skipWhitespace() {
		while let ch = current, ch.isWhitespace {
			self.advance()
		}
	}

	mutating func parseSelector() throws -> Selector {
		var selectors: [Selector] = []

		repeat {
			self.skipWhitespace()
			let sel = try parseComplexSelector()
			selectors.append(sel)
			self.skipWhitespace()
		}
		while self.consume(",")

		if selectors.count == 1 {
			return selectors[0]
		}
		return .group(selectors)
	}

	mutating func parseComplexSelector() throws -> Selector {
		var left = try parseCompoundSelector()

		while true {
			let hadSpace = self.skipWhitespaceReturnIfAny()

			if let combinator = parseCombinator() {
				self.skipWhitespace()
				let right = try parseCompoundSelector()
				left = .complex(left, combinator, right)
			}
			else if hadSpace, self.current != nil, self.current != "," {
				// Descendant combinator (space)
				let right = try parseCompoundSelector()
				left = .complex(left, .descendant, right)
			}
			else {
				break
			}
		}

		return left
	}

	mutating func skipWhitespaceReturnIfAny() -> Bool {
		let hadSpace = self.current?.isWhitespace == true
		self.skipWhitespace()
		return hadSpace
	}

	mutating func parseCombinator() -> Combinator? {
		switch self.current {
			case ">":
				self.advance()
				return .child

			case "+":
				self.advance()
				return .nextSibling

			case "~":
				self.advance()
				return .subsequentSibling

			default:
				return nil
		}
	}

	mutating func parseCompoundSelector() throws -> Selector {
		var simples: [SimpleSelector] = []

		while let simple = try parseSimpleSelector() {
			simples.append(simple)
		}

		if simples.isEmpty {
			throw SelectorError(
				"Expected selector",
				position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		if simples.count == 1 {
			return .simple(simples[0])
		}
		return .compound(simples)
	}

	mutating func parseSimpleSelector() throws -> SimpleSelector? {
		switch self.current {
			case "*":
				self.advance()
				return .universal

			case "#":
				self.advance()
				let name = self.parseName()
				if name.isEmpty {
					throw SelectorError(
						"Expected id name after #",
						position: self.input.distance(from: self.input.startIndex, to: self.position))
				}
				return .id(name)

			case ".":
				self.advance()
				let name = self.parseName()
				if name.isEmpty {
					throw SelectorError(
						"Expected class name after .",
						position: self.input.distance(from: self.input.startIndex, to: self.position))
				}
				return .class(name)

			case "[":
				return try .attribute(self.parseAttributeSelector())

			case ":":
				return try self.parsePseudoSelector()

			default:
				let name = self.parseName()
				if !name.isEmpty {
					return .type(name.lowercased())
				}
				return nil
		}
	}

	mutating func parseName() -> String {
		var name = ""
		while let ch = current, ch.isNameChar {
			name.append(ch)
			self.advance()
		}
		return name
	}

	mutating func consume(_ expected: Character) -> Bool {
		if self.current == expected {
			self.advance()
			return true
		}
		return false
	}

	mutating func parseAttributeSelector() throws -> AttributeSelector {
		guard self.consume("[") else {
			throw SelectorError(
				"Expected [", position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		self.skipWhitespace()

		let attrName = self.parseName()
		if attrName.isEmpty {
			throw SelectorError(
				"Expected attribute name",
				position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		self.skipWhitespace()

		// Check for operator
		var operation: AttributeOperation? = nil
		if self.current == "=" {
			self.advance()
			operation = .equals
		}
		else if self.current == "~", self.peek(1) == "=" {
			self.advance()
			self.advance()
			operation = .includes
		}
		else if self.current == "|", self.peek(1) == "=" {
			self.advance()
			self.advance()
			operation = .dashMatch
		}
		else if self.current == "^", self.peek(1) == "=" {
			self.advance()
			self.advance()
			operation = .prefix
		}
		else if self.current == "$", self.peek(1) == "=" {
			self.advance()
			self.advance()
			operation = .suffix
		}
		else if self.current == "*", self.peek(1) == "=" {
			self.advance()
			self.advance()
			operation = .substring
		}

		var value: String? = nil
		var caseInsensitive = false

		if operation != nil {
			self.skipWhitespace()
			value = try self.parseAttributeValue()
			self.skipWhitespace()

			// Check for case-insensitivity flag
			if self.current == "i" || self.current == "I" {
				caseInsensitive = true
				self.advance()
				self.skipWhitespace()
			}
		}

		guard self.consume("]") else {
			throw SelectorError(
				"Expected ]", position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		return AttributeSelector(
			name: attrName,
			lowercaseName: attrName.asciiLowercasedIfNeeded(),
			operation: operation,
			value: value,
			caseInsensitive: caseInsensitive)
	}

	func peek(_ offset: Int) -> Character? {
		guard let idx = input.index(position, offsetBy: offset, limitedBy: input.endIndex) else {
			return nil
		}

		return idx < self.input.endIndex ? self.input[idx] : nil
	}

	mutating func parseAttributeValue() throws -> String {
		if self.current == "\"" || self.current == "'" {
			return try self.parseQuotedString()
		}
		return self.parseName()
	}

	mutating func parseQuotedString() throws -> String {
		let quote = self.current!
		self.advance()

		var result = ""
		while let ch = current, ch != quote {
			if ch == "\\" {
				self.advance()
				if let escaped = current {
					result.append(escaped)
					self.advance()
				}
			}
			else {
				result.append(ch)
				self.advance()
			}
		}

		guard self.consume(quote) else {
			throw SelectorError(
				"Unterminated string",
				position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		return result
	}

	mutating func parsePseudoSelector() throws -> SimpleSelector {
		guard self.consume(":") else {
			throw SelectorError(
				"Expected :", position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		// Check for pseudo-element (::)
		if self.consume(":") {
			let name = self.parseName()
			return .pseudoElement(name)
		}

		let name = self.parseName().lowercased()

		switch name {
			case "first-child":
				return .pseudoClass(.firstChild)

			case "last-child":
				return .pseudoClass(.lastChild)

			case "only-child":
				return .pseudoClass(.onlyChild)

			case "first-of-type":
				return .pseudoClass(.firstOfType)

			case "last-of-type":
				return .pseudoClass(.lastOfType)

			case "only-of-type":
				return .pseudoClass(.onlyOfType)

			case "empty":
				return .pseudoClass(.empty)

			case "root":
				return .pseudoClass(.root)

			case "nth-child":
				let (a, b) = try parseNth()
				return .pseudoClass(.nthChild(a, b))

			case "nth-last-child":
				let (a, b) = try parseNth()
				return .pseudoClass(.nthLastChild(a, b))

			case "nth-of-type":
				let (a, b) = try parseNth()
				return .pseudoClass(.nthOfType(a, b))

			case "nth-last-of-type":
				let (a, b) = try parseNth()
				return .pseudoClass(.nthLastOfType(a, b))

			case "not":
				guard self.consume("(") else {
					throw SelectorError(
						"Expected ( after :not",
						position: self.input.distance(from: self.input.startIndex, to: self.position))
				}

				self.skipWhitespace()
				let inner = try parseCompoundSelector()
				self.skipWhitespace()
				guard self.consume(")") else {
					throw SelectorError(
						"Expected ) after :not selector",
						position: self.input.distance(from: self.input.startIndex, to: self.position))
				}

				return .pseudoClass(.not(inner))

			default:
				throw SelectorError(
					"Unknown pseudo-class: \(name)",
					position: self.input.distance(from: self.input.startIndex, to: self.position))
		}
	}

	mutating func parseNth() throws -> (Int, Int) {
		guard self.consume("(") else {
			throw SelectorError(
				"Expected ( for nth expression",
				position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		self.skipWhitespace()

		var a = 0
		var b = 0

		// Parse "odd", "even", or "an+b" expression
		if self.consumeKeyword("odd") {
			a = 2
			b = 1
		}
		else if self.consumeKeyword("even") {
			a = 2
			b = 0
		}
		else {
			// Parse an+b
			let result = try parseAnPlusB()
			a = result.0
			b = result.1
		}

		self.skipWhitespace()
		guard self.consume(")") else {
			throw SelectorError(
				"Expected ) after nth expression",
				position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		return (a, b)
	}

	mutating func consumeKeyword(_ keyword: String) -> Bool {
		guard let nextIdx = self.indexAfterKeyword(keyword) else {
			return false
		}
		guard nextIdx >= self.input.endIndex || !self.input[nextIdx].isNameChar else {
			return false
		}
		self.position = nextIdx
		return true
	}

	private func indexAfterKeyword(_ keyword: String) -> String.Index? {
		var inputIndex = self.position
		for keywordChar in keyword {
			guard inputIndex < self.input.endIndex,
			      self.input[inputIndex].asciiCaseInsensitiveEquals(keywordChar)
			else {
				return nil
			}
			inputIndex = self.input.index(after: inputIndex)
		}
		return inputIndex
	}

	mutating func parseAnPlusB() throws -> (Int, Int) {
		var a = 0
		var b = 0
		var sign = 1

		// Optional leading sign
		if self.consume("-") {
			sign = -1
		}
		else if self.consume("+") {
			sign = 1
		}

		// Check for 'n'
		if self.current == "n" || self.current == "N" {
			a = sign
			self.advance()
		}
		else if let ch = current, ch.isNumber {
			// Parse number
			var num = self.parseNumber()
			num *= sign

			// Check if followed by 'n'
			if self.current == "n" || self.current == "N" {
				a = num
				self.advance()
			}
			else {
				// Just a number
				b = num
				self.skipWhitespace()
				guard self.consume(")") else {
					throw SelectorError(
						"Expected ) after number",
						position: self.input.distance(from: self.input.startIndex, to: self.position))
				}

				// Put back the )
				self.position = self.input.index(before: self.position)
				return (0, b)
			}
		}
		else {
			throw SelectorError(
				"Invalid nth expression",
				position: self.input.distance(from: self.input.startIndex, to: self.position))
		}

		// Now we have 'a' and have consumed 'n', parse optional +/- b
		self.skipWhitespace()
		if self.consume("+") {
			self.skipWhitespace()
			b = self.parseNumber()
		}
		else if self.consume("-") {
			self.skipWhitespace()
			b = -self.parseNumber()
		}

		return (a, b)
	}

	mutating func parseNumber() -> Int {
		var numStr = ""
		while let ch = current, ch.isNumber {
			numStr.append(ch)
			self.advance()
		}
		return Int(numStr) ?? 0
	}
}

private extension String {
	func containsWhitespaceSeparatedWord(_ word: String, caseInsensitive: Bool = false) -> Bool {
		guard !word.isEmpty else { return false }

		var wordStart: String.Index?
		var index = self.startIndex

		while index < self.endIndex {
			if self[index].isWhitespace {
				if let start = wordStart,
				   self.word(self[start ..< index], matches: word, caseInsensitive: caseInsensitive)
				{
					return true
				}
				wordStart = nil
			}
			else if wordStart == nil {
				wordStart = index
			}

			index = self.index(after: index)
		}

		if let start = wordStart,
		   self.word(self[start ..< self.endIndex], matches: word, caseInsensitive: caseInsensitive)
		{
			return true
		}
		return false
	}

	private func word(
		_ candidate: Substring,
		matches word: String,
		caseInsensitive: Bool
	) -> Bool {
		caseInsensitive ? candidate.asciiCaseInsensitiveEquals(word) : candidate == word
	}

	func asciiCaseInsensitiveHasSuffix(_ suffix: String) -> Bool {
		guard self.utf8.count >= suffix.utf8.count else { return false }
		return self.utf8.suffix(suffix.utf8.count).elementsEqual(suffix.utf8, by: Self.asciiBytesEqual)
	}

	func asciiCaseInsensitiveContains(_ needle: String) -> Bool {
		guard !needle.isEmpty else { return true }
		guard self.utf8.count >= needle.utf8.count else { return false }

		var start = self.utf8.startIndex
		while start != self.utf8.endIndex {
			var haystackIndex = start
			var needleIndex = needle.utf8.startIndex
			var matches = true

			while needleIndex != needle.utf8.endIndex {
				if haystackIndex == self.utf8.endIndex
					|| !Self.asciiBytesEqual(self.utf8[haystackIndex], needle.utf8[needleIndex])
				{
					matches = false
					break
				}

				haystackIndex = self.utf8.index(after: haystackIndex)
				needleIndex = needle.utf8.index(after: needleIndex)
			}

			if matches {
				return true
			}
			start = self.utf8.index(after: start)
		}
		return false
	}

	func asciiLowercasedIfNeeded() -> String? {
		var hasUppercase = false
		var bytes = ContiguousArray<UInt8>()
		bytes.reserveCapacity(self.utf8.count)

		for byte in self.utf8 {
			if byte >= 0x41, byte <= 0x5A {
				hasUppercase = true
				bytes.append(byte + 0x20)
			}
			else {
				bytes.append(byte)
			}
		}

		guard hasUppercase else { return nil }
		return String(decoding: bytes, as: UTF8.self)
	}

	private static func asciiBytesEqual(_ lhs: UInt8, _ rhs: UInt8) -> Bool {
		let lowerLHS = lhs >= 0x41 && lhs <= 0x5A ? lhs + 0x20 : lhs
		let lowerRHS = rhs >= 0x41 && rhs <= 0x5A ? rhs + 0x20 : rhs
		return lowerLHS == lowerRHS
	}
}

private extension Substring {
	func asciiCaseInsensitiveEquals(_ other: String) -> Bool {
		guard self.utf8.count == other.utf8.count else { return false }
		return zip(self.utf8, other.utf8).allSatisfy { lhs, rhs in
			let lowerLHS = lhs >= 0x41 && lhs <= 0x5A ? lhs + 0x20 : lhs
			let lowerRHS = rhs >= 0x41 && rhs <= 0x5A ? rhs + 0x20 : rhs
			return lowerLHS == lowerRHS
		}
	}
}

// MARK: - Character Extensions

extension Character {
	var isNameChar: Bool {
		return isLetter || isNumber || self == "-" || self == "_"
	}

	func asciiCaseInsensitiveEquals(_ other: Character) -> Bool {
		guard let lhs = self.asciiValue, let rhs = other.asciiValue else {
			return self == other
		}
		let lowerLHS = lhs >= 0x41 && lhs <= 0x5A ? lhs + 0x20 : lhs
		let lowerRHS = rhs >= 0x41 && rhs <= 0x5A ? rhs + 0x20 : rhs
		return lowerLHS == lowerRHS
	}
}

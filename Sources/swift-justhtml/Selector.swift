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

// MARK: - Selector AST

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
        collectMatches(root, into: &results, checkRoot: true)
        return results
    }

    private func collectMatches(_ node: Node, into results: inout [Node], checkRoot: Bool) {
        if checkRoot && matches(node) {
            results.append(node)
        }
        for child in node.children {
            collectMatches(child, into: &results, checkRoot: true)
        }
        // Also check template content
        if let content = node.templateContent {
            collectMatches(content, into: &results, checkRoot: true)
        }
    }

    /// Check if a specific node matches this selector
    func matches(_ node: Node) -> Bool {
        switch self {
        case .simple(let simple):
            return simple.matches(node)

        case .compound(let simples):
            return simples.allSatisfy { $0.matches(node) }

        case .complex(let left, let combinator, let right):
            // For a complex selector, the right part must match the node
            guard right.matches(node) else { return false }
            // Then check the combinator relationship
            return combinator.check(left, node)

        case .group(let selectors):
            return selectors.contains { $0.matches(node) }
        }
    }
}

/// Simple selector components
indirect enum SimpleSelector {
    case universal                              // *
    case type(String)                           // tagname
    case id(String)                             // #id
    case `class`(String)                        // .class
    case attribute(AttributeSelector)           // [attr], [attr=val], etc.
    case pseudoClass(PseudoClass)              // :first-child, :nth-child(), etc.
    case pseudoElement(String)                  // ::before, ::after (not fully implemented)

    func matches(_ node: Node) -> Bool {
        switch self {
        case .universal:
            return node.name != "#document" && node.name != "#document-fragment" &&
                   node.name != "#text" && node.name != "#comment"

        case .type(let name):
            return node.name.lowercased() == name.lowercased()

        case .id(let id):
            return node.attrs["id"] == id

        case .class(let className):
            let classes = node.attrs["class"]?.split(separator: " ").map(String.init) ?? []
            return classes.contains(className)

        case .attribute(let attrSel):
            return attrSel.matches(node)

        case .pseudoClass(let pseudo):
            return pseudo.matches(node)

        case .pseudoElement:
            // Pseudo-elements don't match actual nodes
            return false
        }
    }
}

/// Attribute selector types
struct AttributeSelector {
    let name: String
    let operation: AttributeOperation?
    let value: String?
    let caseInsensitive: Bool

    func matches(_ node: Node) -> Bool {
        guard let attrValue = node.attrs[name] ?? node.attrs[name.lowercased()] else {
            return false  // attribute doesn't exist
        }

        guard let op = operation, let val = value else {
            return true  // [attr] - attribute exists, no value check needed
        }

        let compareValue = caseInsensitive ? attrValue.lowercased() : attrValue
        let targetValue = caseInsensitive ? val.lowercased() : val

        switch op {
        case .equals:         // [attr=val]
            return compareValue == targetValue
        case .includes:       // [attr~=val]
            return compareValue.split(separator: " ").map(String.init).contains(targetValue)
        case .dashMatch:      // [attr|=val]
            return compareValue == targetValue || compareValue.hasPrefix(targetValue + "-")
        case .prefix:         // [attr^=val]
            return compareValue.hasPrefix(targetValue)
        case .suffix:         // [attr$=val]
            return compareValue.hasSuffix(targetValue)
        case .substring:      // [attr*=val]
            return compareValue.contains(targetValue)
        }
    }
}

enum AttributeOperation {
    case equals        // =
    case includes      // ~=
    case dashMatch     // |=
    case prefix        // ^=
    case suffix        // $=
    case substring     // *=
}

/// Pseudo-class selectors
indirect enum PseudoClass {
    case firstChild
    case lastChild
    case onlyChild
    case nthChild(Int, Int)      // (an+b)
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

        case .nthChild(let a, let b):
            guard let index = node.childIndex else { return false }
            return matchesNth(index + 1, a: a, b: b)  // CSS indices are 1-based

        case .nthLastChild(let a, let b):
            guard let parent = node.parent else { return false }
            let siblings = parent.elementChildren
            guard let idx = siblings.firstIndex(where: { $0 === node }) else { return false }
            let indexFromEnd = siblings.count - idx
            return matchesNth(indexFromEnd, a: a, b: b)

        case .firstOfType:
            return node.isFirstOfType

        case .lastOfType:
            return node.isLastOfType

        case .onlyOfType:
            return node.isOnlyOfType

        case .nthOfType(let a, let b):
            guard let parent = node.parent else { return false }
            let sameType = parent.elementChildren.filter { $0.name == node.name }
            guard let idx = sameType.firstIndex(where: { $0 === node }) else { return false }
            return matchesNth(idx + 1, a: a, b: b)

        case .nthLastOfType(let a, let b):
            guard let parent = node.parent else { return false }
            let sameType = parent.elementChildren.filter { $0.name == node.name }
            guard let idx = sameType.firstIndex(where: { $0 === node }) else { return false }
            let indexFromEnd = sameType.count - idx
            return matchesNth(indexFromEnd, a: a, b: b)

        case .empty:
            return node.children.isEmpty ||
                   node.children.allSatisfy { $0.name == "#comment" }

        case .root:
            return node.parent?.name == "#document" || node.parent?.name == "#document-fragment"

        case .not(let selector):
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
        } else {
            return n <= 0 && n % a == 0
        }
    }
}

/// Combinators between selectors
enum Combinator {
    case descendant       // space
    case child            // >
    case nextSibling      // +
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
            var current = node.previousElementSibling
            while let sibling = current {
                if left.matches(sibling) {
                    return true
                }
                current = sibling.previousElementSibling
            }
            return false
        }
    }
}

// MARK: - Node Extensions for Selector Matching

extension Node {
    /// Get element children (excluding text, comments, etc.)
    var elementChildren: [Node] {
        return children.filter { !$0.name.hasPrefix("#") && $0.name != "!doctype" }
    }

    /// Index among element siblings
    var childIndex: Int? {
        guard let parent = parent else { return nil }
        return parent.elementChildren.firstIndex(where: { $0 === self })
    }

    var isFirstChild: Bool {
        return childIndex == 0
    }

    var isLastChild: Bool {
        guard let parent = parent else { return false }
        let elements = parent.elementChildren
        return elements.last === self
    }

    var isOnlyChild: Bool {
        guard let parent = parent else { return false }
        return parent.elementChildren.count == 1
    }

    var isFirstOfType: Bool {
        guard let parent = parent else { return false }
        return parent.elementChildren.first(where: { $0.name == name }) === self
    }

    var isLastOfType: Bool {
        guard let parent = parent else { return false }
        return parent.elementChildren.last(where: { $0.name == name }) === self
    }

    var isOnlyOfType: Bool {
        guard let parent = parent else { return false }
        return parent.elementChildren.filter { $0.name == name }.count == 1
    }

    var previousElementSibling: Node? {
        guard let parent = parent,
              let idx = parent.children.firstIndex(where: { $0 === self }),
              idx > 0 else { return nil }
        for i in stride(from: idx - 1, through: 0, by: -1) {
            let sibling = parent.children[i]
            if !sibling.name.hasPrefix("#") && sibling.name != "!doctype" {
                return sibling
            }
        }
        return nil
    }
}

// MARK: - Selector Parser

private struct SelectorParser {
    var input: String
    var position: String.Index

    init(_ input: String) {
        self.input = input
        self.position = input.startIndex
    }

    var current: Character? {
        return position < input.endIndex ? input[position] : nil
    }

    mutating func advance() {
        if position < input.endIndex {
            position = input.index(after: position)
        }
    }

    mutating func skipWhitespace() {
        while let ch = current, ch.isWhitespace {
            advance()
        }
    }

    mutating func parseSelector() throws -> Selector {
        var selectors: [Selector] = []

        repeat {
            skipWhitespace()
            let sel = try parseComplexSelector()
            selectors.append(sel)
            skipWhitespace()
        } while consume(",")

        if selectors.count == 1 {
            return selectors[0]
        }
        return .group(selectors)
    }

    mutating func parseComplexSelector() throws -> Selector {
        var left = try parseCompoundSelector()

        while true {
            let hadSpace = skipWhitespaceReturnIfAny()

            if let combinator = parseCombinator() {
                skipWhitespace()
                let right = try parseCompoundSelector()
                left = .complex(left, combinator, right)
            } else if hadSpace && current != nil && current != "," {
                // Descendant combinator (space)
                let right = try parseCompoundSelector()
                left = .complex(left, .descendant, right)
            } else {
                break
            }
        }

        return left
    }

    mutating func skipWhitespaceReturnIfAny() -> Bool {
        let hadSpace = current?.isWhitespace == true
        skipWhitespace()
        return hadSpace
    }

    mutating func parseCombinator() -> Combinator? {
        switch current {
        case ">":
            advance()
            return .child
        case "+":
            advance()
            return .nextSibling
        case "~":
            advance()
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
            throw SelectorError("Expected selector", position: input.distance(from: input.startIndex, to: position))
        }

        if simples.count == 1 {
            return .simple(simples[0])
        }
        return .compound(simples)
    }

    mutating func parseSimpleSelector() throws -> SimpleSelector? {
        switch current {
        case "*":
            advance()
            return .universal

        case "#":
            advance()
            let name = parseName()
            if name.isEmpty {
                throw SelectorError("Expected id name after #", position: input.distance(from: input.startIndex, to: position))
            }
            return .id(name)

        case ".":
            advance()
            let name = parseName()
            if name.isEmpty {
                throw SelectorError("Expected class name after .", position: input.distance(from: input.startIndex, to: position))
            }
            return .class(name)

        case "[":
            return try .attribute(parseAttributeSelector())

        case ":":
            return try parsePseudoSelector()

        default:
            let name = parseName()
            if !name.isEmpty {
                return .type(name)
            }
            return nil
        }
    }

    mutating func parseName() -> String {
        var name = ""
        while let ch = current, ch.isNameChar {
            name.append(ch)
            advance()
        }
        return name
    }

    mutating func consume(_ expected: Character) -> Bool {
        if current == expected {
            advance()
            return true
        }
        return false
    }

    mutating func parseAttributeSelector() throws -> AttributeSelector {
        guard consume("[") else {
            throw SelectorError("Expected [", position: input.distance(from: input.startIndex, to: position))
        }
        skipWhitespace()

        let attrName = parseName()
        if attrName.isEmpty {
            throw SelectorError("Expected attribute name", position: input.distance(from: input.startIndex, to: position))
        }

        skipWhitespace()

        // Check for operator
        var operation: AttributeOperation? = nil
        if current == "=" {
            advance()
            operation = .equals
        } else if current == "~" && peek(1) == "=" {
            advance(); advance()
            operation = .includes
        } else if current == "|" && peek(1) == "=" {
            advance(); advance()
            operation = .dashMatch
        } else if current == "^" && peek(1) == "=" {
            advance(); advance()
            operation = .prefix
        } else if current == "$" && peek(1) == "=" {
            advance(); advance()
            operation = .suffix
        } else if current == "*" && peek(1) == "=" {
            advance(); advance()
            operation = .substring
        }

        var value: String? = nil
        var caseInsensitive = false

        if operation != nil {
            skipWhitespace()
            value = try parseAttributeValue()
            skipWhitespace()

            // Check for case-insensitivity flag
            if current == "i" || current == "I" {
                caseInsensitive = true
                advance()
                skipWhitespace()
            }
        }

        guard consume("]") else {
            throw SelectorError("Expected ]", position: input.distance(from: input.startIndex, to: position))
        }

        return AttributeSelector(name: attrName, operation: operation, value: value, caseInsensitive: caseInsensitive)
    }

    func peek(_ offset: Int) -> Character? {
        guard let idx = input.index(position, offsetBy: offset, limitedBy: input.endIndex) else { return nil }
        return idx < input.endIndex ? input[idx] : nil
    }

    mutating func parseAttributeValue() throws -> String {
        if current == "\"" || current == "'" {
            return try parseQuotedString()
        }
        return parseName()
    }

    mutating func parseQuotedString() throws -> String {
        let quote = current!
        advance()

        var result = ""
        while let ch = current, ch != quote {
            if ch == "\\" {
                advance()
                if let escaped = current {
                    result.append(escaped)
                    advance()
                }
            } else {
                result.append(ch)
                advance()
            }
        }

        guard consume(quote) else {
            throw SelectorError("Unterminated string", position: input.distance(from: input.startIndex, to: position))
        }

        return result
    }

    mutating func parsePseudoSelector() throws -> SimpleSelector {
        guard consume(":") else {
            throw SelectorError("Expected :", position: input.distance(from: input.startIndex, to: position))
        }

        // Check for pseudo-element (::)
        if consume(":") {
            let name = parseName()
            return .pseudoElement(name)
        }

        let name = parseName().lowercased()

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
            guard consume("(") else {
                throw SelectorError("Expected ( after :not", position: input.distance(from: input.startIndex, to: position))
            }
            skipWhitespace()
            let inner = try parseCompoundSelector()
            skipWhitespace()
            guard consume(")") else {
                throw SelectorError("Expected ) after :not selector", position: input.distance(from: input.startIndex, to: position))
            }
            return .pseudoClass(.not(inner))
        default:
            throw SelectorError("Unknown pseudo-class: \(name)", position: input.distance(from: input.startIndex, to: position))
        }
    }

    mutating func parseNth() throws -> (Int, Int) {
        guard consume("(") else {
            throw SelectorError("Expected ( for nth expression", position: input.distance(from: input.startIndex, to: position))
        }
        skipWhitespace()

        var a = 0
        var b = 0

        // Parse "odd", "even", or "an+b" expression
        if consumeKeyword("odd") {
            a = 2
            b = 1
        } else if consumeKeyword("even") {
            a = 2
            b = 0
        } else {
            // Parse an+b
            let result = try parseAnPlusB()
            a = result.0
            b = result.1
        }

        skipWhitespace()
        guard consume(")") else {
            throw SelectorError("Expected ) after nth expression", position: input.distance(from: input.startIndex, to: position))
        }

        return (a, b)
    }

    mutating func consumeKeyword(_ keyword: String) -> Bool {
        let remaining = String(input[position...])
        if remaining.lowercased().hasPrefix(keyword.lowercased()) {
            let nextIdx = input.index(position, offsetBy: keyword.count)
            if nextIdx >= input.endIndex || !input[nextIdx].isNameChar {
                position = nextIdx
                return true
            }
        }
        return false
    }

    mutating func parseAnPlusB() throws -> (Int, Int) {
        var a = 0
        var b = 0
        var sign = 1

        // Optional leading sign
        if consume("-") {
            sign = -1
        } else if consume("+") {
            sign = 1
        }

        // Check for 'n'
        if current == "n" || current == "N" {
            a = sign
            advance()
        } else if let ch = current, ch.isNumber {
            // Parse number
            var num = parseNumber()
            num *= sign

            // Check if followed by 'n'
            if current == "n" || current == "N" {
                a = num
                advance()
            } else {
                // Just a number
                b = num
                skipWhitespace()
                guard consume(")") else {
                    throw SelectorError("Expected ) after number", position: input.distance(from: input.startIndex, to: position))
                }
                // Put back the )
                position = input.index(before: position)
                return (0, b)
            }
        } else {
            throw SelectorError("Invalid nth expression", position: input.distance(from: input.startIndex, to: position))
        }

        // Now we have 'a' and have consumed 'n', parse optional +/- b
        skipWhitespace()
        if consume("+") {
            skipWhitespace()
            b = parseNumber()
        } else if consume("-") {
            skipWhitespace()
            b = -parseNumber()
        }

        return (a, b)
    }

    mutating func parseNumber() -> Int {
        var numStr = ""
        while let ch = current, ch.isNumber {
            numStr.append(ch)
            advance()
        }
        return Int(numStr) ?? 0
    }
}

// MARK: - Character Extensions

extension Character {
    var isNameChar: Bool {
        return isLetter || isNumber || self == "-" || self == "_"
    }
}

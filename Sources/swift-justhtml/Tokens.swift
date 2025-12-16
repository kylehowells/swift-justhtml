// Tokens.swift - Token types for the HTML tokenizer

import Foundation

/// Token types emitted by the tokenizer
public enum Token {
    case startTag(name: String, attrs: [String: String], selfClosing: Bool)
    case endTag(name: String)
    case character(String)
    case comment(String)
    case doctype(Doctype)
    case eof
}

/// Parse error with location information
public struct ParseError: Error, CustomStringConvertible, Sendable {
    /// Error code (kebab-case, matches html5lib-tests)
    public let code: String

    /// Human-readable message
    public let message: String

    /// Line number (1-based)
    public let line: Int?

    /// Column number (1-based)
    public let column: Int?

    public init(code: String, message: String? = nil, line: Int? = nil, column: Int? = nil) {
        self.code = code
        self.message = message ?? code
        self.line = line
        self.column = column
    }

    public var description: String {
        if let line = line, let column = column {
            return "(\(line),\(column)): \(code)"
        }
        return code
    }
}

/// Thrown when strict mode encounters a parse error
public struct StrictModeError: Error {
    public let parseError: ParseError

    public init(_ parseError: ParseError) {
        self.parseError = parseError
    }
}

/// Thrown on invalid CSS selector syntax
public struct SelectorError: Error {
    public let message: String
    public let position: Int?

    public init(_ message: String, position: Int? = nil) {
        self.message = message
        self.position = position
    }
}

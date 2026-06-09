// Tokens.swift - Token types for the HTML tokenizer

import Foundation

// MARK: - Token

/// Token types emitted by the tokenizer
public enum Token {
	case startTag(name: String, attrs: [String: String], selfClosing: Bool)
	case endTag(name: String)
	case character(String)
	case comment(String)
	case doctype(Doctype)
	case eof
}

// MARK: - ParseError

/// Parse error with location information
public struct ParseError: Error, CustomStringConvertible, LocalizedError, Sendable {
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
		self.message = message ?? Self.message(for: code)
		self.line = line
		self.column = column
	}

	public var errorDescription: String? {
		return self.description
	}

	public var description: String {
		if let line = line, let column = column {
			return "(\(line),\(column)): \(self.message) [\(self.code)]"
		}
		return "\(self.message) [\(self.code)]"
	}

	private static func message(for code: String) -> String {
		var words: [String] = []
		words.reserveCapacity(8)

		for part in code.split(separator: "-") {
			switch part {
				case "eof":
					words.append("EOF")
				case "doctype":
					words.append("DOCTYPE")
				case "cdata":
					words.append("CDATA")
				case "html":
					words.append("HTML")
				case "svg":
					words.append("SVG")
				default:
					words.append(String(part))
			}
		}

		guard let first = words.first else { return code }
		let sentence = ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(
			separator: " ")
		return sentence
	}
}

// MARK: - StrictModeError

/// Thrown when strict mode encounters a parse error
public struct StrictModeError: Error {
	public let parseError: ParseError

	public init(_ parseError: ParseError) {
		self.parseError = parseError
	}
}

// MARK: - SelectorError

/// Thrown on invalid CSS selector syntax
public struct SelectorError: Error, CustomStringConvertible {
	public let message: String
	public let position: Int?

	public init(_ message: String, position: Int? = nil) {
		self.message = message
		self.position = position
	}

	public var description: String {
		if let pos = position {
			return "SelectorError at position \(pos): \(self.message)"
		}
		return "SelectorError: \(self.message)"
	}
}

// JustHTML.swift - Main parser entry point

import Foundation

/// JustHTML - A dependency-free HTML5 parser for Swift
public struct JustHTML {
	/// The parsed document root (#document or #document-fragment)
	public let root: Node

	/// Parse errors encountered (empty unless collectErrors or strict mode)
	public let errors: [ParseError]

	/// Detected encoding when parsing from Data (nil for String input)
	public let encoding: String?

	/// Fragment context if parsing a fragment
	public let fragmentContext: FragmentContext?

	/// Initialize with an HTML string
	/// - Parameters:
	///   - html: The HTML string to parse
	///   - fragmentContext: Optional fragment context for parsing fragments
	///   - collectErrors: Whether to collect parse errors
	///   - strict: Whether to throw on first parse error
	///   - scripting: Whether scripting is enabled
	///   - iframeSrcdoc: Whether parsing iframe srcdoc content
	///   - xmlCoercion: Whether to coerce output for XML compatibility
	/// - Throws: StrictModeError if strict mode is enabled and a parse error occurs
	public init(
		_ html: String,
		fragmentContext: FragmentContext? = nil,
		collectErrors: Bool = false,
		strict: Bool = false,
		scripting: Bool = false,
		iframeSrcdoc: Bool = false,
		xmlCoercion: Bool = false
	) throws {
		self.fragmentContext = fragmentContext
		self.encoding = nil

		let shouldCollect = collectErrors || strict

		let treeBuilder = TreeBuilder(
			fragmentContext: fragmentContext,
			iframeSrcdoc: iframeSrcdoc,
			collectErrors: shouldCollect,
			scripting: scripting
		)

		let opts = Self.tokenizerOpts(
			fragmentContext: fragmentContext,
			xmlCoercion: xmlCoercion,
			scripting: scripting
		)

		let tokenizer = Tokenizer(treeBuilder, opts: opts, collectErrors: shouldCollect)
		treeBuilder.tokenizer = tokenizer

		tokenizer.run(html)

		self.root = treeBuilder.finish()
		self.errors = tokenizer.errors + treeBuilder.errors

		if strict, !self.errors.isEmpty {
			throw StrictModeError(self.errors[0])
		}
	}

	/// Initialize with raw bytes (auto-detects encoding)
	/// - Parameters:
	///   - data: The raw bytes to parse
	///   - transportEncoding: Optional transport-layer encoding override (e.g., from HTTP headers)
	///   - fragmentContext: Optional fragment context for parsing fragments
	///   - collectErrors: Whether to collect parse errors
	///   - strict: Whether to throw on first parse error
	///   - scripting: Whether scripting is enabled
	///   - iframeSrcdoc: Whether parsing iframe srcdoc content
	///   - xmlCoercion: Whether to coerce output for XML compatibility
	/// - Throws: StrictModeError if strict mode is enabled and a parse error occurs
	public init(
		data: Data,
		transportEncoding: String? = nil,
		fragmentContext: FragmentContext? = nil,
		collectErrors: Bool = false,
		strict: Bool = false,
		scripting: Bool = false,
		iframeSrcdoc: Bool = false,
		xmlCoercion: Bool = false
	) throws {
		let (html, detectedEncoding) = decodeHTML(data, transportEncoding: transportEncoding)

		self.fragmentContext = fragmentContext
		self.encoding = detectedEncoding

		let shouldCollect = collectErrors || strict

		let treeBuilder = TreeBuilder(
			fragmentContext: fragmentContext,
			iframeSrcdoc: iframeSrcdoc,
			collectErrors: shouldCollect,
			scripting: scripting
		)

		let opts = Self.tokenizerOpts(
			fragmentContext: fragmentContext,
			xmlCoercion: xmlCoercion,
			scripting: scripting
		)

		let tokenizer = Tokenizer(treeBuilder, opts: opts, collectErrors: shouldCollect)
		treeBuilder.tokenizer = tokenizer

		tokenizer.run(html)

		self.root = treeBuilder.finish()
		self.errors = tokenizer.errors + treeBuilder.errors

		if strict, !self.errors.isEmpty {
			throw StrictModeError(self.errors[0])
		}
	}

	// MARK: - Convenience Methods

	/// Query the document using a CSS selector
	/// - Parameter selector: The CSS selector
	/// - Returns: Array of matching nodes
	public func query(_ selector: String) throws -> [Node] {
		return try justhtml.query(self.root, selector: selector)
	}

	/// Serialize the document to HTML
	/// - Parameters:
	///   - pretty: Whether to format with indentation
	///   - indentSize: Number of spaces per indent level
	/// - Returns: HTML string
	public func toHTML(pretty: Bool = true, indentSize: Int = 2) -> String {
		return self.root.toHTML(pretty: pretty, indentSize: indentSize)
	}

	/// Extract all text content from the document
	/// - Parameters:
	///   - separator: String to insert between text parts (default: "" to preserve original spacing)
	///   - strip: If true, trim whitespace from each text node (default: false to preserve spacing)
	///   - collapseWhitespace: If true, collapse runs of whitespace to single spaces (default: true)
	/// - Returns: Plain text content of the document
	public func toText(separator: String = "", strip: Bool = false, collapseWhitespace: Bool = true)
		-> String
	{
		return self.root.toText(
			separator: separator, strip: strip, collapseWhitespace: collapseWhitespace)
	}

	/// Convert to html5lib test format
	/// - Returns: Test format string
	public func toTestFormat() -> String {
		return self.root.toTestFormat()
	}

	/// Convert to Markdown (GitHub-Flavored Markdown subset)
	/// - Returns: Markdown string
	public func toMarkdown() -> String {
		return self.root.toMarkdown()
	}

	// MARK: - Private Helpers

	/// Configure tokenizer options for fragment context
	private static func tokenizerOpts(
		fragmentContext: FragmentContext?,
		xmlCoercion: Bool,
		scripting: Bool
	) -> TokenizerOpts {
		var opts = TokenizerOpts()
		opts.xmlCoercion = xmlCoercion
		opts.scripting = scripting

		// Handle special fragment contexts that affect tokenizer initial state
		// Note: We DON'T set initialRawtextTag for fragments because no start tag was emitted,
		// so no end tag should be considered "appropriate" per WHATWG spec
		if let ctx = fragmentContext, ctx.namespace == nil || ctx.namespace == .html {
			let tagName = ctx.tagName.lowercased()
			switch tagName {
				case "title", "textarea":
					opts.initialState = .rcdata

				case "style", "xmp", "iframe", "noembed", "noframes":
					opts.initialState = .rawtext

				case "noscript" where scripting:
					// When scripting is enabled, noscript content is raw text
					opts.initialState = .rawtext

				case "script":
					opts.initialState = .scriptData

				case "plaintext":
					opts.initialState = .plaintext

				default:
					break
			}
		}

		return opts
	}
}

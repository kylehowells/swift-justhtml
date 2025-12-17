import Foundation
import Testing
@testable import justhtml

// MARK: - Serializer Tests

private let VOID_ELEMENTS: Set<String> = [
	"area", "base", "br", "col", "embed", "hr", "img", "input",
	"link", "meta", "param", "source", "track", "wbr",
]

/// Serialize a token stream for html5lib serializer tests
func serializeSerializerTokenStream(_ tokens: [[Any]], options: [String: Any] = [:]) -> String? {
	var parts: [String] = []
	var rawtext: String? = nil
	let escapeRcdata = options["escape_rcdata"] as? Bool ?? false
	let stripWhitespace = options["strip_whitespace"] as? Bool ?? (options["strip_whitespace"] as? Int == 1)
	let injectMetaCharset = options["inject_meta_charset"] as? Bool ?? (options["inject_meta_charset"] as? Int == 1)
	let encoding = options["encoding"] as? String
	let useTrailingSolidus = options["use_trailing_solidus"] as? Bool ?? (options["use_trailing_solidus"] as? Int == 1)
	var openElements: [String] = []
	var preserveWhitespace = false // Track if we're in pre/textarea/script/style
	var foundCharsetMeta = false // Track if we found existing charset meta in head
	var headStartIndex = -1 // Track where head content starts for possible injection

	for i in 0 ..< tokens.count {
		let token = tokens[i]
		guard let kind = token.first as? String else { continue }

		let prevToken = i > 0 ? tokens[i - 1] : nil
		let nextToken = i + 1 < tokens.count ? tokens[i + 1] : nil

		switch kind {
			case "StartTag":
				// ["StartTag", namespace, name, attrs]
				guard token.count >= 3 else { continue }

				let name = (token[2] as? String)?.lowercased() ?? ""
				let attrs = parseSerializerAttrs(token.count > 3 ? token[3] : [])

				openElements.append(name)

				// Track preserve whitespace elements
				if ["pre", "textarea", "script", "style"].contains(name) {
					preserveWhitespace = true
					if ["script", "style"].contains(name), !escapeRcdata {
						rawtext = name
					}
				}

				// Track head element for inject_meta_charset
				if name == "head" {
					headStartIndex = parts.count
				}

				// Check if start tag should be omitted
				if shouldOmitStartTag(name, attrs: attrs, prevToken: prevToken, nextToken: nextToken) {
					continue
				}

				parts.append(
					serializeStartTag(
						name, attrs: attrs, options: options, isVoid: VOID_ELEMENTS.contains(name)))

			case "EndTag":
				// ["EndTag", namespace, name]
				guard token.count >= 3 else { continue }

				let name = (token[2] as? String)?.lowercased() ?? ""

				// Pop from open elements
				if let idx = openElements.lastIndex(of: name) {
					openElements.remove(at: idx)
				}

				// Track preserve whitespace elements
				if ["pre", "textarea", "script", "style"].contains(name) {
					preserveWhitespace = openElements.contains(where: { ["pre", "textarea", "script", "style"].contains($0) })
				}

				// At end of head, inject meta charset if needed and we didn't find one
				if name == "head" {
					if injectMetaCharset, let enc = encoding, !foundCharsetMeta {
						// Insert at beginning of head content
						if headStartIndex >= 0, headStartIndex <= parts.count {
							parts.insert("<meta charset=\(enc)>", at: headStartIndex)
						}
						else {
							parts.append("<meta charset=\(enc)>")
						}
					}
					foundCharsetMeta = false
					headStartIndex = -1
				}

				if rawtext == name {
					rawtext = nil
				}

				// Check if end tag should be omitted
				let nextNextToken = i + 2 < tokens.count ? tokens[i + 2] : nil
				if shouldOmitEndTag(name, nextToken: nextToken, nextNextToken: nextNextToken) {
					continue
				}

				parts.append("</\(name)>")

			case "EmptyTag":
				// ["EmptyTag", name, attrs]
				guard token.count >= 2 else { continue }

				let name = (token[1] as? String)?.lowercased() ?? ""
				var attrs = parseSerializerAttrs(token.count > 2 ? token[2] : [:])

				// Handle inject_meta_charset for meta tags
				if injectMetaCharset, let enc = encoding, name == "meta" {
					// Check if this is a charset meta tag
					if attrs["charset"] != nil {
						attrs["charset"] = enc
						foundCharsetMeta = true
					}
					// Check if this is an http-equiv content-type meta tag
					else if let httpEquiv = attrs["http-equiv"], httpEquiv.lowercased() == "content-type" {
						if let content = attrs["content"] {
							// Replace charset in content attribute
							let charsetPattern = try? NSRegularExpression(pattern: "charset=[^;\\s]+", options: .caseInsensitive)
							if let regex = charsetPattern {
								let range = NSRange(content.startIndex..., in: content)
								let newContent = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "charset=\(enc)")
								attrs["content"] = newContent
							}
						}
						foundCharsetMeta = true
					}
				}

				parts.append(serializeStartTag(name, attrs: attrs, options: options, isVoid: true, useTrailingSolidus: useTrailingSolidus))

			case "Characters":
				guard token.count >= 2 else { continue }

				var text = token[1] as? String ?? ""

				// Handle strip_whitespace
				if stripWhitespace, !preserveWhitespace, rawtext == nil {
					text = collapseWhitespaceForSerializer(text)
				}

				if rawtext != nil {
					parts.append(text)
				}
				else {
					parts.append(escapeTextForSerializer(text))
				}

			case "Comment":
				guard token.count >= 2 else { continue }

				let text = token[1] as? String ?? ""
				parts.append("<!--\(text)-->")

			case "Doctype":
				// ["Doctype", name, publicId?, systemId?]
				let name = token.count > 1 ? (token[1] as? String ?? "") : ""
				let publicId = token.count > 2 ? token[2] as? String : nil
				let systemId = token.count > 3 ? token[3] as? String : nil

				if publicId == nil, systemId == nil {
					parts.append("<!DOCTYPE \(name)>")
				}
				else if let pub = publicId, !pub.isEmpty {
					if let sys = systemId, !sys.isEmpty {
						parts.append("<!DOCTYPE \(name) PUBLIC \"\(pub)\" \"\(sys)\">")
					}
					else {
						parts.append("<!DOCTYPE \(name) PUBLIC \"\(pub)\">")
					}
				}
				else if let sys = systemId, !sys.isEmpty {
					parts.append("<!DOCTYPE \(name) SYSTEM \"\(sys)\">")
				}
				else {
					parts.append("<!DOCTYPE \(name)>")
				}

			default:
				continue
		}
	}

	return parts.joined()
}

/// Collapse whitespace for strip_whitespace option
/// Whitespace characters are: space, tab, LF, CR, form feed (U+000C)
/// Note: Must iterate over unicode scalars since Swift treats CR+LF as a single grapheme cluster
func collapseWhitespaceForSerializer(_ text: String) -> String {
	var result = ""
	var lastWasWhitespace = false

	for scalar in text.unicodeScalars {
		// Check for HTML whitespace: space (0x20), tab (0x09), LF (0x0A), CR (0x0D), FF (0x0C)
		let isWhitespace = scalar.value == 0x20 || scalar.value == 0x09 ||
			scalar.value == 0x0A || scalar.value == 0x0D || scalar.value == 0x0C

		if isWhitespace {
			if !lastWasWhitespace {
				result.append(" ")
				lastWasWhitespace = true
			}
		}
		else {
			result.append(Character(scalar))
			lastWasWhitespace = false
		}
	}
	return result
}

/// Check if a start tag should be omitted per HTML5 optional tag rules
func shouldOmitStartTag(
	_ name: String, attrs: [String: String], prevToken _: [Any]?, nextToken: [Any]?
) -> Bool {
	// Can't omit if it has attributes
	if !attrs.isEmpty { return false }

	// Check what follows
	let nextKind = nextToken?.first as? String

	switch name {
		case "html":
			// html start tag can be omitted if not followed by a comment
			if nextKind == "Comment" { return false }
			// Also can't omit if followed by space character at start
			if nextKind == "Characters", let text = nextToken?[1] as? String {
				if text.hasPrefix(" ") || text.hasPrefix("\t") || text.hasPrefix("\n") || text.hasPrefix("\r")
					|| text.hasPrefix("\u{0C}")
				{
					return false
				}
			}
			return true

		case "head":
			// head start tag can be omitted if element is empty or first child is an element
			if nextKind == nil { return true }
			if nextKind == "StartTag" || nextKind == "EmptyTag" { return true }
			// Also omit if followed by head end tag (empty element)
			if nextKind == "EndTag", let nextName = nextToken?[2] as? String {
				if nextName.lowercased() == "head" { return true }
			}
			return false

		case "body":
			// body start tag can be omitted if element is empty or first child is not space/comment/certain elements
			if nextKind == nil { return true }
			if nextKind == "Comment" { return false }
			if nextKind == "Characters", let text = nextToken?[1] as? String {
				if text.hasPrefix(" ") || text.hasPrefix("\t") || text.hasPrefix("\n") || text.hasPrefix("\r")
					|| text.hasPrefix("\u{0C}")
				{
					return false
				}
			}
			// Can't omit if followed by certain elements
			if nextKind == "StartTag", let nextName = nextToken?[2] as? String {
				let cantOmitBefore = ["meta", "link", "script", "style", "template"]
				if cantOmitBefore.contains(nextName.lowercased()) {
					return false
				}
			}
			return true

		case "colgroup":
			// colgroup start tag can be omitted if first child is col
			if nextKind == "StartTag", let nextName = nextToken?[2] as? String {
				return nextName.lowercased() == "col"
			}
			if nextKind == "EmptyTag", let nextName = nextToken?[1] as? String {
				return nextName.lowercased() == "col"
			}
			return false

		case "tbody":
			// tbody start tag can be omitted if first child is tr
			if nextKind == "StartTag", let nextName = nextToken?[2] as? String {
				return nextName.lowercased() == "tr"
			}
			return false

		default:
			return false
	}
}

/// Check if an end tag should be omitted per HTML5 optional tag rules
func shouldOmitEndTag(_ name: String, nextToken: [Any]?, nextNextToken: [Any]? = nil) -> Bool {
	let nextKind = nextToken?.first as? String
	let nextName = {
		if nextKind == "StartTag" { return (nextToken?[2] as? String)?.lowercased() }
		if nextKind == "EndTag" { return (nextToken?[2] as? String)?.lowercased() }
		if nextKind == "EmptyTag" { return (nextToken?[1] as? String)?.lowercased() }
		return nil
	}()

	// Helper to check if a following tbody start tag would be omitted
	let tbodyStartWouldBeOmitted: Bool = {
		guard nextName == "tbody", nextKind == "StartTag" else { return false }

		// tbody start tag is omitted if first child is tr
		if let nnKind = nextNextToken?.first as? String {
			if nnKind == "StartTag", let nnName = nextNextToken?[2] as? String {
				return nnName.lowercased() == "tr"
			}
		}
		return false
	}()

	switch name {
		case "html":
			// html end tag can be omitted if not followed by comment or whitespace
			if nextKind == "Comment" { return false }
			if nextKind == "Characters", let text = nextToken?[1] as? String {
				if text.hasPrefix(" ") || text.hasPrefix("\t") || text.hasPrefix("\n") || text.hasPrefix("\r")
					|| text.hasPrefix("\u{0C}")
				{
					return false
				}
			}
			return true

		case "head":
			// head end tag can be omitted if not followed by space or comment
			if nextKind == "Comment" { return false }
			if nextKind == "Characters", let text = nextToken?[1] as? String {
				if text.hasPrefix(" ") || text.hasPrefix("\t") || text.hasPrefix("\n") || text.hasPrefix("\r")
					|| text.hasPrefix("\u{0C}")
				{
					return false
				}
			}
			return true

		case "body":
			// body end tag can be omitted if not followed by comment or whitespace
			if nextKind == "Comment" { return false }
			if nextKind == "Characters", let text = nextToken?[1] as? String {
				if text.hasPrefix(" ") || text.hasPrefix("\t") || text.hasPrefix("\n") || text.hasPrefix("\r")
					|| text.hasPrefix("\u{0C}")
				{
					return false
				}
			}
			return true

		case "li":
			// li end tag can be omitted if followed by li or end of parent
			return nextKind == nil || nextName == "li" || nextKind == "EndTag"

		case "dt":
			// dt end tag can be omitted if followed by dt or dd
			return nextName == "dt" || nextName == "dd"

		case "dd":
			// dd end tag can be omitted if followed by dd, dt, or end of parent
			return nextKind == nil || nextName == "dd" || nextName == "dt" || nextKind == "EndTag"

		case "p":
			// p end tag can be omitted if followed by certain elements
			let omitBefore: Set<String> = [
				"address", "article", "aside", "blockquote", "datagrid", "details",
				"dialog", "dir", "div", "dl", "fieldset", "figcaption", "figure",
				"footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup",
				"hr", "main", "menu", "nav", "ol", "p", "pre", "search", "section",
				"table", "ul",
			]
			if let next = nextName, omitBefore.contains(next) { return true }
			if nextKind == "EndTag" { return true }
			if nextKind == nil { return true }
			return false

		case "rt", "rp":
			return nextName == "rt" || nextName == "rp" || nextKind == "EndTag" || nextKind == nil

		case "optgroup":
			return nextName == "optgroup" || nextKind == "EndTag" || nextKind == nil

		case "option":
			return nextName == "option" || nextName == "optgroup" || nextKind == "EndTag" || nextKind == nil

		case "colgroup":
			// colgroup end tag can be omitted if not followed by space or comment
			// But NOT if followed by colgroup start tag (would merge elements)
			if nextKind == "Comment" { return false }
			if nextKind == "Characters", let text = nextToken?[1] as? String {
				if text.hasPrefix(" ") || text.hasPrefix("\t") { return false }
			}
			if nextKind == "StartTag", nextName == "colgroup" { return false }
			return true

		case "caption":
			return true // caption end tag can always be omitted when followed properly

		case "thead":
			// thead end tag can be omitted if followed by tbody or tfoot
			// But NOT if the tbody start tag would also be omitted (would merge elements)
			if nextName == "tfoot" { return true }
			if nextName == "tbody" {
				// If tbody start would be omitted (has tr child), keep this end tag
				// Otherwise (tbody start kept), omit this end tag
				return !tbodyStartWouldBeOmitted
			}
			return false

		case "tbody":
			// tbody end tag can be omitted if followed by tbody, tfoot, or end of parent
			// But NOT if the next tbody start tag would also be omitted (would merge elements)
			if nextName == "tfoot" { return true }
			if nextKind == "EndTag" || nextKind == nil { return true }
			if nextName == "tbody" {
				// If tbody start would be omitted, keep this end tag
				// Otherwise, omit this end tag
				return !tbodyStartWouldBeOmitted
			}
			return false

		case "tfoot":
			if nextKind == "EndTag" || nextKind == nil { return true }
			if nextName == "tbody" {
				return !tbodyStartWouldBeOmitted
			}
			return false

		case "tr":
			return nextName == "tr" || nextKind == "EndTag" || nextKind == nil

		case "td", "th":
			return nextName == "td" || nextName == "th" || nextKind == "EndTag" || nextKind == nil

		default:
			return false
	}
}

func parseSerializerAttrs(_ input: Any) -> [String: String] {
	var result: [String: String] = [:]

	if let arr = input as? [[String: Any]] {
		// Array of {namespace, name, value} objects
		for item in arr {
			if let name = item["name"] as? String,
			   let value = item["value"] as? String
			{
				result[name] = value
			}
		}
	}
	else if let dict = input as? [String: Any] {
		// Simple dict
		for (key, val) in dict {
			if let str = val as? String {
				result[key] = str
			}
			else {
				result[key] = ""
			}
		}
	}

	return result
}

func serializeStartTag(
	_ name: String, attrs: [String: String], options: [String: Any], isVoid: Bool, useTrailingSolidus: Bool = false
) -> String {
	var result = "<\(name)"

	// Sort attributes for deterministic output
	let sortedAttrs = attrs.sorted { $0.key < $1.key }

	for (attrName, attrValue) in sortedAttrs {
		result += " "
		result += serializeAttribute(attrName, value: attrValue, options: options)
	}

	// Add trailing solidus for void elements if requested
	if isVoid, useTrailingSolidus {
		result += " />"
	}
	else {
		result += ">"
	}
	return result
}

func serializeAttribute(_ name: String, value: String, options: [String: Any]) -> String {
	let quoteAttrValues = options["quote_attr_values"] as? Bool ?? (options["quote_attr_values"] as? Int == 1)
	let escapeLtInAttrs = options["escape_lt_in_attrs"] as? Bool ?? (options["escape_lt_in_attrs"] as? Int == 1)
	let customQuoteChar = options["quote_char"] as? String
	let minimizeBooleanAttrs = options["minimize_boolean_attributes"] as? Bool ?? (options["minimize_boolean_attributes"] as? Int != 0)

	// Handle quote_attr_values option: if name equals value, just output name
	if quoteAttrValues, name == value {
		return name
	}

	// Handle minimize_boolean_attributes=false with empty value
	if !minimizeBooleanAttrs, value.isEmpty {
		return "\(name)=\"\""
	}

	// Determine quote character needed
	let hasDoubleQuote = value.contains("\"")
	let hasSingleQuote = value.contains("'")
	let needsQuotes =
		value.isEmpty || value.contains(" ") || value.contains("\t") || value.contains("\n")
			|| value.contains("\r") || value.contains("\u{0C}") || value.contains("=")
			|| value.contains(">") || value.contains("`")

	if !needsQuotes, !hasDoubleQuote, !hasSingleQuote, customQuoteChar == nil {
		// Unquoted attribute
		var escaped = value.replacingOccurrences(of: "&", with: "&amp;")
		if escapeLtInAttrs {
			escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
		}
		return "\(name)=\(escaped)"
	}

	// Choose quote character
	let quoteChar: Character
	if let custom = customQuoteChar, !custom.isEmpty {
		quoteChar = custom.first!
	}
	else if hasDoubleQuote, !hasSingleQuote {
		quoteChar = "'"
	}
	else if hasSingleQuote, !hasDoubleQuote {
		quoteChar = "\""
	}
	else if hasDoubleQuote, hasSingleQuote {
		// Escape double quotes
		quoteChar = "\""
	}
	else {
		quoteChar = "\""
	}

	// Escape value
	var escaped = value.replacingOccurrences(of: "&", with: "&amp;")
	if escapeLtInAttrs {
		escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
	}
	if quoteChar == "\"" {
		escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
	}
	else if quoteChar == "'" {
		escaped = escaped.replacingOccurrences(of: "'", with: "&#39;")
	}

	return "\(name)=\(quoteChar)\(escaped)\(quoteChar)"
}

func escapeTextForSerializer(_ text: String) -> String {
	var result = text
	result = result.replacingOccurrences(of: "&", with: "&amp;")
	result = result.replacingOccurrences(of: "<", with: "&lt;")
	result = result.replacingOccurrences(of: ">", with: "&gt;")
	return result
}

func getSerializerTestsDirectory() -> URL? {
	let fileManager = FileManager.default
	let cwd = fileManager.currentDirectoryPath
	let cwdUrl = URL(fileURLWithPath: cwd)

	let possiblePaths = [
		cwdUrl.appendingPathComponent("html5lib-tests/serializer"),
		cwdUrl.appendingPathComponent("../html5lib-tests/serializer"),
	]

	for path in possiblePaths {
		if fileManager.fileExists(atPath: path.path) {
			return path
		}
	}
	return nil
}

@Test func html5libSerializerTests() async throws {
	guard let testsDir = getSerializerTestsDirectory() else {
		print("Serializer tests directory not found")
		return
	}

	let fileManager = FileManager.default
	var testFiles: [URL] = []

	if let enumerator = fileManager.enumerator(at: testsDir, includingPropertiesForKeys: nil) {
		while let url = enumerator.nextObject() as? URL {
			if url.pathExtension == "test" {
				testFiles.append(url)
			}
		}
	}

	testFiles.sort { $0.lastPathComponent < $1.lastPathComponent }

	var totalPassed = 0
	var totalFailed = 0

	for fileURL in testFiles {
		let filename = fileURL.lastPathComponent
		guard let content = try? Data(contentsOf: fileURL),
		      let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any],
		      let tests = json["tests"] as? [[String: Any]]
		else {
			continue
		}

		var passed = 0
		var failed = 0

		for (idx, test) in tests.enumerated() {
			let options = test["options"] as? [String: Any] ?? [:]

			guard let input = test["input"] as? [[Any]] else {
				failed += 1
				print("\nSERIALIZER FAIL: \(filename):\(idx) - could not parse input")
				continue
			}

			guard let actual = serializeSerializerTokenStream(input, options: options) else {
				failed += 1
				let desc = test["description"] as? String ?? ""
				print("\nSERIALIZER FAIL: \(filename):\(idx) \(desc) - serializer returned nil")
				continue
			}

			let expectedList = test["expected"] as? [String] ?? []

			if expectedList.contains(actual) {
				passed += 1
			}
			else {
				failed += 1
				let desc = test["description"] as? String ?? ""
				print("\nSERIALIZER FAIL: \(filename):\(idx) \(desc)")
				print("OPTIONS: \(options)")
				print("EXPECTED one of: \(expectedList)")
				print("ACTUAL: \(actual)")
			}
		}

		print("  \(filename): \(passed)/\(passed + failed) passed")
		totalPassed += passed
		totalFailed += failed
	}

	let passRate = Double(totalPassed) / Double(max(1, totalPassed + totalFailed)) * 100
	print(
		"\nSERIALIZER TESTS: \(totalPassed)/\(totalPassed + totalFailed) passed, \(totalFailed) failed"
	)
	print("Pass rate: \(String(format: "%.1f", passRate))%")
	#expect(totalPassed + totalFailed > 0, "No serializer tests were run")
	#expect(totalFailed == 0, "Expected 0 serializer test failures but got \(totalFailed)")
}

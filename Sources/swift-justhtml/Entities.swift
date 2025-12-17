// Entities.swift - HTML character entity decoding

import Foundation

/// Legacy entities that can be used without a semicolon
public let LEGACY_ENTITIES: Set<String> = [
	"gt", "lt", "amp", "quot", "nbsp",
	"AMP", "QUOT", "GT", "LT", "COPY", "REG",
	"AElig", "Aacute", "Acirc", "Agrave", "Aring", "Atilde", "Auml",
	"Ccedil", "ETH", "Eacute", "Ecirc", "Egrave", "Euml",
	"Iacute", "Icirc", "Igrave", "Iuml", "Ntilde",
	"Oacute", "Ocirc", "Ograve", "Oslash", "Otilde", "Ouml",
	"THORN", "Uacute", "Ucirc", "Ugrave", "Uuml", "Yacute",
	"aacute", "acirc", "acute", "aelig", "agrave", "aring", "atilde", "auml",
	"brvbar", "ccedil", "cedil", "cent", "copy", "curren",
	"deg", "divide", "eacute", "ecirc", "egrave", "eth", "euml",
	"frac12", "frac14", "frac34",
	"iacute", "icirc", "iexcl", "igrave", "iquest", "iuml",
	"laquo", "macr", "micro", "middot", "not", "ntilde",
	"oacute", "ocirc", "ograve", "ordf", "ordm", "oslash", "otilde", "ouml",
	"para", "plusmn", "pound", "raquo", "reg", "sect", "shy",
	"sup1", "sup2", "sup3", "szlig", "thorn", "times",
	"uacute", "ucirc", "ugrave", "uml", "uuml", "yacute", "yen", "yuml",
]

/// HTML5 numeric character reference replacements (§13.2.5.73)
private let NUMERIC_REPLACEMENTS: [UInt32: String] = [
	0x00: "\u{FFFD}",
	0x80: "\u{20AC}",
	0x82: "\u{201A}",
	0x83: "\u{0192}",
	0x84: "\u{201E}",
	0x85: "\u{2026}",
	0x86: "\u{2020}",
	0x87: "\u{2021}",
	0x88: "\u{02C6}",
	0x89: "\u{2030}",
	0x8A: "\u{0160}",
	0x8B: "\u{2039}",
	0x8C: "\u{0152}",
	0x8E: "\u{017D}",
	0x91: "\u{2018}",
	0x92: "\u{2019}",
	0x93: "\u{201C}",
	0x94: "\u{201D}",
	0x95: "\u{2022}",
	0x96: "\u{2013}",
	0x97: "\u{2014}",
	0x98: "\u{02DC}",
	0x99: "\u{2122}",
	0x9A: "\u{0161}",
	0x9B: "\u{203A}",
	0x9C: "\u{0153}",
	0x9E: "\u{017E}",
	0x9F: "\u{0178}",
]

/// Decode a numeric character reference
/// - Parameters:
///   - text: The numeric part (without # prefix)
///   - isHex: Whether this is a hexadecimal reference
/// - Returns: The decoded character
public func decodeNumericEntity(_ text: String, isHex: Bool = false) -> String {
	guard let codepoint = UInt32(text, radix: isHex ? 16 : 10) else {
		return "\u{FFFD}"
	}

	// Check replacement table first
	if let replacement = NUMERIC_REPLACEMENTS[codepoint] {
		return replacement
	}

	// Invalid codepoints
	if codepoint > 0x10FFFF {
		return "\u{FFFD}"
	}
	if codepoint >= 0xD800, codepoint <= 0xDFFF {
		return "\u{FFFD}"
	}

	// Valid codepoint
	if let scalar = Unicode.Scalar(codepoint) {
		return String(Character(scalar))
	}
	return "\u{FFFD}"
}

/// Check if a character is an ASCII alpha character
private func isAsciiAlpha(_ ch: Character) -> Bool {
	let c = ch.asciiValue ?? 0
	return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
}

/// Check if a character is an ASCII digit
private func isAsciiDigit(_ ch: Character) -> Bool {
	let c = ch.asciiValue ?? 0
	return c >= 0x30 && c <= 0x39
}

/// Check if a character is an ASCII alphanumeric
private func isAsciiAlnum(_ ch: Character) -> Bool {
	return isAsciiAlpha(ch) || isAsciiDigit(ch)
}

/// Check if a character is a hex digit
private func isHexDigit(_ ch: Character) -> Bool {
	let c = ch.asciiValue ?? 0
	return (c >= 0x30 && c <= 0x39) || // 0-9
		(c >= 0x41 && c <= 0x46) || // A-F
		(c >= 0x61 && c <= 0x66) // a-f
}

/// Decode HTML entities in text
/// - Parameters:
///   - text: The text containing entities
///   - inAttribute: Whether this is inside an attribute value
/// - Returns: Text with entities decoded
public func decodeEntitiesInText(_ text: String, inAttribute: Bool = false) -> String {
	var result: [String] = []
	var i = text.startIndex

	while i < text.endIndex {
		let nextAmp = text[i...].firstIndex(of: "&")

		if nextAmp == nil {
			result.append(String(text[i...]))
			break
		}

		if nextAmp! > i {
			result.append(String(text[i ..< nextAmp!]))
		}

		i = nextAmp!
		var j = text.index(after: i)

		// Numeric entity
		if j < text.endIndex, text[j] == "#" {
			j = text.index(after: j)
			var isHex = false

			if j < text.endIndex, (text[j] == "x" || text[j] == "X") {
				isHex = true
				j = text.index(after: j)
			}

			let digitStart = j
			if isHex {
				while j < text.endIndex, isHexDigit(text[j]) {
					j = text.index(after: j)
				}
			}
			else {
				while j < text.endIndex, isAsciiDigit(text[j]) {
					j = text.index(after: j)
				}
			}

			let hasSemicolon = j < text.endIndex && text[j] == ";"
			let digitText = String(text[digitStart ..< j])

			if !digitText.isEmpty {
				result.append(decodeNumericEntity(digitText, isHex: isHex))
				i = hasSemicolon ? text.index(after: j) : j
				continue
			}

			result.append(String(text[i ..< (hasSemicolon ? text.index(after: j) : j)]))
			i = hasSemicolon ? text.index(after: j) : j
			continue
		}

		// Named entity
		while j < text.endIndex, (isAsciiAlpha(text[j]) || isAsciiDigit(text[j])) {
			j = text.index(after: j)
		}

		let entityName = String(text[text.index(after: i) ..< j])
		let hasSemicolon = j < text.endIndex && text[j] == ";"

		if entityName.isEmpty {
			result.append("&")
			i = text.index(after: i)
			continue
		}

		// With semicolon - exact match
		if hasSemicolon, let decoded = NAMED_ENTITIES[entityName] {
			result.append(decoded)
			i = text.index(after: j)
			continue
		}

		// With semicolon but no exact match - try legacy prefix match (not in attributes)
		if hasSemicolon, !inAttribute {
			var bestMatch: String? = nil
			var bestMatchLen = 0
			for k in stride(from: entityName.count, through: 1, by: -1) {
				let prefix = String(entityName.prefix(k))
				if LEGACY_ENTITIES.contains(prefix), let decoded = NAMED_ENTITIES[prefix] {
					bestMatch = decoded
					bestMatchLen = k
					break
				}
			}
			if let match = bestMatch {
				result.append(match)
				i = text.index(text.index(after: i), offsetBy: bestMatchLen)
				continue
			}
		}

		// Legacy entity without semicolon
		if LEGACY_ENTITIES.contains(entityName), let decoded = NAMED_ENTITIES[entityName] {
			let nextChar = j < text.endIndex ? text[j] : nil

			// In attributes, don't decode if followed by alphanumeric or =
			if inAttribute, let next = nextChar, isAsciiAlnum(next) || next == "=" {
				result.append("&")
				i = text.index(after: i)
				continue
			}

			result.append(decoded)
			i = j
			continue
		}

		// Try prefix match for legacy entities
		var bestMatch: String? = nil
		var bestMatchLen = 0
		for k in stride(from: entityName.count, through: 1, by: -1) {
			let prefix = String(entityName.prefix(k))
			if LEGACY_ENTITIES.contains(prefix), let decoded = NAMED_ENTITIES[prefix] {
				bestMatch = decoded
				bestMatchLen = k
				break
			}
		}

		if let match = bestMatch {
			if inAttribute {
				result.append("&")
				i = text.index(after: i)
				continue
			}
			result.append(match)
			i = text.index(text.index(after: i), offsetBy: bestMatchLen)
			continue
		}

		// No match - keep as is
		if hasSemicolon {
			result.append(String(text[i ... j]))
			i = text.index(after: j)
		}
		else {
			result.append("&")
			i = text.index(after: i)
		}
	}

	return result.joined()
}

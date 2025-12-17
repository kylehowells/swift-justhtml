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

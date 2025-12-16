// Encoding.swift - HTML encoding detection and decoding

import Foundation

/// Result of encoding sniffing
public struct EncodingResult {
    public let encoding: String
    public let bomLength: Int
}

/// ASCII whitespace byte values
private let ASCII_WHITESPACE_BYTES: Set<UInt8> = [0x09, 0x0A, 0x0C, 0x0D, 0x20]

/// Normalize an encoding label to a canonical name
public func normalizeEncodingLabel(_ label: String?) -> String? {
    guard let label = label else { return nil }

    let s = label.trimmingCharacters(in: .whitespaces).lowercased()
    if s.isEmpty { return nil }

    // UTF-7 variants become windows-1252 (security)
    if s == "utf-7" || s == "utf7" || s == "x-utf-7" {
        return "windows-1252"
    }

    // UTF-8
    if s == "utf-8" || s == "utf8" {
        return "utf-8"
    }

    // ISO-8859-1 becomes windows-1252
    if s == "iso-8859-1" || s == "iso8859-1" || s == "latin1" ||
       s == "latin-1" || s == "l1" || s == "cp819" || s == "ibm819" {
        return "windows-1252"
    }

    // Windows-1252
    if s == "windows-1252" || s == "windows1252" || s == "cp1252" || s == "x-cp1252" {
        return "windows-1252"
    }

    // ISO-8859-2
    if s == "iso-8859-2" || s == "iso8859-2" || s == "latin2" || s == "latin-2" {
        return "iso-8859-2"
    }

    // EUC-JP
    if s == "euc-jp" || s == "eucjp" {
        return "euc-jp"
    }

    // UTF-16 variants
    if s == "utf-16" || s == "utf16" { return "utf-16" }
    if s == "utf-16le" || s == "utf16le" { return "utf-16le" }
    if s == "utf-16be" || s == "utf16be" { return "utf-16be" }

    return nil
}

/// Normalize a meta-declared encoding
private func normalizeMetaDeclaredEncoding(_ label: Data) -> String? {
    guard let labelString = String(data: label, encoding: .ascii) else { return nil }
    guard let enc = normalizeEncodingLabel(labelString) else { return nil }

    // UTF-16 variants become UTF-8 when declared in meta
    if enc == "utf-16" || enc == "utf-16le" || enc == "utf-16be" ||
       enc == "utf-32" || enc == "utf-32le" || enc == "utf-32be" {
        return "utf-8"
    }

    return enc
}

/// Sniff BOM at start of data
private func sniffBOM(_ data: Data) -> (encoding: String?, bomLength: Int) {
    if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
        return ("utf-8", 3)
    }
    if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
        return ("utf-16le", 2)
    }
    if data.count >= 2 && data[0] == 0xFE && data[1] == 0xFF {
        return ("utf-16be", 2)
    }
    return (nil, 0)
}

/// Skip ASCII whitespace in data
private func skipAsciiWhitespace(_ data: Data, from i: Int) -> Int {
    var idx = i
    while idx < data.count && ASCII_WHITESPACE_BYTES.contains(data[idx]) {
        idx += 1
    }
    return idx
}

/// Check if bytes match pattern (case-insensitive)
private func bytesEqualLower(_ data: Data, start: Int, end: Int, pattern: [UInt8]) -> Bool {
    let len = end - start
    if len != pattern.count { return false }
    for i in 0..<len {
        var b = data[start + i]
        if b >= 0x41 && b <= 0x5A { b |= 0x20 }
        if b != pattern[i] { return false }
    }
    return true
}

/// Check if byte is ASCII alpha
private func isAsciiAlphaByte(_ b: UInt8) -> Bool {
    var c = b
    if c >= 0x41 && c <= 0x5A { c |= 0x20 }
    return c >= 0x61 && c <= 0x7A
}

/// Find index of byte in data
private func indexOfByte(_ data: Data, byte: UInt8, from start: Int) -> Int? {
    for i in start..<data.count {
        if data[i] == byte { return i }
    }
    return nil
}

/// Find index of subarray in data
private func indexOfSubarray(_ data: Data, pattern: [UInt8], from start: Int) -> Int? {
    if pattern.isEmpty { return start }
    if data.count - start < pattern.count { return nil }

    outer: for i in start...(data.count - pattern.count) {
        for j in 0..<pattern.count {
            if data[i + j] != pattern[j] { continue outer }
        }
        return i
    }
    return nil
}

/// Extract charset from content attribute value
private func extractCharsetFromContent(_ contentBytes: Data) -> Data? {
    if contentBytes.isEmpty { return nil }

    // Normalize: lowercase and collapse whitespace
    var normalized = Data()
    for b in contentBytes {
        if ASCII_WHITESPACE_BYTES.contains(b) {
            normalized.append(0x20)
        } else if b >= 0x41 && b <= 0x5A {
            normalized.append(b | 0x20)
        } else {
            normalized.append(b)
        }
    }

    // Find "charset"
    let charsetNeedle: [UInt8] = [0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74] // charset
    guard let idx = indexOfSubarray(normalized, pattern: charsetNeedle, from: 0) else {
        return nil
    }

    var i = idx + charsetNeedle.count
    let n = normalized.count

    // Skip whitespace
    while i < n && ASCII_WHITESPACE_BYTES.contains(normalized[i]) { i += 1 }

    // Expect '='
    if i >= n || normalized[i] != 0x3D { return nil }
    i += 1

    // Skip whitespace
    while i < n && ASCII_WHITESPACE_BYTES.contains(normalized[i]) { i += 1 }
    if i >= n { return nil }

    // Check for quote
    var quote: UInt8? = nil
    if normalized[i] == 0x22 || normalized[i] == 0x27 {
        quote = normalized[i]
        i += 1
    }

    let start = i
    while i < n {
        let ch = normalized[i]
        if let q = quote {
            if ch == q { break }
        } else if ASCII_WHITESPACE_BYTES.contains(ch) || ch == 0x3B {
            break
        }
        i += 1
    }

    if quote != nil && (i >= n || normalized[i] != quote) {
        return nil
    }

    return normalized.subdata(in: start..<i)
}

/// Prescan for meta charset declaration
private func prescanForMetaCharset(_ data: Data) -> String? {
    let maxNonComment = 1024
    let maxTotalScan = 65536

    let n = data.count
    var i = 0
    var nonComment = 0

    let dashDashGt: [UInt8] = [0x2D, 0x2D, 0x3E] // -->
    let metaBytes: [UInt8] = [0x6D, 0x65, 0x74, 0x61] // meta
    let charsetBytes: [UInt8] = [0x63, 0x68, 0x61, 0x72, 0x73, 0x65, 0x74] // charset
    let httpEquivBytes: [UInt8] = [0x68, 0x74, 0x74, 0x70, 0x2D, 0x65, 0x71, 0x75, 0x69, 0x76] // http-equiv
    let contentBytes: [UInt8] = [0x63, 0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74] // content
    let contentTypeBytes: [UInt8] = [0x63, 0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74, 0x2D, 0x74, 0x79, 0x70, 0x65] // content-type

    while i < n && i < maxTotalScan && nonComment < maxNonComment {
        if data[i] != 0x3C { // '<'
            i += 1
            nonComment += 1
            continue
        }

        // Comment <!-- ... -->
        if i + 3 < n && data[i + 1] == 0x21 && data[i + 2] == 0x2D && data[i + 3] == 0x2D {
            guard let endIdx = indexOfSubarray(data, pattern: dashDashGt, from: i + 4) else {
                return nil
            }
            i = endIdx + 3
            continue
        }

        // Tag open
        var j = i + 1

        // End tag: skip
        if j < n && data[j] == 0x2F { // '/'
            var k = i
            var quote: UInt8? = nil
            while k < n && k < maxTotalScan && nonComment < maxNonComment {
                let ch = data[k]
                if quote == nil {
                    if ch == 0x22 || ch == 0x27 { quote = ch }
                    else if ch == 0x3E { // '>'
                        k += 1
                        nonComment += 1
                        break
                    }
                } else if ch == quote {
                    quote = nil
                }
                k += 1
                nonComment += 1
            }
            i = k
            continue
        }

        if j >= n || !isAsciiAlphaByte(data[j]) {
            i += 1
            nonComment += 1
            continue
        }

        let nameStart = j
        while j < n && isAsciiAlphaByte(data[j]) { j += 1 }

        if !bytesEqualLower(data, start: nameStart, end: j, pattern: metaBytes) {
            // Skip rest of tag
            var k = i
            var quote: UInt8? = nil
            while k < n && k < maxTotalScan && nonComment < maxNonComment {
                let ch = data[k]
                if quote == nil {
                    if ch == 0x22 || ch == 0x27 { quote = ch }
                    else if ch == 0x3E {
                        k += 1
                        nonComment += 1
                        break
                    }
                } else if ch == quote {
                    quote = nil
                }
                k += 1
                nonComment += 1
            }
            i = k
            continue
        }

        // Parse meta attributes
        var charset: Data? = nil
        var httpEquiv: Data? = nil
        var content: Data? = nil

        var k = j
        var sawGt = false
        let startI = i

        while k < n && k < maxTotalScan {
            let ch = data[k]
            if ch == 0x3E { // '>'
                sawGt = true
                k += 1
                break
            }

            if ch == 0x3C { break } // '<'

            if ASCII_WHITESPACE_BYTES.contains(ch) || ch == 0x2F { // '/'
                k += 1
                continue
            }

            // Attribute name
            let attrStart = k
            while k < n {
                let c = data[k]
                if ASCII_WHITESPACE_BYTES.contains(c) || c == 0x3D || c == 0x3E || c == 0x2F || c == 0x3C {
                    break
                }
                k += 1
            }
            let attrEnd = k
            k = skipAsciiWhitespace(data, from: k)

            var value: Data? = nil
            if k < n && data[k] == 0x3D { // '='
                k += 1
                k = skipAsciiWhitespace(data, from: k)
                if k >= n { break }

                let q = data[k]
                if q == 0x22 || q == 0x27 { // quote
                    k += 1
                    let valStart = k
                    guard let endQuote = indexOfByte(data, byte: q, from: k) else {
                        // Unclosed quote
                        i += 1
                        nonComment += 1
                        charset = nil
                        httpEquiv = nil
                        content = nil
                        sawGt = false
                        break
                    }
                    value = data.subdata(in: valStart..<endQuote)
                    k = endQuote + 1
                } else {
                    let valStart = k
                    while k < n {
                        let c = data[k]
                        if ASCII_WHITESPACE_BYTES.contains(c) || c == 0x3E || c == 0x3C {
                            break
                        }
                        k += 1
                    }
                    value = data.subdata(in: valStart..<k)
                }
            }

            if bytesEqualLower(data, start: attrStart, end: attrEnd, pattern: charsetBytes) {
                charset = value
            } else if bytesEqualLower(data, start: attrStart, end: attrEnd, pattern: httpEquivBytes) {
                httpEquiv = value
            } else if bytesEqualLower(data, start: attrStart, end: attrEnd, pattern: contentBytes) {
                content = value
            }
        }

        if sawGt {
            if let cs = charset, !cs.isEmpty {
                if let enc = normalizeMetaDeclaredEncoding(cs) {
                    return enc
                }
            }

            if let he = httpEquiv, let ct = content {
                // Check if http-equiv is "content-type"
                if bytesEqualLower(Data(he), start: 0, end: he.count, pattern: contentTypeBytes) {
                    if let extracted = extractCharsetFromContent(ct) {
                        if let enc = normalizeMetaDeclaredEncoding(extracted) {
                            return enc
                        }
                    }
                }
            }

            i = k
            let consumed = i - startI
            nonComment += consumed
        } else {
            i += 1
            nonComment += 1
        }
    }

    return nil
}

/// Sniff HTML encoding from data
/// - Parameters:
///   - data: Raw bytes to analyze
///   - transportEncoding: Optional encoding from HTTP headers
/// - Returns: Detected encoding and BOM length
public func sniffHTMLEncoding(_ data: Data, transportEncoding: String? = nil) -> EncodingResult {
    // Transport-layer encoding takes precedence
    if let transport = normalizeEncodingLabel(transportEncoding) {
        return EncodingResult(encoding: transport, bomLength: 0)
    }

    // Check for BOM
    let (bomEnc, bomLength) = sniffBOM(data)
    if let enc = bomEnc {
        return EncodingResult(encoding: enc, bomLength: bomLength)
    }

    // Prescan for meta charset
    if let metaEnc = prescanForMetaCharset(data) {
        return EncodingResult(encoding: metaEnc, bomLength: 0)
    }

    // Default to windows-1252
    return EncodingResult(encoding: "windows-1252", bomLength: 0)
}

/// Decode HTML from raw bytes
/// - Parameters:
///   - data: Raw bytes
///   - transportEncoding: Optional encoding from HTTP headers
/// - Returns: Decoded string and detected encoding
public func decodeHTML(_ data: Data, transportEncoding: String? = nil) -> (text: String, encoding: String) {
    let result = sniffHTMLEncoding(data, transportEncoding: transportEncoding)
    var enc = result.encoding

    // Limit supported encodings
    if enc != "utf-8" && enc != "windows-1252" && enc != "iso-8859-2" &&
       enc != "euc-jp" && enc != "utf-16" && enc != "utf-16le" && enc != "utf-16be" {
        enc = "windows-1252"
    }

    var payload = data
    if result.bomLength > 0 {
        payload = data.subdata(in: result.bomLength..<data.count)
    }

    // Handle UTF-16
    if enc == "utf-16" {
        let (innerEnc, innerBom) = sniffBOM(payload)
        if innerEnc == "utf-16le" || innerEnc == "utf-16be" {
            payload = payload.subdata(in: innerBom..<payload.count)
            let swiftEnc: String.Encoding = innerEnc == "utf-16le" ? .utf16LittleEndian : .utf16BigEndian
            let text = String(data: payload, encoding: swiftEnc) ?? ""
            return (text, enc)
        }
        let text = String(data: payload, encoding: .utf16LittleEndian) ?? ""
        return (text, enc)
    }

    // Map encoding names to Swift encodings
    let swiftEncoding: String.Encoding
    switch enc {
    case "utf-8":
        swiftEncoding = .utf8
    case "utf-16le":
        swiftEncoding = .utf16LittleEndian
    case "utf-16be":
        swiftEncoding = .utf16BigEndian
    case "iso-8859-2":
        swiftEncoding = .isoLatin2
    case "euc-jp":
        swiftEncoding = .japaneseEUC
    default:
        swiftEncoding = .windowsCP1252
    }

    let text = String(data: payload, encoding: swiftEncoding) ?? ""
    return (text, enc)
}

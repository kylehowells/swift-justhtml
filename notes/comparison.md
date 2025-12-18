# Swift HTML Library Comparison

This document compares swift-justhtml against other common Swift HTML parsing libraries, focusing on HTML5 compliance, Linux support, performance, and dependencies.

## Summary Table

| Library | HTML5 Compliance | Linux Support | Parser Engine | Dependencies |
|---------|-----------------|---------------|---------------|--------------|
| **swift-justhtml** | 100% (1831/1831 tree tests, 6810/6810 tokenizer tests) | Yes | Pure Swift (Custom WHATWG implementation) | None |
| SwiftSoup | Claims WHATWG compliance, ~0% on html5lib tests* | Yes | Pure Swift (Jsoup port) | LRUCache, swift-atomics |
| Kanna | N/A (libxml2-based) | Yes | libxml2 | libxml2-dev |
| LilHTML | N/A (libxml2-based) | Yes | libxml2 | libxml2-dev |
| Fuzi (cezheng) | N/A (libxml2-based) | No** | libxml2 | libxml2 |
| Fuzi (readium) | N/A (libxml2-based) | No** | libxml2 | libxml2 |
| Ono | N/A (libxml2-based) | No | libxml2 (Objective-C) | libxml2 |
| Demark | N/A (not a parser) | No | Turndown.js via WebKit | WebKit |

\* SwiftSoup claims WHATWG HTML5 compliance but doesn't implement the standard tree construction algorithm. Direct html5lib test comparison shows ~0% pass rate due to different output format assumptions.

\** Fuzi libraries use libxml2 but lack proper Swift Package Manager configuration for Linux (missing system library target).

## Detailed Analysis

### swift-justhtml

**HTML5 Compliance:**
- Tree construction tests: 1831/1831 (100%)
- Tokenizer tests: 6810/6810 (100%)
- Full WHATWG HTML5 specification implementation
- Supports fragment parsing with context element
- Supports scripting flag, iframe srcdoc mode, and XML coercion

**Performance:**
- Small HTML (0.9 KB): 0.53ms average, 1.72 MB/s
- Medium HTML (8.4 KB): 4.02ms average, 2.13 MB/s
- Large HTML (42 KB): 15.3ms average, 2.81 MB/s
- Overall average throughput: ~1.79 MB/s

**Dependencies:** None (pure Swift)

**Linux Support:** Full support

---

### SwiftSoup

**Source:** https://github.com/scinfu/SwiftSoup

**Description:** Swift port of Java's Jsoup library. Provides DOM manipulation, CSS selectors, and HTML cleaning capabilities.

**HTML5 Compliance:**
- Claims WHATWG HTML5 compliance in README
- However, does NOT implement the standard html5lib tree construction algorithm
- Uses a simplified parsing approach that produces different tree structures
- Cannot be directly compared against html5lib tests due to fundamental architecture differences

**Features:**
- DOM traversal and manipulation
- CSS selector queries
- HTML sanitization/cleaning (whitelist-based)
- Attribute manipulation

**Dependencies:**
- LRUCache (for query caching)
- swift-atomics (for thread safety)

**Linux Support:** Full support (pure Swift)

**Notes:** SwiftSoup is designed for practical HTML scraping and manipulation rather than strict spec compliance. It handles "tag soup" HTML well for extraction purposes but may produce different DOM structures than a browser would.

---

### Kanna

**Source:** https://github.com/tid-kijyun/Kanna

**Description:** XML/HTML parser using libxml2 as the parsing backend. Inspired by Ruby's Nokogiri.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (not HTML5)
- libxml2 implements HTML 4.01 parsing rules
- Will produce different results than HTML5 parsers for edge cases
- No html5lib test compatibility

**Features:**
- XPath 1.0 queries
- CSS3 selector queries
- Namespace support

**Dependencies:**
- libxml2-dev (system library)

**Linux Support:** Yes (requires `sudo apt-get install libxml2-dev`)

**Notes:** Fast native parsing but not HTML5 compliant. Good for well-formed HTML/XML.

---

### LilHTML

**Source:** https://github.com/nakajima/LilHTML

**Description:** Small HTML parser that uses libxml2 to parse HTML into a pure Swift tree structure.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (not HTML5)
- Same limitations as Kanna
- No html5lib test compatibility

**Features:**
- Mutable and immutable tree representations
- Basic element/attribute access
- Simple query capabilities

**Dependencies:**
- libxml2-dev (system library)

**Linux Support:** Yes (requires `sudo apt-get install libxml2-dev`)

**Notes:** Simple and lightweight but not HTML5 compliant.

---

### Fuzi (cezheng)

**Source:** https://github.com/cezheng/Fuzi

**Description:** Swift port of Ono with improved Swift API conventions.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (not HTML5)
- No html5lib test compatibility

**Features:**
- XPath queries
- CSS selector queries
- Namespace support
- Node type access (elements, text, comments)

**Dependencies:**
- libxml2 (linked library)

**Linux Support:** No (Package.swift lacks proper system library configuration for Linux)

---

### Fuzi (readium)

**Source:** https://github.com/readium/Fuzi

**Description:** Fork of Fuzi maintained by Readium project.

**HTML5 Compliance:** Same as Fuzi (cezheng)

**Linux Support:** No (same issues as cezheng version)

---

### Ono

**Source:** https://github.com/mattt/Ono

**Description:** Objective-C library for XML/HTML parsing using libxml2.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (not HTML5)
- No html5lib test compatibility

**Features:**
- XPath queries
- CSS selector queries
- Objective-C API

**Dependencies:**
- libxml2

**Linux Support:** No (Objective-C only, no Swift Package Manager support)

---

### Demark

**Source:** https://github.com/steipete/Demark

**Description:** HTML to Markdown converter (NOT an HTML parser).

**HTML5 Compliance:** N/A - not an HTML parser

**Features:**
- HTML to Markdown conversion
- Uses Turndown.js via WKWebView
- Multiple conversion engines

**Dependencies:**
- WebKit framework

**Linux Support:** No (requires WebKit/WKWebView)

**Notes:** This library is for converting HTML to Markdown, not for parsing HTML. Included in the comparison list for completeness.

---

## Performance Comparison Notes

Direct performance comparisons are difficult because:

1. **Different architectures:**
   - swift-justhtml: Pure Swift WHATWG implementation
   - SwiftSoup: Pure Swift Jsoup port
   - Kanna/LilHTML/Fuzi: libxml2 wrappers

2. **Different output formats:**
   - Each library exposes the DOM differently
   - Converting to comparable formats adds overhead

3. **libxml2 libraries** will generally be faster for raw parsing (C code), but:
   - Don't implement HTML5 specification
   - May produce incorrect trees for modern HTML
   - Require system dependencies

## Conclusion

**swift-justhtml** is the only Swift HTML library that:
- Implements the full WHATWG HTML5 specification
- Passes 100% of html5lib tree construction tests
- Passes 100% of html5lib tokenizer tests
- Works on Linux without system dependencies
- Has zero external dependencies

Other libraries trade HTML5 compliance for:
- **SwiftSoup:** Rich DOM manipulation API (Jsoup-compatible)
- **Kanna/Fuzi:** XPath support and native libxml2 performance
- **LilHTML:** Simplicity and small footprint

For applications requiring browser-accurate HTML parsing (web scraping, HTML sanitization, document processing), swift-justhtml provides the most spec-compliant results.

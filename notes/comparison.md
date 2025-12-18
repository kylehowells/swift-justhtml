# Swift HTML Library Comparison

This document compares swift-justhtml against other common Swift HTML parsing libraries, focusing on HTML5 compliance, Linux support, performance, and dependencies.

## Summary Table

| Library | Parse Success Rate | Linux Support | Parser Engine | Speed (simple HTML) | Dependencies |
|---------|-------------------|---------------|---------------|---------------------|--------------|
| **swift-justhtml** | 100% (1831/1831 tree, 6810/6810 tokenizer) | Yes | Pure Swift WHATWG | ~0.5ms | None |
| SwiftSoup | 87.9% (1436/1633)* | Yes | Pure Swift (Jsoup) | ~0.1ms | LRUCache, swift-atomics |
| Kanna | 94.4% (1542/1633) | Yes | libxml2 (C) | ~0.003ms | libxml2-dev |
| LilHTML | 47.4% (775/1634)* | Yes | libxml2 (C) | N/A | libxml2-dev |
| Fuzi (cezheng) | Not tested | No | libxml2 | N/A | libxml2 |
| Fuzi (readium) | Not tested | No | libxml2 | N/A | libxml2 |
| Ono | Not tested | No | libxml2 (Obj-C) | N/A | libxml2 |
| Demark | N/A (not a parser) | No | Turndown.js | N/A | WebKit |

\* SwiftSoup has an infinite loop bug on tests16.dat (197 tests on script tag edge cases). LilHTML crashes on 855 tests (52.3%) due to unhandled NULL returns from libxml2.

## Test Results (html5lib-tests/tree-construction)

### swift-justhtml
```
Tree construction tests: 1831/1831 (100%)
Tokenizer tests: 6810/6810 (100%)
Time: 0.152s for all tests
```

### SwiftSoup
```
Total Passed: 1436
Total Failed: 197 (all of tests16.dat - infinite loop)
Total Skipped (fragment): 192
Parse Success Rate: 87.9% (1436/1633)

Benchmark: ~0.098ms per parse (simple HTML)
```

**Note:** SwiftSoup has an infinite loop bug when parsing script tag edge cases (tests16.dat contains 197 such tests). The pass/fail counts above only measure whether parsing completes without error, not whether the resulting DOM tree matches the expected structure.

### Kanna
```
Total Passed: 1542
Total Failed: 91
Total Skipped (fragment): 192
Total Timeout: 0
Total Crash: 0
Parse Success Rate: 94.4% (1542/1633)

Benchmark:
- Simple HTML: 0.003ms avg
- Complex HTML: 0.012ms avg
```

Notable failures in: tests1.dat (16), tests2.dat (15), tests6.dat (10), doctype01.dat (7), tests19.dat (7), domjs-unsafe.dat (5)

**Note:** Unlike LilHTML (which also uses libxml2), Kanna has proper error handling and completes all test files without crashes or timeouts.

### LilHTML
```
Total Passed: 775
Total Failed: 4
Total Crashed: 855
Total Skipped (fragment): 192
Parse Success Rate: 47.4% (775/1634)

Crashes on 22 out of 61 test files including:
- tests1.dat (112 tests), tests2.dat (63), tests19.dat (103)
- template.dat (111), domjs-unsafe.dat (49), doctype01.dat (37)
```

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
- Parses 1436/1633 test inputs successfully (87.9%)
- 197 tests in tests16.dat cause infinite loop (script tag edge cases)
- Uses Jsoup's parsing algorithm, not standard html5lib tree construction
- Tree output format differs from html5lib expected format

**Performance:**
- Simple HTML: ~0.098ms per parse
- Approximately 5x faster than swift-justhtml

**Known Issues:**
- Infinite loop on certain script tag edge cases (tests16.dat)

**Features:**
- DOM traversal and manipulation
- CSS selector queries
- HTML sanitization/cleaning (whitelist-based)
- Attribute manipulation

**Dependencies:**
- LRUCache (for query caching)
- swift-atomics (for thread safety)

**Linux Support:** Full support (pure Swift)

---

### Kanna

**Source:** https://github.com/tid-kijyun/Kanna

**Description:** XML/HTML parser using libxml2 as the parsing backend. Inspired by Ruby's Nokogiri.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (HTML 4.01 based, not HTML5)
- Parse success rate: 94.4% (1542/1634 non-fragment tests)
- 92 tests failed to parse or produced unexpected structure

**Performance:**
- Simple HTML: 0.003ms avg (very fast - native C)
- Complex HTML: 0.012ms avg
- Approximately 30-150x faster than pure Swift implementations

**Features:**
- XPath 1.0 queries
- CSS3 selector queries
- Namespace support

**Dependencies:**
- libxml2-dev (system library: `sudo apt-get install libxml2-dev`)

**Linux Support:** Yes

**Notes:** Extremely fast due to native libxml2, but not HTML5 compliant. Good for well-formed HTML or when speed is critical and perfect compliance isn't required.

---

### LilHTML

**Source:** https://github.com/nakajima/LilHTML

**Description:** Small HTML parser that uses libxml2 to parse HTML into a pure Swift tree structure.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (not HTML5)
- Parse success rate: 47.4% (775/1634 tests)
- **Crashes on 855 tests (52.3%)** due to unhandled NULL from libxml2

**Stability Issues:**
- `htmlReadMemory` returns NULL for many inputs
- Causes `Fatal error: Unexpectedly found nil` crashes
- No error handling for failed parses
- Crashes on 22 out of 61 test files

**Features:**
- Mutable and immutable tree representations
- Basic element/attribute access
- Simple query capabilities

**Dependencies:**
- libxml2-dev (system library)

**Linux Support:** Yes (but highly unstable)

**Notes:** Not recommended for production use. Crashes on over half of html5lib test inputs.

---

### Fuzi (cezheng)

**Source:** https://github.com/cezheng/Fuzi

**Description:** Swift port of Ono with improved Swift API conventions.

**HTML5 Compliance:**
- Uses libxml2's HTML parser (not HTML5)
- Not tested on html5lib tests

**Linux Support:** No (Package.swift lacks proper system library configuration)

Build error: `error: no such module 'libxml2'`

---

### Fuzi (readium)

**Source:** https://github.com/readium/Fuzi

**Description:** Fork of Fuzi maintained by Readium project.

**HTML5 Compliance:** Same as Fuzi (cezheng)

**Linux Support:** No (same build issues)

---

### Ono

**Source:** https://github.com/mattt/Ono

**Description:** Objective-C library for XML/HTML parsing using libxml2.

**Linux Support:** No (Objective-C only, no Swift Package Manager support)

---

### Demark

**Source:** https://github.com/steipete/Demark

**Description:** HTML to Markdown converter (NOT an HTML parser).

**Linux Support:** No (requires WebKit/WKWebView)

---

## Performance Comparison

| Library | Simple HTML | Complex HTML | Notes |
|---------|-------------|--------------|-------|
| swift-justhtml | ~0.5ms | ~4.0ms | Pure Swift, 100% pass rate |
| SwiftSoup | ~0.1ms | ~0.3ms | Pure Swift, 87.9% pass rate |
| Kanna | ~0.003ms | ~0.012ms | Native libxml2, 94.4% pass rate |
| LilHTML | N/A | N/A | 47.4% pass rate, crashes frequently |

**Note:** Kanna is approximately 30-150x faster than pure Swift implementations due to native C code, but trades HTML5 compliance for speed.

## Conclusion

**swift-justhtml** is the only Swift HTML library that:
- Implements the full WHATWG HTML5 specification
- Passes 100% of html5lib tree construction tests (1831/1831)
- Passes 100% of html5lib tokenizer tests (6810/6810)
- Works on Linux without system dependencies
- Has zero external dependencies
- Handles all edge cases without crashes or infinite loops

**Tradeoffs:**
- **SwiftSoup:** Faster parsing, rich DOM API, but 87.9% pass rate due to infinite loop bug on script tags, plus non-standard tree construction
- **Kanna:** Extremely fast (native C), XPath support, but HTML 4.01 only, 94.4% parse rate, requires libxml2
- **LilHTML:** 47.4% pass rate, crashes on 52.3% of test inputs - not production ready

For applications requiring browser-accurate HTML parsing (web scraping, HTML sanitization, document processing), swift-justhtml provides the most spec-compliant and robust results.

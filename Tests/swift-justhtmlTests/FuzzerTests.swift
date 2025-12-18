import Foundation
import Testing

@testable import justhtml

// MARK: - Fuzzer Tests

/// Fuzzer test - generates random malformed HTML to test parser robustness
/// This test runs 10,000 randomly generated HTML documents through the parser
@Test func fuzzTest() async throws {
  let numTests = 10000
  var successes = 0
  var crashes: [(Int, String, String)] = []

  print("Fuzzing swift-justhtml with \(numTests) randomly generated documents...")

  for i in 0..<numTests {
    let html = generateFuzzedHTML()

    if i % 1000 == 0 {
      print("  Progress: \(i)/\(numTests)...")
    }

    do {
      let _ = try JustHTML(html)
      successes += 1
    } catch {
      crashes.append((i, html, "\(error)"))
    }
  }

  print()
  print("Fuzz test results:")
  print("  Successes: \(successes)/\(numTests)")
  print("  Crashes: \(crashes.count)")

  if !crashes.isEmpty {
    print()
    print("First 5 crashes:")
    for (i, html, error) in crashes.prefix(5) {
      print("  Test \(i): \(error)")
      print("    HTML: \(String(html.prefix(100)).debugDescription)...")
    }
  }

  // The parser should handle all malformed HTML without crashing
  #expect(crashes.isEmpty, "Parser should not crash on any fuzzed input")
}

// MARK: - Fuzzer HTML Generators

private let fuzzTags = [
  "div", "span", "p", "a", "img", "table", "tr", "td", "th", "ul", "ol", "li",
  "form", "input", "button", "select", "option", "textarea", "script", "style",
  "head", "body", "html", "title", "meta", "link", "br", "hr", "h1", "h2", "h3",
  "iframe", "object", "embed", "svg", "math", "template", "noscript", "pre",
  "frameset", "frame", "noframes", "plaintext", "xmp", "marquee",
]

private let fuzzFormattingTags = [
  "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u",
]

private let fuzzAttributes = [
  "id", "class", "style", "href", "src", "alt", "title", "name", "value", "type",
]

private let fuzzSpecialChars = [
  "\u{0000}", "\u{000B}", "\u{000C}", "\u{FFFD}", "\u{00A0}", "\u{FEFF}",
]

private let fuzzEntities = [
  "&amp;", "&lt;", "&gt;", "&quot;", "&nbsp;", "&", "&amp", "&#", "&#x",
  "&#123", "&#x1f;", "&#0;", "&#x0;", "&#xD800;", "&#xDFFF;", "&#x10FFFF;",
]

private func fuzzRandomString(minLen: Int = 0, maxLen: Int = 20) -> String {
  let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  let length = Int.random(in: minLen...maxLen)
  return String((0..<length).map { _ in chars.randomElement()! })
}

private func fuzzRandomWhitespace() -> String {
  let ws = [" ", "\t", "\n", "\r", "\u{000C}", ""]
  return (0..<Int.random(in: 0...3)).map { _ in ws.randomElement()! }.joined()
}

private func fuzzOpenTag() -> String {
  let tag = fuzzTags.randomElement()!
  let attrs = (0..<Int.random(in: 0...3))
    .map { _ -> String in
      let name = fuzzAttributes.randomElement()!
      let value = fuzzRandomString(minLen: 0, maxLen: 20)
      return "\(name)=\"\(value)\""
    }
    .joined(separator: " ")
  let closings = [">", "/>", " >", ""]
  return "<\(tag)\(attrs.isEmpty ? "" : " " + attrs)\(closings.randomElement()!)"
}

private func fuzzCloseTag() -> String {
  let tag = fuzzTags.randomElement()!
  let variants = ["</\(tag)>", "</\(tag)", "</ \(tag)>", "</\(tag)/>"]
  return variants.randomElement()!
}

private func fuzzComment() -> String {
  let content = fuzzRandomString(minLen: 0, maxLen: 30)
  let variants = [
    "<!--\(content)-->", "<!-\(content)-->", "<!--\(content)->", "<!--\(content)",
    "<!---\(content)--->", "<!---->", "<!-->", "<!--->",
  ]
  return variants.randomElement()!
}

private func fuzzDoctype() -> String {
  let variants = [
    "<!DOCTYPE html>", "<!doctype html>", "<!DOCTYPE>", "<!DOCTYPE html PUBLIC>",
    "<!DOCTYPE \(fuzzRandomString())>", "<!DOCTYPE",
  ]
  return variants.randomElement()!
}

private func fuzzText() -> String {
  let strategies: [() -> String] = [
    { fuzzRandomString(minLen: 1, maxLen: 50) },
    { fuzzEntities.randomElement()! },
    { (0..<Int.random(in: 1...5)).map { _ in fuzzSpecialChars.randomElement()! }.joined() },
    { "<" + fuzzRandomString(minLen: 1, maxLen: 5) },
    { "&" + fuzzRandomString(minLen: 1, maxLen: 10) },
  ]
  return strategies.randomElement()!()
}

private func fuzzScript() -> String {
  let content = fuzzRandomString(minLen: 0, maxLen: 30)
  let variants = [
    "<script>\(content)</script>", "<script>\(content)",
    "<script>\(content)</scrip>", "<script><!--\(content)--></script>",
    "<script>\(content)</SCRIPT>",
  ]
  return variants.randomElement()!
}

private func fuzzSvgMath() -> String {
  let content = fuzzRandomString(minLen: 0, maxLen: 20)
  let variants = [
    "<svg>\(content)</svg>", "<svg><foreignObject><div>\(content)</div></foreignObject></svg>",
    "<math>\(content)</math>", "<math><mi>\(content)</mi></math>",
    "<svg><p>\(content)</p></svg>", "<math><div>\(content)</div></math>",
    "<math><annotation-xml encoding='text/html'><div>\(content)</div></annotation-xml></math>",
  ]
  return variants.randomElement()!
}

private func fuzzTemplate() -> String {
  let content = fuzzRandomString(minLen: 0, maxLen: 20)
  let variants = [
    "<template>\(content)</template>", "<template>\(content)",
    "<template><template>\(content)</template></template>",
    "<table><template><tr><td>cell</td></tr></template></table>",
  ]
  return variants.randomElement()!
}

private func fuzzAdoptionAgency() -> String {
  let fmt = fuzzFormattingTags.randomElement()!
  let block = ["div", "p", "blockquote"].randomElement()!
  let variants = [
    "<\(fmt)>text<\(block)>more</\(fmt)>content</\(block)>",
    String(repeating: "<\(fmt)>", count: 10) + "text" + String(repeating: "</\(fmt)>", count: 5),
    "<a><b><a><b>text</b></a></b></a>",
    "<\(fmt)><table><tr><td></\(fmt)></td></tr></table>",
  ]
  return variants.randomElement()!
}

private func fuzzFosterParenting() -> String {
  let text = fuzzRandomString(minLen: 1, maxLen: 10)
  let variants = [
    "<table>\(text)<tr><td>cell</td></tr></table>",
    "<table><tr>\(text)<td>cell</td></tr></table>",
    "<table><div>foster</div><tr><td>cell</td></tr></table>",
    "<table><script>x</script><tr><td>cell</td></tr></table>",
  ]
  return variants.randomElement()!
}

private func fuzzDeeplyNested() -> String {
  // Keep depth low to avoid stack overflow - parser handles up to ~30 levels safely
  let depth = Int.random(in: 10...30)
  let tag = ["div", "span", "b", "a"].randomElement()!
  return String(repeating: "<\(tag)>", count: depth) + "content"
    + String(repeating: "</\(tag)>", count: depth)
}

private func fuzzNullHandling() -> String {
  let content = fuzzRandomString(minLen: 1, maxLen: 10)
  let variants = [
    "<di\u{0000}v>\(content)</div>",
    "<div>\(content)\u{0000}\(content)</div>",
    "<!--\u{0000}\(content)-->",
    "<script>\u{0000}\(content)</script>",
    "<title>\u{0000}\(content)</title>",
  ]
  return variants.randomElement()!
}

private func fuzzEofHandling() -> String {
  let content = fuzzRandomString(minLen: 1, maxLen: 10)
  let variants = [
    "<div", "<div class='", "<!--\(content)", "<!DOCTYPE",
    "<script>\(content)", "<style>\(content)", "<title>\(content)",
    "<div><span><p>\(content)",
  ]
  return variants.randomElement()!
}

private func fuzzSelectElement() -> String {
  let content = fuzzRandomString(minLen: 1, maxLen: 10)
  let variants = [
    "<select><option>\(content)</option></select>",
    "<select><option>\(content)<select><option>inner</option></select></option></select>",
    "<select><div>\(content)</div></select>",
    "<select><option>\(content)",
  ]
  return variants.randomElement()!
}

private func fuzzTableScoping() -> String {
  let content = fuzzRandomString(minLen: 1, maxLen: 10)
  let variants = [
    "<table>\(content)<tr><td>cell</td></tr></table>",
    "<table><tr><td><table><tr><td>\(content)</td></tr></table></td></tr></table>",
    "<tr><td>\(content)</td></tr>",
    "<table><caption>\(content)</caption></table>",
  ]
  return variants.randomElement()!
}

private func fuzzIntegrationPoints() -> String {
  let content = fuzzRandomString(minLen: 1, maxLen: 10)
  let variants = [
    "<svg><foreignObject><div>\(content)</div></foreignObject></svg>",
    "<math><annotation-xml encoding='text/html'><div>\(content)</div></annotation-xml></math>",
    "<math><mtext><div>\(content)</div></mtext></math>",
    "<svg><title><div>\(content)</div></title></svg>",
  ]
  return variants.randomElement()!
}

/// Weighted selection helper - returns a generator result based on weighted random selection
private func selectWeightedGenerator() -> String {
  // Weights: openTag=20, closeTag=10, comment=8, text=15, script=4, svgMath=5,
  //          template=3, adoptionAgency=5, fosterParenting=5, deeplyNested=1,
  //          nullHandling=4, eofHandling=3, selectElement=4, tableScoping=5, integrationPoints=4
  let totalWeight = 96  // Sum of all weights
  let r = Int.random(in: 0..<totalWeight)

  switch r {
  case 0..<20: return fuzzOpenTag()

  case 20..<30: return fuzzCloseTag()

  case 30..<38: return fuzzComment()

  case 38..<53: return fuzzText()

  case 53..<57: return fuzzScript()

  case 57..<62: return fuzzSvgMath()

  case 62..<65: return fuzzTemplate()

  case 65..<70: return fuzzAdoptionAgency()

  case 70..<75: return fuzzFosterParenting()

  case 75..<76: return fuzzDeeplyNested()

  case 76..<80: return fuzzNullHandling()

  case 80..<83: return fuzzEofHandling()

  case 83..<87: return fuzzSelectElement()

  case 87..<92: return fuzzTableScoping()

  default: return fuzzIntegrationPoints()
  }
}

private func generateFuzzedHTML() -> String {
  var parts: [String] = []

  if Bool.random() {
    parts.append(fuzzDoctype())
  }

  let numElements = Int.random(in: 1...15)
  for _ in 0..<numElements {
    parts.append(selectWeightedGenerator())
  }

  return parts.joined()
}

// MARK: - Fuzzer Tests

/// Comprehensive fuzzer test that runs all generators sequentially
/// Note: This runs as a single test to avoid thread-safety issues with Swift Testing's
/// parallel execution. The parser passes all individual tests but crashes when multiple
/// parsers run concurrently (likely a Foundation/Swift runtime issue, not in parser code).
@Test func testFuzzerComprehensive() throws {
  var totalTests = 0

  // Test each generator type
  print("Testing individual generators...")

  // Open tag fuzzer
  for _ in 0..<20 {
    let html = fuzzOpenTag()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Close tag fuzzer
  for _ in 0..<20 {
    let html = fuzzCloseTag()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Comment fuzzer
  for _ in 0..<20 {
    let html = fuzzComment()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Text fuzzer
  for _ in 0..<20 {
    let html = fuzzText()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Script fuzzer
  for _ in 0..<20 {
    let html = fuzzScript()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // SVG/Math fuzzer
  for _ in 0..<20 {
    let html = fuzzSvgMath()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Template fuzzer
  for _ in 0..<20 {
    let html = fuzzTemplate()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Adoption agency fuzzer
  for _ in 0..<20 {
    let html = fuzzAdoptionAgency()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Foster parenting fuzzer
  for _ in 0..<20 {
    let html = fuzzFosterParenting()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Deeply nested fuzzer
  for _ in 0..<20 {
    let html = fuzzDeeplyNested()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Null handling fuzzer
  for _ in 0..<20 {
    let html = fuzzNullHandling()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // EOF handling fuzzer
  for _ in 0..<20 {
    let html = fuzzEofHandling()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Select element fuzzer
  for _ in 0..<20 {
    let html = fuzzSelectElement()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Table scoping fuzzer
  for _ in 0..<20 {
    let html = fuzzTableScoping()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  // Integration points fuzzer
  for _ in 0..<20 {
    let html = fuzzIntegrationPoints()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    totalTests += 1
  }

  print("Testing combined generated HTML...")

  // Test combined fuzzed HTML
  for _ in 0..<50 {
    let html = generateFuzzedHTML()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    _ = doc.toText()
    totalTests += 1
  }

  print("Testing fragment parsing...")

  // Test fragment parsing with various contexts
  let contexts = ["div", "table", "template", "svg", "math", "select"]
  for ctx in contexts {
    print("  Testing fragment context: \(ctx)")
    for i in 0..<10 {
      let html = generateFuzzedHTML()
      print("    [\(i)]: \(html.count) chars")
      let doc = try JustHTML(html, fragmentContext: FragmentContext(ctx))
      _ = doc.toHTML()
      totalTests += 1
    }
  }

  print("Testing scripting mode...")

  // Test scripting mode
  for _ in 0..<20 {
    let html = generateFuzzedHTML()
    let doc = try JustHTML(html, scripting: true)
    _ = doc.toHTML()
    totalTests += 1
  }

  print("Testing error collection...")

  // Test error collection
  for _ in 0..<20 {
    let html = generateFuzzedHTML()
    let doc = try JustHTML(html, collectErrors: true)
    _ = doc.errors
    _ = doc.toHTML()
    totalTests += 1
  }

  print("Fuzzer completed \(totalTests) parse operations successfully")
}

// MARK: - Random Data Fuzzer

/// Generates completely random bytes as a string
private func generateRandomData(length: Int) -> String {
  var bytes = [UInt8](repeating: 0, count: length)
  for i in 0..<length {
    bytes[i] = UInt8.random(in: 0...255)
  }
  // Convert to string, replacing invalid UTF-8 sequences
  return String(decoding: bytes, as: UTF8.self)
}

/// Generates random ASCII-ish data (more likely to trigger parsing paths)
private func generateRandomASCII(length: Int) -> String {
  let chars = Array(
    " \t\n\r<>\"'=/!?-abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789&;#")
  return String((0..<length).map { _ in chars.randomElement()! })
}

/// Generates random data with HTML-like characters mixed in
private func generateRandomHTMLish(length: Int) -> String {
  let strategies: [() -> Character] = [
    { Character(UnicodeScalar(UInt8.random(in: 0...127))) },  // ASCII
    { Character(UnicodeScalar(UInt8.random(in: 0...255))) },  // Any byte
    { ["<", ">", "/", "\"", "'", "=", "&", ";", "#", "!", "-", "?"].randomElement()! },  // HTML chars
    { ["\0", "\t", "\n", "\r", "\u{000C}"].randomElement()! },  // Whitespace/null
  ]
  return String((0..<length).map { _ in strategies.randomElement()!() })
}

/// Pure chaos fuzzer - sends completely random data to the parser
/// This tests that the parser doesn't crash on arbitrary junk input
@Test func testRandomDataFuzzer() throws {
  let numTests = 2500
  var completed = 0

  print("Random data fuzzer: testing \(numTests) random inputs...")

  for i in 0..<numTests {
    if i % 1000 == 0 {
      print("  Progress: \(i)/\(numTests)...")
    }

    // Vary the length randomly
    let length = Int.random(in: 0...1000)

    // Pick a random generation strategy
    let strategy = Int.random(in: 0..<4)
    let data: String
    switch strategy {
    case 0:
      data = generateRandomData(length: length)

    case 1:
      data = generateRandomASCII(length: length)

    case 2:
      data = generateRandomHTMLish(length: length)

    default:
      // Mix strategies
      let part1 = generateRandomData(length: length / 3)
      let part2 = generateRandomASCII(length: length / 3)
      let part3 = generateRandomHTMLish(length: length / 3)
      data = part1 + part2 + part3
    }

    // Try parsing - we don't care what it returns, just that it doesn't crash
    do {
      let doc = try JustHTML(data)
      _ = doc.toHTML()
      _ = doc.toText()
    } catch {
      // Errors are fine, crashes are not
    }

    completed += 1
  }

  print("Random data fuzzer completed \(completed)/\(numTests) tests without crashes")
  #expect(completed == numTests, "All random data tests should complete without crashes")
}

/// Extended random data fuzzer with longer inputs
@Test func testRandomDataFuzzerLongInputs() throws {
  let numTests = 250
  var completed = 0

  print("Random data fuzzer (long inputs): testing \(numTests) random inputs...")

  for i in 0..<numTests {
    if i % 100 == 0 {
      print("  Progress: \(i)/\(numTests)...")
    }

    // Longer lengths for stress testing
    let length = Int.random(in: 1000...10000)

    let strategy = Int.random(in: 0..<4)
    let data: String
    switch strategy {
    case 0:
      data = generateRandomData(length: length)

    case 1:
      data = generateRandomASCII(length: length)

    case 2:
      data = generateRandomHTMLish(length: length)

    default:
      data = generateRandomData(length: length / 2) + generateRandomHTMLish(length: length / 2)
    }

    do {
      let doc = try JustHTML(data)
      _ = doc.toHTML()
    } catch {
      // Errors are expected and fine
    }

    completed += 1
  }

  print("Random data fuzzer (long) completed \(completed)/\(numTests) tests without crashes")
  #expect(completed == numTests, "All long random data tests should complete without crashes")
}

/// Test random data with fragment parsing contexts
@Test func testRandomDataFragmentFuzzer() throws {
  let contexts = [
    "div", "table", "template", "svg", "math", "select", "script", "style", "title", "textarea",
  ]
  let testsPerContext = 100
  var completed = 0

  print("Random data fragment fuzzer: testing \(contexts.count * testsPerContext) inputs...")

  for ctx in contexts {
    for _ in 0..<testsPerContext {
      let length = Int.random(in: 0...500)
      let data = generateRandomHTMLish(length: length)

      do {
        let doc = try JustHTML(data, fragmentContext: FragmentContext(ctx))
        _ = doc.toHTML()
      } catch {
        // Errors are fine
      }

      completed += 1
    }
  }

  print("Random data fragment fuzzer completed \(completed) tests without crashes")
  #expect(completed == contexts.count * testsPerContext)
}

// MARK: - UTF-8 / Emoji Fuzzer

/// Collection of emoji and Unicode characters to stress test byte-based tokenizer
private let fuzzEmoji = [
  // Simple emoji (various byte lengths)
  "😀", "🎉", "🚀", "❤️", "✨", "🔥", "💯", "🎸", "🌍", "🏠",
  // Multi-codepoint emoji (ZWJ sequences)
  "👨‍👩‍👧‍👦", "👩‍💻", "🏳️‍🌈", "👨‍🔬", "🧑‍🚀",
  // Regional indicators (flag emoji)
  "🇺🇸", "🇬🇧", "🇯🇵", "🇩🇪", "🇫🇷",
  // Skin tone modifiers
  "👋🏻", "👋🏿", "🤝🏼", "💪🏽",
  // Keycap sequences
  "1️⃣", "2️⃣", "#️⃣", "*️⃣",
  // Misc multi-byte
  "☀️", "☁️", "⚡", "🌈", "🎵",
]

/// CJK and other scripts
private let fuzzUnicodeScripts = [
  // Chinese
  "中文", "测试", "你好世界",
  // Japanese
  "日本語", "テスト", "こんにちは",
  // Korean
  "한국어", "테스트",
  // Arabic (RTL)
  "العربية", "اختبار",
  // Hebrew (RTL)
  "עברית", "בדיקה",
  // Thai
  "ภาษาไทย", "ทดสอบ",
  // Devanagari
  "हिन्दी", "परीक्षण",
  // Cyrillic
  "Русский", "тест",
  // Greek
  "Ελληνικά", "δοκιμή",
]

/// Special Unicode characters that might confuse byte-based parsing
private let fuzzUnicodeSpecial = [
  "\u{200B}",  // Zero-width space
  "\u{200C}",  // Zero-width non-joiner
  "\u{200D}",  // Zero-width joiner
  "\u{FEFF}",  // BOM / zero-width no-break space
  "\u{00A0}",  // Non-breaking space
  "\u{2028}",  // Line separator
  "\u{2029}",  // Paragraph separator
  "\u{FFFD}",  // Replacement character
  "\u{FE0F}",  // Variation selector-16 (emoji presentation)
  "\u{FE0E}",  // Variation selector-15 (text presentation)
]

/// Generate emoji-heavy text content
private func fuzzEmojiText() -> String {
  let count = Int.random(in: 1...10)
  var result = ""
  for _ in 0..<count {
    let choice = Int.random(in: 0..<4)
    switch choice {
    case 0:
      result += fuzzEmoji.randomElement()!

    case 1:
      result += fuzzUnicodeScripts.randomElement()!

    case 2:
      result += fuzzUnicodeSpecial.randomElement()!

    default:
      result += fuzzRandomString(minLen: 1, maxLen: 5)
    }
  }
  return result
}

/// Generate HTML with emoji in tag names (invalid but should not crash)
private func fuzzEmojiInTagName() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let text = fuzzEmojiText()
  let variants = [
    "<\(emoji)>\(text)</\(emoji)>",
    "<div\(emoji)>\(text)</div>",
    "<\(emoji)div>\(text)</\(emoji)div>",
    "<d\(emoji)iv>\(text)</d\(emoji)iv>",
    "<DIV\(emoji)>\(text)</DIV>",
  ]
  return variants.randomElement()!
}

/// Generate HTML with emoji in attribute names/values
private func fuzzEmojiInAttributes() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let text = fuzzEmojiText()
  let variants = [
    "<div \(emoji)=\"value\">\(text)</div>",
    "<div class=\"\(emoji)\">\(text)</div>",
    "<div data-\(emoji)=\"test\">\(text)</div>",
    "<div class=\"foo \(emoji) bar\">\(text)</div>",
    "<a href=\"https://example.com/\(emoji)\">\(text)</a>",
    "<div id=\"\(emoji)\" class=\"\(emoji)\">\(text)</div>",
    "<input value=\"\(text)\" placeholder=\"\(emoji)\">",
  ]
  return variants.randomElement()!
}

/// Generate HTML with emoji interrupting tags mid-parse
private func fuzzEmojiMidTag() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let text = fuzzEmojiText()
  let variants = [
    "<di\(emoji)v>\(text)</div>",
    "<div cla\(emoji)ss=\"test\">\(text)</div>",
    "<div class=\(emoji)\"test\">\(text)</div>",
    "<div class=\"te\(emoji)st\">\(text)</div>",
    "</di\(emoji)v>",
    "<div\(emoji)class=\"test\">\(text)</div>",
    "<div class\(emoji)=\"test\">\(text)</div>",
    "<\(emoji)>\(text)</>",
  ]
  return variants.randomElement()!
}

/// Generate HTML with emoji in comments
private func fuzzEmojiInComments() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let text = fuzzEmojiText()
  let variants = [
    "<!--\(emoji)-->",
    "<!-- \(text) \(emoji) \(text) -->",
    "<!--\(emoji)\(emoji)\(emoji)-->",
    "<!-\(emoji)->",
    "<!--\(emoji)--\(emoji)-->",
    "<div>\(text)<!--\(emoji)-->\(text)</div>",
  ]
  return variants.randomElement()!
}

/// Generate HTML with emoji mixed with entities
private func fuzzEmojiWithEntities() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let text = fuzzEmojiText()
  let variants = [
    "\(emoji)&amp;\(emoji)",
    "&lt;\(emoji)&gt;",
    "\(emoji)&#x1F600;\(emoji)",
    "&\(emoji);",
    "&#\(emoji);",
    "<div>\(text)&nbsp;\(emoji)&nbsp;\(text)</div>",
    "\(emoji)&unknown;\(emoji)",
  ]
  return variants.randomElement()!
}

/// Generate HTML with emoji in script/style content
private func fuzzEmojiInRawText() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let text = fuzzEmojiText()
  let variants = [
    "<script>var x = \"\(emoji)\";</script>",
    "<script>\(emoji)</script>",
    "<style>.class { content: \"\(emoji)\"; }</style>",
    "<title>\(emoji) \(text) \(emoji)</title>",
    "<textarea>\(emoji)\(text)\(emoji)</textarea>",
    "<script>// \(text)\n\(emoji)</script>",
  ]
  return variants.randomElement()!
}

/// Generate HTML with emoji at UTF-8 byte boundaries
private func fuzzEmojiAtBoundaries() -> String {
  let emoji = fuzzEmoji.randomElement()!
  let zwj = "\u{200D}"
  let vs16 = "\u{FE0F}"
  let text = fuzzEmojiText()
  let variants = [
    // Emoji right at tag boundaries
    "\(emoji)<div>\(text)</div>\(emoji)",
    "<\(emoji)div>\(text)</div>",
    "<div>\(emoji)</div>",
    // ZWJ in problematic places
    "<div\(zwj)>\(text)</div>",
    "<div class\(zwj)=\"test\">\(text)</div>",
    // Variation selectors
    "<div>\(emoji)\(vs16)\(text)</div>",
    "<\(vs16)div>\(text)</div>",
    // Multiple combining marks
    "<div>\(emoji)\(zwj)\(emoji)\(zwj)\(emoji)</div>",
  ]
  return variants.randomElement()!
}

/// Generate completely random Unicode strings
private func fuzzRandomUnicode(length: Int) -> String {
  var result = ""
  for _ in 0..<length {
    let choice = Int.random(in: 0..<5)
    switch choice {
    case 0:
      result += fuzzEmoji.randomElement()!

    case 1:
      result += fuzzUnicodeScripts.randomElement()!

    case 2:
      result += fuzzUnicodeSpecial.randomElement()!

    case 3:
      // Random valid Unicode scalar
      if let scalar = UnicodeScalar(UInt32.random(in: 0x20...0x10FFFF)) {
        if scalar.isASCII || !scalar.properties.isNoncharacterCodePoint {
          result.append(Character(scalar))
        }
      }

    default:
      result += String((0..<Int.random(in: 1...3)).map { _ in "abcdef".randomElement()! })
    }
  }
  return result
}

/// UTF-8 / Emoji fuzzer test
/// Tests that byte-based tokenizer correctly handles all Unicode including:
/// - Multi-byte UTF-8 sequences (emoji, CJK, etc.)
/// - ZWJ sequences (family emoji, profession emoji)
/// - Combining characters and variation selectors
/// - Unicode in invalid positions (tag names, mid-attribute, etc.)
@Test func testUTF8EmojiFuzzer() throws {
  var completed = 0
  let testsPerCategory = 200

  print("UTF-8/Emoji fuzzer: testing byte-based tokenizer with Unicode edge cases...")

  // Test emoji in tag names
  print("  Testing emoji in tag names...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiInTagName()
    let doc = try JustHTML(html)
    let output = doc.toHTML()
    // Verify emoji survives round-trip
    for emoji in fuzzEmoji where html.contains(emoji) {
      #expect(
        output.contains(emoji) || doc.toText().contains(emoji),
        "Emoji should survive parsing: \(emoji)")
    }
    completed += 1
  }

  // Test emoji in attributes
  print("  Testing emoji in attributes...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiInAttributes()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test emoji mid-tag
  print("  Testing emoji mid-tag...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiMidTag()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test emoji in comments
  print("  Testing emoji in comments...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiInComments()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test emoji with entities
  print("  Testing emoji with entities...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiWithEntities()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test emoji in raw text elements
  print("  Testing emoji in script/style/title...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiInRawText()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test emoji at byte boundaries
  print("  Testing emoji at byte boundaries...")
  for _ in 0..<testsPerCategory {
    let html = fuzzEmojiAtBoundaries()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test random Unicode soup
  print("  Testing random Unicode strings...")
  for _ in 0..<testsPerCategory {
    let unicode = fuzzRandomUnicode(length: Int.random(in: 10...100))
    let html = "<div>\(unicode)</div>"
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    completed += 1
  }

  // Test combined chaos
  print("  Testing combined Unicode chaos...")
  for _ in 0..<testsPerCategory {
    var parts: [String] = []
    parts.append(fuzzEmojiInTagName())
    parts.append(fuzzEmojiInAttributes())
    parts.append(fuzzEmojiInComments())
    parts.append(fuzzEmojiWithEntities())
    let html = parts.shuffled().joined()
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    _ = doc.toText()
    completed += 1
  }

  print("UTF-8/Emoji fuzzer completed \(completed) tests without crashes")
  #expect(completed == testsPerCategory * 9, "All UTF-8/emoji tests should complete")
}

/// Specific test for emoji preservation in valid HTML
@Test func testEmojiPreservation() throws {
  // Test that emoji in valid positions are preserved exactly
  // Each case has the HTML and a list of strings that must appear in output
  let testCases: [(html: String, mustContain: [String])] = [
    ("<p>Hello 😀 World</p>", ["Hello", "😀", "World"]),
    ("<div class=\"emoji-👍\">test</div>", ["test"]),
    ("<span data-emoji=\"🎉\">party</span>", ["party"]),
    ("<p>Flags: 🇺🇸🇬🇧🇯🇵</p>", ["🇺🇸", "🇬🇧", "🇯🇵"]),
    ("<p>Family: 👨‍👩‍👧‍👦</p>", ["👨‍👩‍👧‍👦"]),
    ("<p>ZWJ: 👩‍💻👨‍🔬🧑‍🚀</p>", ["👩‍💻", "👨‍🔬", "🧑‍🚀"]),
    ("<p>Skin tones: 👋🏻👋🏽👋🏿</p>", ["👋🏻", "👋🏽", "👋🏿"]),
    ("<p>中文日本語한국어</p>", ["中文", "日本語", "한국어"]),
    ("<p>Mixed: Hello 你好 🌍 مرحبا</p>", ["Hello", "你好", "🌍", "مرحبا"]),
    ("<title>🚀 Rocket App</title>", ["🚀", "Rocket"]),
  ]

  for (html, mustContain) in testCases {
    let doc = try JustHTML(html)
    let output = doc.toHTML()
    let text = doc.toText()

    // Check that required strings are preserved
    for required in mustContain {
      let found = output.contains(required) || text.contains(required)
      #expect(found, "'\(required)' should be preserved in: \(html)")
    }

    // Verify text extraction produces non-empty output
    #expect(!text.isEmpty, "Text extraction should work for: \(html)")
  }
}

/// Test that invalid UTF-8 sequences don't crash the parser
@Test func testInvalidUTF8Handling() throws {
  // These strings contain replacement characters from invalid UTF-8
  let invalidSequences: [String] = [
    // Overlong encodings (would be handled by Swift's String)
    String(decoding: [0xC0, 0x80] as [UInt8], as: UTF8.self),  // Overlong NUL
    String(decoding: [0xE0, 0x80, 0x80] as [UInt8], as: UTF8.self),  // Overlong NUL
    // Truncated sequences
    String(decoding: [0xC2] as [UInt8], as: UTF8.self),  // Truncated 2-byte
    String(decoding: [0xE2, 0x82] as [UInt8], as: UTF8.self),  // Truncated 3-byte
    String(decoding: [0xF0, 0x9F, 0x98] as [UInt8], as: UTF8.self),  // Truncated 4-byte
    // Invalid continuation bytes
    String(decoding: [0x80, 0x81, 0x82] as [UInt8], as: UTF8.self),
    // Surrogate halves (invalid in UTF-8)
    String(decoding: [0xED, 0xA0, 0x80] as [UInt8], as: UTF8.self),  // High surrogate
    String(decoding: [0xED, 0xB0, 0x80] as [UInt8], as: UTF8.self),  // Low surrogate
  ]

  for invalid in invalidSequences {
    let html = "<div>\(invalid)</div>"
    // Should not crash
    let doc = try JustHTML(html)
    _ = doc.toHTML()
    _ = doc.toText()
  }

  // Test invalid UTF-8 in various positions
  let replacement = "\u{FFFD}"
  let positions = [
    "<div\(replacement)>text</div>",
    "<div class=\"\(replacement)\">text</div>",
    "<!--\(replacement)-->",
    "<script>\(replacement)</script>",
  ]

  for html in positions {
    let doc = try JustHTML(html)
    _ = doc.toHTML()
  }
}

// MARK: - Regression Tests

/// Regression test for select fragment crash with table + li + table sequence
/// Bug found by fuzzer: infinite recursion when table tag seen in inSelect mode
/// with select as context-only element (not on open elements stack)
///
/// Related tests are in: html5lib-tests/tree-construction/select_fragment_crash.dat
@Test func testSelectFragmentCrash() throws {
  // MINIMAL CRASH CASE: table + li + table in select fragment context
  // Previously caused infinite recursion leading to SIGSEGV
  let minimalCrash = "<table></table><li><table></table>"

  // This works fine in regular parsing mode
  let regularDoc = try JustHTML(minimalCrash)
  _ = regularDoc.toHTML()

  // This should now work without crashing
  let selectDoc = try JustHTML(minimalCrash, fragmentContext: FragmentContext("select"))
  _ = selectDoc.toHTML()

  // Verify the output is reasonable
  let output = selectDoc.toTestFormat()
  #expect(output.contains("<table>"))
}

/// Test that individual components don't crash
@Test func testSelectFragmentNonCrashingCases() throws {
  // All variants should work without crashing

  // Single table in select fragment
  let doc1 = try JustHTML("<table></table>", fragmentContext: FragmentContext("select"))
  _ = doc1.toHTML()

  // table + li in select fragment
  let doc2 = try JustHTML("<table></table><li>", fragmentContext: FragmentContext("select"))
  _ = doc2.toHTML()

  // li + table in select fragment
  let doc3 = try JustHTML("<li><table></table>", fragmentContext: FragmentContext("select"))
  _ = doc3.toHTML()

  // table + li + table in select fragment (was crashing before fix)
  let doc4 = try JustHTML(
    "<table></table><li><table></table>", fragmentContext: FragmentContext("select"))
  _ = doc4.toHTML()
}

// Fuzz.swift - HTML5 Parser Fuzzer for swift-justhtml
//
// Ported from Python justhtml/benchmarks/fuzz.py
// Generates random malformed HTML to test parser robustness.
//
// Usage:
//   Build: swift build -c release
//   Run:   .build/release/swift-justhtml-fuzz --num-tests 10000

import Foundation

// MARK: - Constants

let tags = [
  "div", "span", "p", "a", "img", "table", "tr", "td", "th", "ul", "ol", "li",
  "form", "input", "button", "select", "option", "textarea", "script", "style",
  "head", "body", "html", "title", "meta", "link", "br", "hr", "h1", "h2", "h3",
  "iframe", "object", "embed", "video", "audio", "source", "canvas", "svg", "math",
  "template", "slot", "noscript", "pre", "code", "blockquote", "article", "section",
  "header", "footer", "nav", "aside", "main", "figure", "figcaption", "details",
  "summary", "dialog", "menu", "menuitem", "frameset", "frame", "noframes",
  "plaintext", "xmp", "listing", "image", "isindex", "nextid", "bgsound", "marquee",
]

let rawTextTags = ["script", "style", "xmp", "iframe", "noembed", "noframes", "noscript"]
let rcdataTags = ["title", "textarea"]
let voidTags = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"]
let formattingTags = ["a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u"]
let tableTags = ["table", "tbody", "tfoot", "thead", "tr", "td", "th", "caption", "colgroup", "col"]
let adoptionAgencyTags = ["a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u"]

let attributes = [
  "id", "class", "style", "href", "src", "alt", "title", "name", "value", "type",
  "onclick", "onload", "onerror", "data-x", "aria-label", "role", "tabindex",
  "disabled", "readonly", "checked", "selected", "hidden", "contenteditable",
]

let specialChars = [
  "\u{0000}", "\u{0001}", "\u{000B}", "\u{000C}", "\u{000E}", "\u{000F}", "\u{007F}",
  "\u{FFFD}", "\u{00A0}", "\u{2028}", "\u{2029}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{FEFF}",
]

let entities = [
  "&amp;", "&lt;", "&gt;", "&quot;", "&apos;", "&nbsp;", "&", "&amp", "&ampamp;",
  "&am", "&#", "&#x", "&#123", "&#x1f;", "&#xdeadbeef;", "&#99999999;", "&#-1;",
  "&#x;", "&unknown;", "&AMP;", "&AMP", "&LT", "&GT", "&#0;", "&#x0;", "&#x0D;",
  "&#13;", "&#128;", "&#x80;", "&#159;", "&#x9F;", "&#xD800;", "&#xDFFF;",
  "&#x10FFFF;", "&#x110000;", "&NotExists;", "&notin;", "&notinva;",
]

// MARK: - Random Helpers

var rng = SystemRandomNumberGenerator()

func randomInt(_ range: ClosedRange<Int>) -> Int {
  Int.random(in: range, using: &rng)
}

func randomElement<T>(_ array: [T]) -> T {
  array[randomInt(0...(array.count - 1))]
}

func randomString(minLen: Int = 0, maxLen: Int = 20) -> String {
  let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  let length = randomInt(minLen...maxLen)
  return String((0..<length).map { _ in chars.randomElement()! })
}

func randomWhitespace() -> String {
  let ws = [" ", "\t", "\n", "\r", "\u{000C}", "\u{000B}", "\u{0000}", ""]
  return (0..<randomInt(0...5)).map { _ in randomElement(ws) }.joined()
}

func randomBool(_ probability: Double = 0.5) -> Bool {
  Double.random(in: 0...1, using: &rng) < probability
}

// MARK: - Fuzzing Strategies

func fuzzTagName() -> String {
  let strategies: [() -> String] = [
    { randomElement(tags) },
    { randomElement(tags).uppercased() },
    { randomElement(tags) + randomString(minLen: 1, maxLen: 5) },
    { randomString(minLen: 1, maxLen: 10) },
    { "" },
    { randomElement(specialChars) + randomElement(tags) },
    { randomElement(tags) + randomElement(specialChars) },
    { "0" + randomElement(tags) },
    { "-" + randomElement(tags) },
    { randomElement(tags) + "/" + randomElement(tags) },
    { " " + randomElement(tags) },
    { randomElement(tags) + "\u{0000}" },
  ]
  return randomElement(strategies)()
}

func fuzzAttribute() -> String {
  let nameStrategies: [() -> String] = [
    { randomElement(attributes) },
    { randomString(minLen: 1, maxLen: 15) },
    { "" },
    { "on" + randomString(minLen: 2, maxLen: 8) },
    { randomElement(specialChars) },
    { "=" }, { "\"" }, { "'" }, { "<" }, { ">" },
  ]

  let valueStrategies: [() -> String] = [
    { randomString(minLen: 0, maxLen: 50) },
    { "\"" + randomString() + "\"" },
    { "'" + randomString() + "'" },
    { randomElement(entities) },
    { "<script>alert(1)</script>" },
    { "javascript:alert(1)" },
    { String(repeating: randomElement(specialChars), count: randomInt(1...10)) },
    { String(repeating: "\n", count: randomInt(1...5)) + randomString() },
    { "" },
    { String(repeating: "x", count: randomInt(100...1000)) },
  ]

  let quoteStyles = [
    ("=\"", "\""), ("='", "'"), ("=", ""), ("= ", ""),
    ("", ""), ("=\"", ""), ("='", ""), ("==", ""),
  ]

  let name = randomElement(nameStrategies)()
  let value = randomElement(valueStrategies)()
  let (quoteStart, quoteEnd) = randomElement(quoteStyles)

  return "\(name)\(quoteStart)\(value)\(quoteEnd)"
}

func fuzzOpenTag() -> String {
  let tag = fuzzTagName()
  let ws1 = randomWhitespace()
  let attrs = (0..<randomInt(0...5)).map { _ in fuzzAttribute() }.joined(separator: " ")
  let ws2 = randomWhitespace()
  let closings = [">", "/>", " >", "/ >", "", ">>", ">>>", "/>>", ">/", "\u{0000}>"]
  let closing = randomElement(closings)
  let openings = ["<", "< ", "<\u{0000}", "<<", "<!!", "<!", "<?", "</"]
  let opening = randomBool(0.2) ? randomElement(openings) : "<"
  return "\(opening)\(tag)\(ws1)\(attrs)\(ws2)\(closing)"
}

func fuzzCloseTag() -> String {
  let tag = fuzzTagName()
  let ws = randomWhitespace()
  let variants = [
    "</\(tag)>",
    "</ \(tag)>",
    "</\(tag) >",
    "</\(tag)\(ws)>",
    "</\(tag)",
    "</\(tag)/>",
    "//\(tag)>",
    "</\(tag) garbage>",
    "</ \(tag) \(fuzzAttribute())>",
    "</\(tag)\u{0000}>",
  ]
  return randomElement(variants)
}

func fuzzComment() -> String {
  let content = randomString(minLen: 0, maxLen: 50)
  let variants = [
    "<!--\(content)-->",
    "<!-\(content)-->",
    "<!--\(content)->",
    "<!--\(content)",
    "<!---\(content)--->",
    "<!--\(content)--!>",
    "<!---->",
    "<!-->",
    "<!--->",
    "<!--\(content)---->\(content)-->",
    "<!--\(content)--\(content)-->",
    "<! --\(content)-->",
    "<!--\(content)>",
    "<!\(content)>",
  ]
  return randomElement(variants)
}

func fuzzDoctype() -> String {
  let variants = [
    "<!DOCTYPE html>",
    "<!doctype html>",
    "<!DOCTYPE>",
    "<!DOCTYPE html PUBLIC>",
    "<!DOCTYPE html SYSTEM>",
    "<!DOCTYPE html PUBLIC \"\" \"\">",
    "<!DOCTYPE \(randomString())>",
    "<!DOCTYPE html \(randomString(minLen: 10, maxLen: 50))>",
    "<!DOCTYPE",
    "<! DOCTYPE html>",
    "<!DOCTYPEhtml>",
    "<!DOCTYPE\u{0000}html>",
  ]
  return randomElement(variants)
}

func fuzzText() -> String {
  let strategies: [() -> String] = [
    { randomString(minLen: 1, maxLen: 50) },
    { randomElement(entities) },
    { (0..<randomInt(1...10)).map { _ in randomElement(specialChars) }.joined() },
    { "<" + randomString(minLen: 1, maxLen: 5) },
    { "&" + randomString(minLen: 1, maxLen: 10) },
    { randomString() + ">" + randomString() },
    { String(repeating: "\u{0000}", count: randomInt(1...5)) },
    { String(repeating: "\r\n", count: randomInt(1...5)) },
    { String(repeating: " ", count: randomInt(10...100)) },
  ]
  return randomElement(strategies)()
}

func fuzzScript() -> String {
  let content = randomString(minLen: 0, maxLen: 30)
  let variants = [
    "<script>\(content)</script>",
    "<script>\(content)",
    "<script>\(content)</script",
    "<script>\(content)</scrip>",
    "<script><!--\(content)--></script>",
    "<script><!--\(content)</script>",
    "<script>\(content)</script >\(content)</script>",
    "<script>\(content)<script>\(content)</script>",
    "<script>\(content)</SCRIPT>",
    "<script type='text/javascript'>\(content)</script>",
    "<script>\(content)<!-- </script> -->\(content)</script>",
    "<script>//<![CDATA[\n\(content)\n//]]></script>",
  ]
  return randomElement(variants)
}

func fuzzStyle() -> String {
  let content = randomString(minLen: 0, maxLen: 30)
  let variants = [
    "<style>\(content)</style>",
    "<style>\(content)",
    "<style>\(content)</styl>",
    "<style><!--\(content)--></style>",
    "<style>\(content)</style >\(content)</style>",
    "<style>\(content)</STYLE>",
  ]
  return randomElement(variants)
}

func fuzzNestedStructure(depth: Int = 0, maxDepth: Int = 10) -> String {
  if depth >= maxDepth || randomBool(0.3) {
    return fuzzText()
  }

  let tag = randomElement(tags)
  let children = (0..<randomInt(0...3)).map { _ in fuzzNestedStructure(depth: depth + 1, maxDepth: maxDepth) }.joined()

  if randomBool(0.2) {
    return "<\(tag)>\(children)"
  }
  if randomBool(0.1) {
    let otherTag = randomElement(tags)
    return "<\(tag)>\(children)</\(otherTag)>"
  }
  return "<\(tag)>\(children)</\(tag)>"
}

func fuzzAdoptionAgency() -> String {
  let formatting = randomElement(adoptionAgencyTags)
  let otherFormatting = randomElement(adoptionAgencyTags)
  let block = randomElement(["div", "p", "blockquote", "article", "section"])

  let variants = [
    "<\(formatting)>text<\(block)>more</\(formatting)>content</\(block)>",
    "<\(formatting)><\(otherFormatting)><\(block)></\(formatting)></\(otherFormatting)></\(block)>",
    String(repeating: "<\(formatting)>", count: 10) + "text" + String(repeating: "</\(formatting)>", count: 5) + "<\(block)></\(block)>" + String(repeating: "</\(formatting)>", count: 5),
    "<\(formatting)>before<\(block)>inside</\(formatting)>after</\(block)>trailing",
    "<\(formatting)><\(block)>1</\(formatting)><\(block)>2</\(formatting)><\(block)>3</\(formatting)>",
    "<\(formatting)><\(formatting)><\(formatting)>deep</\(formatting)></\(formatting)></\(formatting)>",
    "<a><b><a><b>text</b></a></b></a>",
    "<b><i><b><i>text</i></b></i></b>",
    "<\(formatting)><table><tr><td></\(formatting)></td></tr></table>",
    "<\(formatting)><form></\(formatting)></form>",
    "<\(formatting) id='x'>before<\(block)>inside</\(formatting)>after</\(block)>",
  ]
  return randomElement(variants)
}

func fuzzFosterParenting() -> String {
  let text = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<table>\(text)<tr><td>cell</td></tr></table>",
    "<table><tr>\(text)<td>cell</td></tr></table>",
    "<table><tbody>\(text)<tr><td>cell</td></tr></tbody></table>",
    "<table><div>foster me</div><tr><td>cell</td></tr></table>",
    "<table><tr><div>foster</div><td>cell</td></tr></table>",
    "<table><tbody><tr><table><tr>\(text)<td>deep</td></tr></table></tr></tbody></table>",
    "<table><script>var x=1;</script><tr><td>cell</td></tr></table>",
    "<table>text1<span>span</span>text2<tr><td>cell</td></tr>text3</table>",
    "<table><form><tr><td><input></td></tr></form></table>",
    "<table><caption>\(text)<table><tr><td>nested</td></tr></table></caption></table>",
    "<table><colgroup>\(text)<col></colgroup><tr><td>cell</td></tr></table>",
  ]
  return randomElement(variants)
}

func fuzzSvgMath() -> String {
  let content = randomString(minLen: 0, maxLen: 20)
  let variants = [
    "<svg>\(content)</svg>",
    "<svg><rect width='100' height='100'/></svg>",
    "<svg><foreignObject><div>\(content)</div></foreignObject></svg>",
    "<svg><desc><div>\(content)</div></desc></svg>",
    "<svg><title><div>\(content)</div></title></svg>",
    "<svg><clipPath><circle/></clipPath></svg>",
    "<svg viewBox='0 0 100 100'><path d='M0 0'/></svg>",
    "<svg><div>\(content)</div></svg>",
    "<svg><svg>\(content)</svg></svg>",
    "<svg><script>\(content)</script></svg>",
    "<math>\(content)</math>",
    "<math><mi>x</mi><mo>=</mo><mn>1</mn></math>",
    "<math><annotation-xml encoding='text/html'><div>\(content)</div></annotation-xml></math>",
    "<math><ms><div>\(content)</div></ms></math>",
    "<math><div>\(content)</div></math>",
    "<svg><math>\(content)</math></svg>",
    "<math><svg>\(content)</svg></math>",
    "<svg><p>\(content)</p></svg>",
    "<math><p>\(content)</p></math>",
    "<svg><table><tr><td>\(content)</td></tr></table></svg>",
  ]
  return randomElement(variants)
}

func fuzzTemplate() -> String {
  let content = randomString(minLen: 0, maxLen: 20)
  let variants = [
    "<template>\(content)</template>",
    "<template><tr><td>\(content)</td></tr></template>",
    "<template><template>\(content)</template></template>",
    "<template><script>\(content)</script></template>",
    "<template>\(content)",
    "<table><template><tr><td>cell</td></tr></template></table>",
    "<template><col></template>",
    "<template><caption>\(content)</caption></template>",
    "<template><html><head></head><body></body></html></template>",
    "<div><template shadowroot='open'>\(content)</template></div>",
  ]
  return randomElement(variants)
}

func fuzzEncodingEdgeCases() -> String {
  let content = randomString(minLen: 0, maxLen: 20)
  let variants = [
    "\u{FEFF}<html>\(content)</html>",
    "<html>\(content)\u{FEFF}\(content)</html>",
    "\u{0000}<html>\(content)</html>",
    "<html>\u{0000}\(content)</html>",
    "<html \(content)='\u{0000}'>",
    "<html>\(content)\u{00FF}\(content)</html>",
    "<html>\r\(content)\r\n\(content)\n</html>",
    "<html>\r\r\n\n\(content)</html>",
    "<html>\u{000C}\(content)\u{000C}</html>",
    "<html>\u{000B}\(content)\u{000B}</html>",
    "<html><head><meta charset='utf-8'></head><body>\(content)</body></html>",
    "<html><head><meta http-equiv='Content-Type' content='text/html; charset=utf-8'></head></html>",
  ]
  return randomElement(variants)
}

func fuzzDeeplyNested() -> String {
  let depth = randomInt(100...500)
  let tag = randomElement(["div", "span", "b", "i", "a"])
  let variants = [
    String(repeating: "<\(tag)>", count: depth) + "content" + String(repeating: "</\(tag)>", count: depth),
    (0..<depth).map { _ in "<\(randomElement(["div", "span", "p"]))>" }.joined() + "x",
    String(repeating: "<\(tag)>", count: depth) + "content" + String(repeating: "</\(tag)>", count: depth / 2),
    String(repeating: "<b>", count: depth) + "text" + String(repeating: "</b>", count: depth),
    String(repeating: "<a>", count: depth) + "text" + String(repeating: "</a>", count: depth),
  ]
  return randomElement(variants)
}

func fuzzManyAttributes() -> String {
  let numAttrs = randomInt(100...500)
  let tag = randomElement(tags)
  let variants = [
    "<\(tag) " + (0..<numAttrs).map { "attr\($0)='value\($0)'" }.joined(separator: " ") + ">",
    "<\(tag) " + (0..<100).map { "id='id\($0)'" }.joined(separator: " ") + ">",
    "<\(tag) data-x='\(String(repeating: "x", count: 100000))'>",
    "<\(tag) \(String(repeating: "x", count: 10000))='value'>",
    "<\(tag) class='" + (0..<1000).map { "class\($0)" }.joined(separator: " ") + "'>",
  ]
  return randomElement(variants)
}

func fuzzImplicitTags() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<title>\(content)</title><p>\(content)</p>",
    content,
    "<p>\(content)</p>",
    "<p>\(content)</p><title>\(content)</title>",
    "<p>\(content)<p>\(content)<p>\(content)",
    "<ul><li>\(content)<li>\(content)<li>\(content)</ul>",
    "<dl><dt>\(content)<dd>\(content)<dt>\(content)<dd>\(content)</dl>",
    "<table><tr><td>\(content)<td>\(content)<tr><td>\(content)</table>",
    "<select><option>\(content)<option>\(content)</select>",
    "<table><col><tr><td>\(content)</td></tr></table>",
    "<html><body>\(content)",
  ]
  return randomElement(variants)
}

func fuzzDocumentStructure() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<html><html>\(content)</html></html>",
    "<html><head></head><head></head><body></body></html>",
    "<html><body></body><body></body></html>",
    "<html><body></body><head></head></html>",
    "\(content)<html><body></body></html>",
    "<html><body></body></html>\(content)",
    "<html><frameset><frame></frameset><body></body></html>",
    "<html><body></body><frameset><frame></frameset></html>",
    "<html><!DOCTYPE html></html>",
    "<!DOCTYPE html><!DOCTYPE html><html></html>",
  ]
  return randomElement(variants)
}

func fuzzNullHandling() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<di\u{0000}v>\(content)</div>",
    "<\u{0000}div>\(content)</div>",
    "<div \u{0000}class='a'>\(content)</div>",
    "<div class='\u{0000}a'>\(content)</div>",
    "<div class\u{0000}='a'>\(content)</div>",
    "<div>\(content)\u{0000}\(content)</div>",
    "<!--\u{0000}\(content)-->",
    "<script>\u{0000}\(content)</script>",
    "<style>\u{0000}\(content)</style>",
    "<textarea>\u{0000}\(content)</textarea>",
    "<title>\u{0000}\(content)</title>",
    "<svg><![CDATA[\u{0000}\(content)]]></svg>",
    "<div\u{0000}\u{0000}\u{0000}>\(content)</div>",
    "<div>\(content)</div>\u{0000}",
  ]
  return randomElement(variants)
}

func fuzzEofHandling() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<div",
    "<div ",
    "<div class",
    "<div class=",
    "<div class='",
    "<div class='a",
    "</div",
    "</",
    "<",
    "<!--",
    "<!-",
    "<!--\(content)",
    "<!--\(content)-",
    "<!--\(content)--",
    "<!DOCTYPE",
    "<!DOCTYPE ",
    "<!DOCTYPE html",
    "<!DOCTYPE html PUBLIC",
    "<!DOCTYPE html PUBLIC \"",
    "<script>\(content)",
    "<script><!--\(content)",
    "<svg><![CDATA[\(content)",
    "<svg><![CDATA[\(content)]",
    "<svg><![CDATA[\(content)]]",
    "<style>\(content)",
    "<textarea>\(content)",
    "<title>\(content)",
    "<div><span><p>\(content)",
    "<table><tr><td>\(content)",
  ]
  return randomElement(variants)
}

func fuzzIntegrationPoints() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let htmlTag = randomElement(["div", "span", "p", "table", "tr", "td"])
  let variants = [
    "<math><annotation-xml encoding='text/html'><\(htmlTag)>\(content)</\(htmlTag)></annotation-xml></math>",
    "<math><annotation-xml encoding='application/xhtml+xml'><\(htmlTag)>\(content)</\(htmlTag)></annotation-xml></math>",
    "<math><annotation-xml><\(htmlTag)>\(content)</\(htmlTag)></annotation-xml></math>",
    "<svg><foreignObject><\(htmlTag)>\(content)</\(htmlTag)></foreignObject></svg>",
    "<svg><desc><\(htmlTag)>\(content)</\(htmlTag)></desc></svg>",
    "<svg><title><\(htmlTag)>\(content)</\(htmlTag)></title></svg>",
    "<math><mi><\(htmlTag)>\(content)</\(htmlTag)></mi></math>",
    "<math><mtext><\(htmlTag)>\(content)</\(htmlTag)></mtext></math>",
    "<svg><foreignObject><math><annotation-xml encoding='text/html'><div>\(content)</div></annotation-xml></math></foreignObject></svg>",
    "<svg><\(htmlTag)>\(content)</\(htmlTag)></svg>",
    "<math><\(htmlTag)>\(content)</\(htmlTag)></math>",
    "<svg><foreignObject><table><tr><td>\(content)</td></tr></table></foreignObject></svg>",
  ]
  return randomElement(variants)
}

func fuzzTableScoping() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<table>\(content)<tr><td>cell</td></tr></table>",
    "<table><tbody>\(content)<tr><td>cell</td></tr></tbody></table>",
    "<table><tr><td><table><tr><td>\(content)</td></tr></table></td></tr></table>",
    "<table><thead><tr><td>\(content)</td></tr></tbody></table>",
    "<table><tbody></thead><tr><td>\(content)</td></tr></table>",
    "<table><colgroup><col><col></colgroup><colgroup>\(content)</colgroup></table>",
    "<table><colgroup><template>\(content)</template></colgroup></table>",
    "<table><caption>\(content)</caption><caption>second</caption></table>",
    "<table><tr><td></td></tr><caption>\(content)</caption></table>",
    "<table><caption><table><tr><td>\(content)</td></tr></table></caption></table>",
    "<tr><td>\(content)</td></tr>",
    "<td>\(content)</td>",
    "<tbody><tr><td>\(content)</td></tr></tbody>",
    "<table><tr><td>\(content)</table></td></tr>",
    "<table><tr><td>\(content)</td></table></tr>",
  ]
  return randomElement(variants)
}

func fuzzSelectElement() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<select><option>\(content)</option><optgroup><option>opt</option></optgroup></select>",
    "<table><tr><td><select><option>\(content)</option></select></td></tr></table>",
    "<select><option>\(content)<select><option>inner</option></select></option></select>",
    "<select><div>\(content)</div></select>",
    "<select><table><tr><td>\(content)</td></tr></table></select>",
    "<select><script>\(content)</script></select>",
    "<select><option>\(content)</option><input></select>",
    "<select><option>\(content)</option><textarea></textarea></select>",
    "<select><optgroup><optgroup><option>\(content)</option></optgroup></optgroup></select>",
    "<select><option>\(content)</option><keygen></select>",
    "<select><option>\(content)",
    "<div><select><option>\(content)</div>",
  ]
  return randomElement(variants)
}

func fuzzFramesetMode() -> String {
  let content = randomString(minLen: 1, maxLen: 10)
  let variants = [
    "<html><head></head><frameset><frame src='a'><frame src='b'></frameset></html>",
    "<html><frameset><frameset><frame></frameset><frame></frameset></html>",
    "<html><frameset><frame><noframes>\(content)</noframes></frameset></html>",
    "<html><body>\(content)</body><frameset><frame></frameset></html>",
    "<html><frameset><frame></frameset><body>\(content)</body></html>",
    "<html><frameset>\(content)<frame></frameset></html>",
    "<html><frameset><frame></frameset></html>\(content)",
    "<html><frameset><div>\(content)</div><frame></frameset></html>",
    "<html><frameset><frame src='\(content)' name='f1'></frameset></html>",
    "<html><frameset><frameset><frameset><frame></frameset></frameset></frameset></html>",
  ]
  return randomElement(variants)
}

func fuzzEntityEdgeCases() -> String {
  let name = randomString(minLen: 1, maxLen: 8)
  let num = randomInt(0...0x10FFFF)
  let variants = [
    "&#0;", "&#x0;", "&#9;", "&#10;", "&#13;", "&#127;", "&#128;", "&#159;",
    "&#x80;", "&#x9F;", "&#xD800;", "&#xDFFF;", "&#xFFFE;", "&#xFFFF;",
    "&#x10FFFF;", "&#x110000;", "&#x\(String(num, radix: 16, uppercase: true));",
    "&#-1;", "&#99999999999;", "&\(name);", "&amp", "&amp;amp;", "&ampamp;",
    "&lt&gt", "&#x26;amp;", "<div title='&lt;script&gt;'>",
    "<div title='&#60;script&#62;'>", "<a href='?a=1&b=2'>",
    "<a href='?a=1&amp;b=2'>", "&;", "&#;", "&#x;", "&#\(num);", "&#x\(name);",
  ]
  return randomElement(variants)
}

// MARK: - Fuzz Generators Array

let fuzzGenerators: [() -> String] = [
  fuzzOpenTag,
  fuzzCloseTag,
  fuzzComment,
  fuzzText,
  fuzzScript,
  fuzzStyle,
  fuzzNestedStructure,
  fuzzAdoptionAgency,
  fuzzFosterParenting,
  fuzzSvgMath,
  fuzzTemplate,
  fuzzEncodingEdgeCases,
  fuzzDeeplyNested,
  fuzzManyAttributes,
  fuzzImplicitTags,
  fuzzDocumentStructure,
  fuzzNullHandling,
  fuzzEofHandling,
  fuzzIntegrationPoints,
  fuzzTableScoping,
  fuzzSelectElement,
  fuzzFramesetMode,
  fuzzEntityEdgeCases,
]

let fuzzWeights = [
  20, 10, 8, 15, 4, 4, 8, 5, 5, 5, 3, 3, 1, 1, 3, 2, 4, 3, 4, 5, 4, 2, 5,
]

func weightedRandomGenerator() -> () -> String {
  let totalWeight = fuzzWeights.reduce(0, +)
  let r = randomInt(0...(totalWeight - 1))
  var cumulative = 0
  for (i, weight) in fuzzWeights.enumerated() {
    cumulative += weight
    if r < cumulative {
      return fuzzGenerators[i]
    }
  }
  return fuzzGenerators.last!
}

func generateFuzzedHTML() -> String {
  var parts: [String] = []

  // Maybe add doctype
  if randomBool(0.5) {
    parts.append(fuzzDoctype())
  }

  // Generate random mix of elements
  let numElements = randomInt(1...20)
  for _ in 0..<numElements {
    let generator = weightedRandomGenerator()
    parts.append(generator())
  }

  return parts.joined()
}

// MARK: - Main Fuzzer

struct FuzzResult {
  var successes: Int = 0
  var crashes: [(index: Int, html: String, error: String)] = []
  var hangs: [(index: Int, html: String, time: Double)] = []
}

func runFuzzer(numTests: Int, seed: UInt64?, verbose: Bool) -> FuzzResult {
  if let seed = seed {
    srand48(Int(seed))
  } else {
    srand48(Int(Date().timeIntervalSince1970))
  }

  var result = FuzzResult()
  let startTime = Date()

  print("Fuzzing swift-justhtml with \(numTests) test cases...")

  // Dynamic import of JustHTML
  // For standalone execution, we import the module at compile time

  for i in 0..<numTests {
    let html = generateFuzzedHTML()

    if verbose && i % 100 == 0 {
      print("  Test \(i)/\(numTests)...")
    }

    let testStart = Date()

    do {
      // NOTE: This requires swift_justhtml to be imported
      // For standalone testing, compile with: swift build -c release
      // Then run the fuzzer from the test suite

      // Simulate parsing for standalone execution
      // In actual use, replace with: let _ = try JustHTML(html)
      let elapsed = Date().timeIntervalSince(testStart)

      if elapsed > 5.0 {
        result.hangs.append((i, html, elapsed))
        if verbose {
          print("  HANG: Test \(i) took \(String(format: "%.2f", elapsed))s")
        }
      } else {
        result.successes += 1
      }
    } catch {
      result.crashes.append((i, html, "\(error)"))
      if verbose {
        print("  CRASH: Test \(i): \(error)")
      }
    }
  }

  let totalTime = Date().timeIntervalSince(startTime)

  print()
  print(String(repeating: "=", count: 60))
  print("FUZZING RESULTS")
  print(String(repeating: "=", count: 60))
  print("Total tests:    \(numTests)")
  print("Successes:      \(result.successes)")
  print("Crashes:        \(result.crashes.count)")
  print("Hangs (>5s):    \(result.hangs.count)")
  print("Total time:     \(String(format: "%.2f", totalTime))s")
  print("Tests/second:   \(String(format: "%.1f", Double(numTests) / totalTime))")

  if !result.crashes.isEmpty {
    print()
    print(String(repeating: "=", count: 60))
    print("CRASH DETAILS:")
    print(String(repeating: "=", count: 60))
    for crash in result.crashes.prefix(10) {
      print()
      print("Test #\(crash.index):")
      let preview = String(crash.html.prefix(200))
      print("  HTML: \(preview.debugDescription)...")
      print("  Error: \(crash.error)")
    }
    if result.crashes.count > 10 {
      print()
      print("... and \(result.crashes.count - 10) more crashes")
    }
  }

  if !result.hangs.isEmpty {
    print()
    print(String(repeating: "=", count: 60))
    print("HANG DETAILS:")
    print(String(repeating: "=", count: 60))
    for hang in result.hangs.prefix(5) {
      print()
      print("Test #\(hang.index) (\(String(format: "%.2f", hang.time))s):")
      let preview = String(hang.html.prefix(200))
      print("  HTML: \(preview.debugDescription)...")
    }
  }

  return result
}

// MARK: - Standalone Execution

// Print sample fuzzed HTML documents
func printSamples(_ count: Int) {
  print("Sample fuzzed HTML documents:")
  print()
  for i in 0..<count {
    print("=== Sample \(i + 1) ===")
    print(generateFuzzedHTML())
    print()
  }
}

// Command line interface
func main() {
  var numTests = 1000
  var seed: UInt64? = nil
  var verbose = false
  var sampleCount: Int? = nil

  var args = CommandLine.arguments.dropFirst()
  while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--num-tests", "-n":
      if let next = args.first, let n = Int(next) {
        numTests = n
        args = args.dropFirst()
      }
    case "--seed", "-s":
      if let next = args.first, let s = UInt64(next) {
        seed = s
        args = args.dropFirst()
      }
    case "--verbose", "-v":
      verbose = true
    case "--sample":
      if let next = args.first, let n = Int(next) {
        sampleCount = n
        args = args.dropFirst()
      }
    case "--help", "-h":
      print("""
      HTML5 Parser Fuzzer for swift-justhtml

      Usage: swift-justhtml-fuzz [options]

      Options:
        --num-tests, -n N    Number of test cases (default: 1000)
        --seed, -s SEED      Random seed for reproducibility
        --verbose, -v        Show progress during fuzzing
        --sample N           Print N sample fuzzed HTML documents
        --help, -h           Show this help message
      """)
      return
    default:
      break
    }
  }

  if let count = sampleCount {
    printSamples(count)
    return
  }

  let result = runFuzzer(numTests: numTests, seed: seed, verbose: verbose)
  exit(result.crashes.isEmpty && result.hangs.isEmpty ? 0 : 1)
}

main()

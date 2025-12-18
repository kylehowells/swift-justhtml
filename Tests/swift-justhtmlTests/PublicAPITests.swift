import Foundation
import Testing

@testable import justhtml

// MARK: - Public API Tests

/// Test JustHTML.init(data:) - parsing from raw bytes
@Test func justHTMLInitFromData() async throws {
  // Include charset meta tag so encoding is detected correctly
  let html =
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body><p>Hello from Data</p></body></html>"
  let data = html.data(using: .utf8)!
  let doc = try JustHTML(data: data)
  #expect(doc.root.name == "#document")
  #expect(doc.toText() == "Hello from Data")
  #expect(doc.encoding == "utf-8")
}

/// Test JustHTML.init(data:) with UTF-16 encoding
@Test func justHTMLInitFromDataUTF16() async throws {
  let html = "<html><body><p>UTF-16 Test</p></body></html>"
  // Create UTF-16 data with BOM
  var data = Data([0xFE, 0xFF])  // UTF-16 BE BOM
  data.append(html.data(using: .utf16BigEndian)!)
  let doc = try JustHTML(data: data)
  #expect(doc.toText() == "UTF-16 Test")
}

/// Test JustHTML.init(data:) with transport encoding override
@Test func justHTMLInitFromDataWithTransportEncoding() async throws {
  let html = "<html><body><p>Transport Test</p></body></html>"
  let data = html.data(using: .utf8)!
  let doc = try JustHTML(data: data, transportEncoding: "utf-8")
  #expect(doc.toText() == "Transport Test")
  #expect(doc.encoding == "utf-8")
}

/// Test JustHTML.toHTML() method
@Test func justHTMLToHTML() async throws {
  let html = "<p>Test</p>"
  let doc = try JustHTML(html)
  let output = doc.toHTML(pretty: false)
  #expect(output.contains("<p>"))
  #expect(output.contains("Test"))
  #expect(output.contains("</p>"))
}

/// Test JustHTML.toHTML() with pretty printing
@Test func justHTMLToHTMLPretty() async throws {
  let html = "<div><p>Test</p></div>"
  let doc = try JustHTML(html)
  let output = doc.toHTML(pretty: true, indentSize: 4)
  #expect(output.contains("\n"))
}

/// Test strict mode throwing on parse error
@Test func justHTMLStrictModeThrows() async throws {
  // This HTML has a parse error (duplicate attribute)
  let html = "<p id=\"a\" id=\"b\">Test</p>"
  do {
    _ = try JustHTML(html, strict: true)
    #expect(Bool(false), "Should have thrown StrictModeError")
  } catch is StrictModeError {
    // Expected
  } catch {
    #expect(Bool(false), "Wrong error type: \(error)")
  }
}

/// Test collectErrors mode
@Test func justHTMLCollectErrors() async throws {
  // Using invalid HTML that triggers parse errors
  let html = "<p>Test</p>"
  let doc = try JustHTML(html, collectErrors: true)
  // Should have at least one error (missing DOCTYPE)
  #expect(!doc.errors.isEmpty)
  #expect(doc.errors[0].code == "expected-doctype-but-got-start-tag")
}

/// Test Node.replaceChild()
@Test func nodeReplaceChild() async throws {
  let parent = Node(name: "div")
  let child1 = Node(name: "p")
  let child2 = Node(name: "span")
  let replacement = Node(name: "a")

  parent.appendChild(child1)
  parent.appendChild(child2)

  let replaced = parent.replaceChild(replacement, oldNode: child1)
  #expect(replaced === child1)
  #expect(parent.children.count == 2)
  #expect(parent.children[0] === replacement)
  #expect(parent.children[1] === child2)
  #expect(child1.parent == nil)
  #expect(replacement.parent === parent)
}

/// Test Node.cloneNode(deep: false)
@Test func nodeCloneNodeShallow() async throws {
  let node = Node(name: "div", attrs: ["class": "test"])
  let child = Node(name: "p")
  node.appendChild(child)

  let clone = node.cloneNode(deep: false)
  #expect(clone.name == "div")
  #expect(clone.attrs["class"] == "test")
  #expect(clone.children.isEmpty)  // Shallow clone doesn't copy children
  #expect(clone !== node)
}

/// Test Node.cloneNode(deep: true)
@Test func nodeCloneNodeDeep() async throws {
  let node = Node(name: "div", attrs: ["class": "test"])
  let child = Node(name: "p")
  let grandchild = Node(name: "span")
  child.appendChild(grandchild)
  node.appendChild(child)

  let clone = node.cloneNode(deep: true)
  #expect(clone.name == "div")
  #expect(clone.children.count == 1)
  #expect(clone.children[0].name == "p")
  #expect(clone.children[0].children.count == 1)
  #expect(clone.children[0].children[0].name == "span")
  #expect(clone !== node)
  #expect(clone.children[0] !== child)
}

/// Test Node.hasChildNodes
@Test func nodeHasChildNodes() async throws {
  let parent = Node(name: "div")
  #expect(!parent.hasChildNodes)

  let child = Node(name: "p")
  parent.appendChild(child)
  #expect(parent.hasChildNodes)
}

/// Test Node.text property
@Test func nodeTextProperty() async throws {
  let textNode = Node(name: "#text", data: .text("Hello World"))
  #expect(textNode.text == "Hello World")

  let elementNode = Node(name: "p")
  #expect(elementNode.text == "")
}

/// Test Node.toHTML()
@Test func nodeToHTML() async throws {
  let doc = try JustHTML("<p>Test</p>")
  let body = try doc.query("body").first!
  let html = body.toHTML(pretty: false)
  #expect(html.contains("<p>"))
  #expect(html.contains("Test"))
}

/// Test Node.query() method (on Node directly)
@Test func nodeQuery() async throws {
  let doc = try JustHTML("<div><p class=\"test\">Hello</p></div>")
  let div = try doc.query("div").first!
  let results = try div.query("p.test")
  #expect(results.count == 1)
  #expect(results[0].name == "p")
}

/// Test ParseError description
@Test func parseErrorDescription() async throws {
  let error1 = ParseError(code: "test-error", message: "Test message", line: 10, column: 5)
  #expect(error1.description == "(10,5): test-error")

  let error2 = ParseError(code: "test-error")
  #expect(error2.description == "test-error")
}

/// Test SelectorError description
@Test func selectorErrorDescription() async throws {
  let error1 = SelectorError("Invalid selector", position: 5)
  #expect(error1.description.contains("position 5"))

  let error2 = SelectorError("Invalid selector")
  #expect(error2.description.contains("Invalid selector"))
}

/// Test StrictModeError
@Test func strictModeErrorCreation() async throws {
  let parseError = ParseError(code: "test-error")
  let strictError = StrictModeError(parseError)
  #expect(strictError.parseError.code == "test-error")
}

/// Test FragmentContext
@Test func fragmentContextParsing() async throws {
  let ctx = FragmentContext("div")
  let doc = try JustHTML("<p>Fragment</p>", fragmentContext: ctx)
  #expect(doc.fragmentContext?.tagName == "div")
  #expect(doc.toText() == "Fragment")
}

/// Test FragmentContext with special elements
@Test func fragmentContextScript() async throws {
  let ctx = FragmentContext("script")
  let doc = try JustHTML("var x = 1;", fragmentContext: ctx)
  // Script content is treated as raw text
  #expect(doc.root.name == "#document-fragment")
}

/// Test FragmentContext with textarea (rcdata)
@Test func fragmentContextTextarea() async throws {
  let ctx = FragmentContext("textarea")
  let doc = try JustHTML("Hello <b>World</b>", fragmentContext: ctx)
  // Textarea content treats tags as text
  #expect(doc.toText().contains("<b>"))
}

/// Test Doctype struct
@Test func doctypeCreation() async throws {
  let doctype = Doctype(
    name: "html", publicId: "-//W3C//DTD HTML 4.01//EN",
    systemId: "http://www.w3.org/TR/html4/strict.dtd")
  #expect(doctype.name == "html")
  #expect(doctype.publicId == "-//W3C//DTD HTML 4.01//EN")
  #expect(doctype.systemId == "http://www.w3.org/TR/html4/strict.dtd")
  #expect(!doctype.forceQuirks)
}

/// Test decodeEntitiesInText - basic named entities
@Test func decodeEntitiesInTextBasic() async throws {
  let result = decodeEntitiesInText("Hello &amp; World")
  #expect(result == "Hello & World")
}

/// Test decodeEntitiesInText - numeric entities
@Test func decodeEntitiesInTextNumeric() async throws {
  let result = decodeEntitiesInText("&#60;div&#62;")
  #expect(result == "<div>")
}

/// Test decodeEntitiesInText - hex entities
@Test func decodeEntitiesInTextHex() async throws {
  let result = decodeEntitiesInText("&#x3C;div&#x3E;")
  #expect(result == "<div>")
}

/// Test decodeEntitiesInText - legacy entities without semicolon
@Test func decodeEntitiesInTextLegacy() async throws {
  let result = decodeEntitiesInText("Hello &amp World")
  #expect(result == "Hello & World")
}

/// Test decodeEntitiesInText - in attribute mode
@Test func decodeEntitiesInTextAttribute() async throws {
  // In attribute mode, legacy entities followed by alphanumeric shouldn't decode
  let result = decodeEntitiesInText("foo&ampbar", inAttribute: true)
  #expect(result == "foo&ampbar")
}

/// Test decodeNumericEntity
@Test func decodeNumericEntityTest() async throws {
  // Basic decimal
  #expect(decodeNumericEntity("65") == "A")
  // Hex
  #expect(decodeNumericEntity("41", isHex: true) == "A")
  // Replacement character for invalid
  #expect(decodeNumericEntity("0") == "\u{FFFD}")
  // Windows-1252 replacements
  #expect(decodeNumericEntity("128") == "\u{20AC}")  // Euro sign
}

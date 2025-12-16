import Testing
@testable import swift_justhtml

@Test func smokeTestBasicHTML() async throws {
    // Test the milestone 0.5 example from the spec
    let html = "<html><head></head><body><p>Hello</p></body></html>"
    let doc = try JustHTML(html)

    // Verify we get a document root
    #expect(doc.root.name == "#document")

    // Verify basic structure: html > head + body > p > "Hello"
    #expect(doc.root.children.count == 1)

    let htmlElement = doc.root.children[0]
    #expect(htmlElement.name == "html")
    #expect(htmlElement.children.count == 2)

    let headElement = htmlElement.children[0]
    #expect(headElement.name == "head")

    let bodyElement = htmlElement.children[1]
    #expect(bodyElement.name == "body")
    #expect(bodyElement.children.count == 1)

    let pElement = bodyElement.children[0]
    #expect(pElement.name == "p")
    #expect(pElement.children.count == 1)

    let textNode = pElement.children[0]
    #expect(textNode.name == "#text")

    // Verify toText() returns "Hello"
    let text = doc.toText()
    #expect(text == "Hello")

    // Verify no errors for valid input
    #expect(doc.errors.isEmpty)
}

@Test func smokeTestMinimalHTML() async throws {
    // Even simpler test
    let html = "<p>Test</p>"
    let doc = try JustHTML(html)

    #expect(doc.toText() == "Test")
}

@Test func smokeTestWithAttributes() async throws {
    let html = "<p class=\"intro\" id=\"greeting\">Hello World</p>"
    let doc = try JustHTML(html)

    #expect(doc.toText() == "Hello World")

    // Find the p element
    let body = doc.root.children[0].children[1]  // html > body
    let p = body.children[0]
    #expect(p.attrs["class"] == "intro")
    #expect(p.attrs["id"] == "greeting")
}

@Test func smokeTestNestedElements() async throws {
    let html = "<div><p>One</p><p>Two</p></div>"
    let doc = try JustHTML(html)

    // Should get both text contents
    let text = doc.toText(separator: " ")
    #expect(text == "One Two")
}

@Test func smokeTestImplicitTags() async throws {
    // HTML parser should create html, head, body automatically
    let html = "Hello"
    let doc = try JustHTML(html)

    #expect(doc.root.name == "#document")
    #expect(doc.root.children.count == 1)

    let htmlElement = doc.root.children[0]
    #expect(htmlElement.name == "html")

    // Should have head and body
    #expect(htmlElement.children.count == 2)
    #expect(htmlElement.children[0].name == "head")
    #expect(htmlElement.children[1].name == "body")

    #expect(doc.toText() == "Hello")
}

@Test func smokeTestTestFormat() async throws {
    let html = "<p>Hello</p>"
    let doc = try JustHTML(html)

    let testFormat = doc.toTestFormat()

    // The test format should show the tree structure
    #expect(testFormat.contains("<html>"))
    #expect(testFormat.contains("<head>"))
    #expect(testFormat.contains("<body>"))
    #expect(testFormat.contains("<p>"))
    #expect(testFormat.contains("\"Hello\""))
}

@Test func smokeTestDoctype() async throws {
    let html = "<!DOCTYPE html><html><head></head><body></body></html>"
    let doc = try JustHTML(html)

    #expect(doc.root.children.count == 2)  // doctype + html

    let doctypeNode = doc.root.children[0]
    #expect(doctypeNode.name == "!doctype")
}

@Test func smokeTestComment() async throws {
    let html = "<!--comment--><p>Text</p>"
    let doc = try JustHTML(html)

    // Find the comment (should be first child of body or before html)
    let testFormat = doc.toTestFormat()
    #expect(testFormat.contains("<!-- comment -->"))
}

@Test func smokeTestVoidElements() async throws {
    let html = "<p>Before<br>After</p>"
    let doc = try JustHTML(html)

    // br is a void element, should not have children
    let body = doc.root.children[0].children[1]  // html > body
    let p = body.children[0]

    // p should have: "Before", <br>, "After"
    #expect(p.children.count == 3)
    #expect(p.children[1].name == "br")
    #expect(p.children[1].children.isEmpty)
}

@Test func smokeTestMultipleParagraphs() async throws {
    // <p> tags auto-close previous <p>
    let html = "<p>One<p>Two"
    let doc = try JustHTML(html)

    let body = doc.root.children[0].children[1]  // html > body

    // Should have two sibling p elements
    #expect(body.children.count == 2)
    #expect(body.children[0].name == "p")
    #expect(body.children[1].name == "p")
}

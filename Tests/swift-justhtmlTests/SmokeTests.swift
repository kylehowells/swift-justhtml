import Foundation
import Testing

@testable import justhtml

// MARK: - Smoke Tests

@Test func smokeTestBasicHTML() async throws {
  let html = "<html><head></head><body><p>Hello</p></body></html>"
  let doc = try JustHTML(html)
  #expect(doc.root.name == "#document")
  #expect(doc.toText() == "Hello")
}

@Test func smokeTestMinimalHTML() async throws {
  let html = "<p>Test</p>"
  let doc = try JustHTML(html)
  #expect(doc.toText() == "Test")
}

@Test func smokeTestImplicitTags() async throws {
  let html = "Hello"
  let doc = try JustHTML(html)
  #expect(doc.root.name == "#document")
  let htmlElement = doc.root.children[0]
  #expect(htmlElement.name == "html")
  #expect(htmlElement.children.count == 2)
  #expect(htmlElement.children[0].name == "head")
  #expect(htmlElement.children[1].name == "body")
}

@Test func smokeTestHeadLink() async throws {
  let html = "<head><meta></head><link>"
  let doc = try JustHTML(html)
  #expect(doc.toText().isEmpty)
}

@Test func smokeTestTableNested() async throws {
  let html = "<table><tr><tr><td><td><span><th><span>X"
  let doc = try JustHTML(html)
  #expect(doc.toText() == "X")
}

@Test func smokeTestMultiBody() async throws {
  let html = "<body><body><base><link><meta><title><p></title><body><p></body>"
  let doc = try JustHTML(html)
  let output = doc.toTestFormat()
  print(output)
  #expect(doc.toText() == "<p>")  // Text inside title
}

@Test func smokeTestTemplate() async throws {
  let html = "<body><template>Hello</template>"
  let doc = try JustHTML(html)
  let output = doc.toTestFormat()
  print(output)
  #expect(doc.toText().isEmpty)
}

@Test func smokeTestTextWithInlineElements() async throws {
  // Verify no extra spaces around inline elements
  let doc = try JustHTML("<p><strong>Hello</strong>, World!</p>")
  #expect(doc.toText() == "Hello, World!")

  // Verify original spacing is preserved
  let doc2 = try JustHTML("<p>Hello <strong>World</strong></p>")
  #expect(doc2.toText() == "Hello World")
}

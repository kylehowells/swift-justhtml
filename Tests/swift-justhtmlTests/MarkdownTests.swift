import Foundation
import Testing
@testable import justhtml

// MARK: - Markdown Tests

@Test func markdownHeadings() async throws {
	let html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("# Title"))
	#expect(md.contains("## Subtitle"))
	#expect(md.contains("### Section"))
}

@Test func markdownParagraph() async throws {
	let html = "<p>Hello World</p><p>Second paragraph</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("Hello World"))
	#expect(md.contains("Second paragraph"))
}

@Test func markdownStrong() async throws {
	let html = "<p>This is <strong>bold</strong> text</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("**bold**"))
	// Verify no newlines inside the bold markers
	#expect(md.contains("This is **bold** text"))
}

@Test func markdownStrongAtStart() async throws {
	let html = "<p><strong>Hello</strong>, World!</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	// The bold markers should wrap the text without newlines inside
	#expect(md == "**Hello**, World!")
}

@Test func markdownEmphasis() async throws {
	let html = "<p>This is <em>italic</em> text</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("*italic*"))
}

@Test func markdownCode() async throws {
	let html = "<p>Use <code>print()</code> to output</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("`print()`"))
}

@Test func markdownPreformatted() async throws {
	let html = "<pre><code>func hello() {\n    print(\"Hi\")\n}</code></pre>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("```"))
	#expect(md.contains("func hello()"))
}

@Test func markdownLink() async throws {
	let html = "<a href=\"https://example.com\">Example</a>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("[Example](https://example.com)"))
}

@Test func markdownImage() async throws {
	let html = "<img src=\"photo.jpg\" alt=\"A photo\">"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("![A photo](photo.jpg)"))
}

@Test func markdownUnorderedList() async throws {
	let html = "<ul><li>Apple</li><li>Banana</li><li>Cherry</li></ul>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("- Apple"))
	#expect(md.contains("- Banana"))
	#expect(md.contains("- Cherry"))
}

@Test func markdownOrderedList() async throws {
	let html = "<ol><li>First</li><li>Second</li><li>Third</li></ol>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("1. First"))
	#expect(md.contains("2. Second"))
	#expect(md.contains("3. Third"))
}

@Test func markdownBlockquote() async throws {
	let html = "<blockquote>This is a quote</blockquote>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("> This is a quote"))
}

@Test func markdownHorizontalRule() async throws {
	let html = "<p>Above</p><hr><p>Below</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("---"))
}

@Test func markdownTable() async throws {
	let html = """
	<table>
	    <tr><th>Name</th><th>Age</th></tr>
	    <tr><td>Alice</td><td>30</td></tr>
	    <tr><td>Bob</td><td>25</td></tr>
	</table>
	"""
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("| Name"))
	#expect(md.contains("| ---"))
	#expect(md.contains("| Alice"))
	#expect(md.contains("| Bob"))
}

@Test func markdownStrikethrough() async throws {
	let html = "<p>This is <del>deleted</del> text</p>"
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()
	#expect(md.contains("~~deleted~~"))
}

@Test func markdownComplex() async throws {
	let html = """
	<article>
	    <h1>My Article</h1>
	    <p>Welcome to <strong>my article</strong> about <em>programming</em>.</p>
	    <h2>Features</h2>
	    <ul>
	        <li>Fast</li>
	        <li>Reliable</li>
	    </ul>
	    <p>Visit <a href="https://example.com">our site</a> for more.</p>
	</article>
	"""
	let doc = try JustHTML(html)
	let md = doc.toMarkdown()

	#expect(md.contains("# My Article"))
	#expect(md.contains("**my article**"))
	#expect(md.contains("*programming*"))
	#expect(md.contains("## Features"))
	#expect(md.contains("- Fast"))
	#expect(md.contains("- Reliable"))
	#expect(md.contains("[our site](https://example.com)"))
}

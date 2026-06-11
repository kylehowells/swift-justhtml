import Foundation
import Testing
@testable import justhtml

// MARK: - CSS Selector Tests

@Test func selectorTypeSelector() async throws {
	let html = "<div><p>Hello</p><span>World</span></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "p")
	#expect(results.count == 1)
	#expect(results[0].name == "p")
}

@Test func selectorIdSelector() async throws {
	let html = "<div><p id=\"main\">Hello</p><p>World</p></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "#main")
	#expect(results.count == 1)
	#expect(results[0].attrs["id"] == "main")
}

@Test func selectorClassSelector() async throws {
	let html = "<div><p class=\"highlight\">One</p><p class=\"highlight\">Two</p><p>Three</p></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: ".highlight")
	#expect(results.count == 2)
}

@Test func selectorUniversalSelector() async throws {
	let html = "<div><p>One</p><span>Two</span></div>"
	let doc = try JustHTML(html)

	// Universal selector matches all elements
	let results = try query(doc.root, selector: "*")
	#expect(results.count >= 4) // html, body, div, p, span at minimum
}

@Test func selectorDescendantCombinator() async throws {
	let html = "<div><p><span>Text</span></p></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "div span")
	#expect(results.count == 1)
	#expect(results[0].name == "span")
}

@Test func selectorChildCombinator() async throws {
	let html = "<div><span>Direct</span><p><span>Nested</span></p></div>"
	let doc = try JustHTML(html)

	// > means direct child only
	let results = try query(doc.root, selector: "div > span")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Direct")
}

@Test func selectorNextSiblingCombinator() async throws {
	let html = "<div><p>First</p><span>Second</span><span>Third</span></div>"
	let doc = try JustHTML(html)

	// + means immediately following sibling
	let results = try query(doc.root, selector: "p + span")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Second")
}

@Test func selectorSubsequentSiblingCombinator() async throws {
	let html = "<div><p>First</p><span>Second</span><span>Third</span></div>"
	let doc = try JustHTML(html)

	// ~ means any following sibling
	let results = try query(doc.root, selector: "p ~ span")
	#expect(results.count == 2)
}

@Test func selectorAttributeExists() async throws {
	let html = "<div><a href=\"link\">With</a><a>Without</a></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "a[href]")
	#expect(results.count == 1)
	#expect(results[0].toText() == "With")
}

@Test func selectorAttributeNameFallbackIsNormalizedOnce() async throws {
	let html = "<div data-mode=\"active\">Active</div><div>Inactive</div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "[DATA-MODE]")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Active")
}

@Test func selectorAttributeEquals() async throws {
	let html = "<input type=\"text\"><input type=\"checkbox\">"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "input[type=\"text\"]")
	#expect(results.count == 1)
	#expect(results[0].attrs["type"] == "text")
}

@Test func selectorAttributeContains() async throws {
	let html = "<div class=\"one two three\"><div class=\"four\"></div></div>"
	let doc = try JustHTML(html)

	// ~= matches word in space-separated list
	let results = try query(doc.root, selector: "[class~=\"two\"]")
	#expect(results.count == 1)
}

@Test func selectorAttributeStartsWith() async throws {
	let html = "<a href=\"https://example.com\">HTTPS</a><a href=\"http://example.com\">HTTP</a>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "a[href^=\"https\"]")
	#expect(results.count == 1)
	#expect(results[0].toText() == "HTTPS")
}

@Test func selectorAttributeEndsWith() async throws {
	let html = "<img src=\"photo.jpg\"><img src=\"photo.png\">"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "img[src$=\".jpg\"]")
	#expect(results.count == 1)
}

@Test func selectorAttributeContainsSubstring() async throws {
	let html = "<a href=\"example.com/page\">Link</a><a href=\"other.com\">Other</a>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "a[href*=\"example\"]")
	#expect(results.count == 1)
}

@Test func selectorAttributeCaseInsensitiveOperators() async throws {
	let html = """
	<div data-kind="Primary-Button" data-tags="Alpha beta" data-path="/Docs/Guide.HTML"></div>
	<div data-kind="secondary-link" data-tags="gamma" data-path="/assets/image.png"></div>
	"""
	let doc = try JustHTML(html)

	#expect(try query(doc.root, selector: "[data-kind=\"primary-button\" i]").count == 1)
	#expect(try query(doc.root, selector: "[data-tags~=\"alpha\" i]").count == 1)
	#expect(try query(doc.root, selector: "[data-kind|=\"primary\" i]").count == 1)
	#expect(try query(doc.root, selector: "[data-path^=\"/docs\" i]").count == 1)
	#expect(try query(doc.root, selector: "[data-path$=\".html\" i]").count == 1)
	#expect(try query(doc.root, selector: "[data-path*=\"guide\" i]").count == 1)
}

@Test func selectorFirstChild() async throws {
	let html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "li:first-child")
	#expect(results.count == 1)
	#expect(results[0].toText() == "One")
}

@Test func selectorLastChild() async throws {
	let html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "li:last-child")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Three")
}

@Test func selectorNthChild() async throws {
	let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li><li>5</li></ul>"
	let doc = try JustHTML(html)

	// :nth-child(2) selects the 2nd child
	let results = try query(doc.root, selector: "li:nth-child(2)")
	#expect(results.count == 1)
	#expect(results[0].toText() == "2")
}

@Test func selectorNthChildOdd() async throws {
	let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "li:nth-child(odd)")
	#expect(results.count == 2)
	#expect(results[0].toText() == "1")
	#expect(results[1].toText() == "3")
}

@Test func selectorNthChildEven() async throws {
	let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "li:nth-child(even)")
	#expect(results.count == 2)
	#expect(results[0].toText() == "2")
	#expect(results[1].toText() == "4")
}

@Test func selectorNthChildFormula() async throws {
	let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li><li>5</li><li>6</li></ul>"
	let doc = try JustHTML(html)

	// :nth-child(3n) selects every 3rd child (3, 6)
	let results = try query(doc.root, selector: "li:nth-child(3n)")
	#expect(results.count == 2)
	#expect(results[0].toText() == "3")
	#expect(results[1].toText() == "6")
}

@Test func selectorOfTypePseudoClasses() async throws {
	let html = "<section><p>One</p><span>A</span><p>Two</p><span>B</span><p>Three</p></section>"
	let doc = try JustHTML(html)

	let first = try query(doc.root, selector: "p:first-of-type")
	#expect(first.count == 1)
	#expect(first[0].toText() == "One")

	let last = try query(doc.root, selector: "p:last-of-type")
	#expect(last.count == 1)
	#expect(last[0].toText() == "Three")

	let only = try query(doc.root, selector: "section:only-of-type")
	#expect(only.count == 1)

	let nth = try query(doc.root, selector: "p:nth-of-type(2)")
	#expect(nth.count == 1)
	#expect(nth[0].toText() == "Two")

	let nthLast = try query(doc.root, selector: "p:nth-last-of-type(2)")
	#expect(nthLast.count == 1)
	#expect(nthLast[0].toText() == "Two")
}

@Test func selectorNot() async throws {
	let html = "<div><p class=\"skip\">Skip</p><p>Keep</p><p class=\"skip\">Skip</p></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "p:not(.skip)")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Keep")
}

@Test func selectorEmpty() async throws {
	let html = "<div><p></p><p>Text</p></div>"
	let doc = try JustHTML(html)

	let results = try query(doc.root, selector: "p:empty")
	#expect(results.count == 1)
}

@Test func selectorCompound() async throws {
	let html = "<p class=\"highlight\" id=\"main\">Target</p><p class=\"highlight\">Other</p>"
	let doc = try JustHTML(html)

	// Compound selector: p.highlight#main
	let results = try query(doc.root, selector: "p.highlight#main")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Target")
}

@Test func selectorGroup() async throws {
	let html = "<div><p>Para</p><span>Span</span><a>Link</a></div>"
	let doc = try JustHTML(html)

	// Group selector: p, span
	let results = try query(doc.root, selector: "p, span")
	#expect(results.count == 2)
}

@Test func selectorMatches() async throws {
	let html = "<p class=\"test\">Hello</p>"
	let doc = try JustHTML(html)

	let p = try query(doc.root, selector: "p")[0]

	#expect(try matches(p, selector: "p"))
	#expect(try matches(p, selector: ".test"))
	#expect(try matches(p, selector: "p.test"))
	#expect(try !matches(p, selector: "div"))
	#expect(try !matches(p, selector: ".other"))
}

@Test func selectorComplex() async throws {
	let html = """
	<div id="container">
	    <ul class="list">
	        <li class="item">One</li>
	        <li class="item active">Two</li>
	        <li class="item">Three</li>
	    </ul>
	</div>
	"""
	let doc = try JustHTML(html)

	// Complex selector with descendant and class
	let results = try query(doc.root, selector: "#container .list > .item.active")
	#expect(results.count == 1)
	#expect(results[0].toText() == "Two")
}

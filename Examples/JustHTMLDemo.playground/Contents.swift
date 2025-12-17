/*:
 # swift-justhtml Demo

 This playground demonstrates the key features of swift-justhtml,
 a dependency-free HTML5 parser for Swift.

 ## Getting Started

 To use this playground:
 1. Open the swift-justhtml package in Xcode
 2. Wait for SPM to resolve dependencies
 3. Open this playground file
 4. Run the playground (⌘+Shift+Return)
 */

import Foundation
import justhtml

//: ## Basic Parsing
//: Parse an HTML document from a string:

let html = """
<!DOCTYPE html>
<html>
<head>
    <title>Demo Page</title>
</head>
<body>
    <h1>Welcome</h1>
    <p class="intro">This is a demo of <strong>swift-justhtml</strong>.</p>
    <ul>
        <li><a href="https://github.com">GitHub</a></li>
        <li><a href="https://swift.org">Swift.org</a></li>
    </ul>
</body>
</html>
"""

let doc = try! JustHTML(html)
print("Parsed document with \(doc.root.children.count) child nodes")

//: ## Extracting Text
//: Get all text content from the document:

let text = doc.toText()
print("Text content:")
print(text)
print()

//: ## CSS Selectors
//: Query the document using CSS selectors:

/// Find all links
let links = try! doc.query("a[href]")
print("Found \(links.count) links:")
for link in links {
	let href = link.attrs["href"] ?? ""
	let text = link.text
	print("  - \(text): \(href)")
}

print()

/// Find by class
let intros = try! doc.query(".intro")
print("Intro paragraphs: \(intros.count)")

/// Find by tag
let headings = try! doc.query("h1, h2, h3")
print("Headings: \(headings.count)")

//: ## Serialization
//: Convert the document to different formats:

// Pretty HTML
print("\n--- Pretty HTML ---")
print(doc.toHTML(pretty: true, indentSize: 2))

// Compact HTML
print("\n--- Compact HTML ---")
print(doc.toHTML(pretty: false))

// Markdown
print("\n--- Markdown ---")
print(doc.toMarkdown())

//: ## Working with Nodes
//: Access and manipulate the DOM tree:

let body = try! doc.query("body").first!

print("\nBody has \(body.children.count) child elements:")
for child in body.children {
	if child.name != "#text" {
		print("  <\(child.name)>")
	}
}

//: ## Fragment Parsing
//: Parse HTML fragments in a specific context:

let tableContent = "<tr><td>Cell 1</td><td>Cell 2</td></tr>"
let ctx = FragmentContext("tbody")
let fragment = try! JustHTML(tableContent, fragmentContext: ctx)

print("\nParsed fragment:")
print(fragment.toHTML())

//: ## Streaming API
//: Memory-efficient event-based parsing:

print("\n--- Streaming Events ---")
let simpleHtml = "<p>Hello <b>World</b></p>"
for event in HTMLStream(simpleHtml) {
	switch event {
		case let .start(tag, _):
			print("START: <\(tag)>")

		case let .end(tag):
			print("END: </\(tag)>")

		case let .text(content):
			if !content.trimmingCharacters(in: .whitespaces).isEmpty {
				print("TEXT: \"\(content)\"")
			}

		default:
			break
	}
}

//: ## Error Handling
//: Detect and handle parse errors:

let malformedHtml = "<p>Unclosed paragraph"
let docWithErrors = try! JustHTML(malformedHtml, collectErrors: true)

print("\nParse errors: \(docWithErrors.errors.count)")
for error in docWithErrors.errors {
	print("  - \(error.code)")
}

print("\n✅ Demo complete!")

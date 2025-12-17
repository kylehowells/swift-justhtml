# Getting Started with swift-justhtml

Learn how to parse HTML documents, query elements, and extract content.

## Overview

swift-justhtml provides a simple, intuitive API for working with HTML in Swift. This guide covers the most common use cases.

## Parsing HTML

The ``JustHTML`` struct is the main entry point for parsing HTML:

```swift
import swift_justhtml

// Parse from a string
let doc = try JustHTML("<p>Hello</p>")

// Parse from raw bytes with encoding detection
let data = htmlString.data(using: .utf8)!
let doc2 = try JustHTML(data: data)
```

## Querying Elements

Use CSS selectors to find elements in the document:

```swift
// Find all paragraphs
let paragraphs = try doc.query("p")

// Find by class
let intros = try doc.query(".intro")

// Find by ID
let header = try doc.query("#header")

// Complex selectors
let links = try doc.query("nav > ul > li > a[href]")
```

## Extracting Content

Extract text or serialize to different formats:

```swift
// Get plain text content
let text = doc.toText()

// Serialize to HTML
let html = doc.toHTML()

// Convert to Markdown
let markdown = doc.toMarkdown()
```

## Working with Nodes

The ``Node`` class represents elements in the DOM tree:

```swift
let nodes = try doc.query("div")
for node in nodes {
    // Access tag name
    print(node.name)

    // Access attributes
    if let href = node.attrs["href"] {
        print(href)
    }

    // Access children
    for child in node.children {
        print(child.name)
    }

    // Get text content
    print(node.text)
}
```

## Fragment Parsing

Parse HTML fragments in a specific context:

```swift
// Parse table rows as if inside a tbody
let ctx = FragmentContext("tbody")
let fragment = try JustHTML("<tr><td>Cell</td></tr>", fragmentContext: ctx)
```

## Streaming API

For memory-efficient parsing of large documents:

```swift
for event in HTMLStream("<p>Hello</p>") {
    switch event {
    case .start(let tag, let attrs):
        print("Start: \(tag)")
    case .end(let tag):
        print("End: \(tag)")
    case .text(let content):
        print("Text: \(content)")
    case .comment(let content):
        print("Comment: \(content)")
    case .doctype(let name, _, _):
        print("Doctype: \(name)")
    }
}
```

## Error Handling

Enable strict mode to catch parse errors:

```swift
do {
    let doc = try JustHTML("<p>Unclosed", strict: true)
} catch let error as StrictModeError {
    print("Parse error: \(error.parseError.code)")
}

// Or collect errors without throwing
let doc = try JustHTML("<p>Unclosed", collectErrors: true)
for error in doc.errors {
    print("\(error.line):\(error.column): \(error.code)")
}
```

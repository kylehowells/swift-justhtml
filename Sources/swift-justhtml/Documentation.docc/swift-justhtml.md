# ``swift_justhtml``

A dependency-free HTML5 parser for Swift, following the WHATWG HTML parsing specification.

## Overview

swift-justhtml is a complete HTML5 parser that passes all html5lib test suites. It provides a simple API for parsing HTML documents and fragments, querying with CSS selectors, and serializing to various formats.

```swift
import swift_justhtml

// Parse an HTML document
let doc = try JustHTML("<html><body><p class='intro'>Hello, World!</p></body></html>")

// Query with CSS selectors
let paragraphs = try doc.query("p.intro")

// Extract text content
let text = doc.toText()  // "Hello, World!"

// Serialize back to HTML
let html = doc.toHTML()
```

## Features

- **Full HTML5 Compliance**: Passes all 1,831 html5lib tree construction tests
- **Zero Dependencies**: Pure Swift implementation using only the standard library and Foundation
- **Cross-Platform**: Works on macOS, iOS, tvOS, watchOS, visionOS, and Linux
- **CSS Selectors**: Query documents using standard CSS selector syntax
- **Multiple Output Formats**: Serialize to HTML, plain text, or Markdown
- **Streaming API**: Memory-efficient event-based parsing with ``HTMLStream``
- **Fragment Parsing**: Parse HTML fragments in specific contexts with ``FragmentContext``

## Topics

### Guides

- <doc:GettingStarted>
- <doc:Examples>
- <doc:Performance>
- <doc:Benchmarking>

### Essentials

- ``JustHTML``
- ``Node``

### Parsing Options

- ``FragmentContext``
- ``Namespace``

### Streaming

- ``HTMLStream``
- ``StreamEvent``

### Errors

- ``ParseError``
- ``StrictModeError``
- ``SelectorError``

### Serialization

- ``Doctype``

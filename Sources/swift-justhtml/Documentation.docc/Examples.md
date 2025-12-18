# Examples

Example applications demonstrating swift-justhtml usage.

## Overview

The `Examples/` directory contains several CLI tools and an interactive playground showing how to use swift-justhtml for common HTML processing tasks.

## CLI Tools

### htmltool

A comprehensive HTML processing tool demonstrating multiple APIs.

**Commands:**
- `text` - Extract plain text
- `html` - Re-serialize HTML
- `markdown` - Convert to Markdown
- `query` - CSS selector queries
- `stream` - Event-based parsing

```bash
swift run htmltool text page.html
swift run htmltool query "a[href]" page.html
```

**APIs demonstrated:**
- ``JustHTML`` - Parsing
- ``Node/toText(separator:strip:collapseWhitespace:)`` - Text extraction
- ``Node/toHTML(pretty:indentSize:)`` - Serialization
- ``Node/toMarkdown()`` - Markdown conversion
- ``JustHTML/query(_:)`` - CSS selectors
- ``HTMLStream`` - Streaming parser

### html2md

A minimal HTML to Markdown converter.

```bash
swift run html2md page.html
curl -s https://example.com | swift run html2md
```

**APIs demonstrated:**
- ``JustHTML`` - Parsing
- ``Node/toMarkdown()`` - Markdown conversion

### extractlinks

Extract all links from an HTML document.

```bash
swift run extractlinks page.html
swift run extractlinks --urls-only page.html
```

**APIs demonstrated:**
- ``JustHTML`` - Parsing
- ``JustHTML/query(_:)`` - CSS selectors
- ``Node/attrs`` - Attribute access
- ``Node/text`` - Text content

## Interactive Playground

### JustHTMLDemo.playground

An Xcode Playground with interactive examples covering:

- Basic parsing with ``JustHTML``
- CSS selectors with ``JustHTML/query(_:)``
- Serialization to HTML, text, and Markdown
- Working with ``Node`` properties and children
- Fragment parsing with ``FragmentContext``
- Streaming with ``HTMLStream``
- Error handling with ``StrictModeError``

Open in Xcode after building the package.

## Building and Running

```bash
# Build all examples
swift build

# Run an example
swift run htmltool --help
swift run html2md --help
swift run extractlinks --help
```

## See Also

- <doc:GettingStarted>
- [Examples on GitHub](https://github.com/kylehowells/swift-justhtml/tree/master/Examples)

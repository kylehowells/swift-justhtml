# Examples

This directory contains example applications demonstrating swift-justhtml usage.

## CLI Tools

### htmltool

A comprehensive CLI tool demonstrating multiple swift-justhtml features:
- Parse HTML and extract text
- Convert to Markdown
- Query with CSS selectors
- Stream parsing events

```bash
swift run htmltool text page.html
swift run htmltool query "a[href]" page.html
```

### html2md

A minimal HTML to Markdown converter demonstrating the `toMarkdown()` API.

```bash
swift run html2md page.html
echo '<p>Hello <strong>World</strong></p>' | swift run html2md
```

### extractlinks

Extract all links from an HTML file, demonstrating CSS selector queries.

```bash
swift run extractlinks page.html
curl -s https://example.com | swift run extractlinks
```

## Interactive

### JustHTMLDemo.playground

An Xcode Playground with interactive examples covering:
- Basic parsing
- CSS selectors
- Serialization (HTML, text, Markdown)
- Working with nodes
- Fragment parsing
- Streaming API
- Error handling

Open in Xcode after building the swift-justhtml package.

## Building Examples

```bash
# Build all examples
swift build

# Build specific example
swift build --product htmltool
swift build --product html2md
swift build --product extractlinks

# Run directly
swift run htmltool --help
swift run html2md --help
swift run extractlinks --help
```

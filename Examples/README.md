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
swift build --target HTML2MD
.build/debug/HTML2MD page.html
echo '<p>Hello <strong>World</strong></p>' | .build/debug/HTML2MD
```

### extractlinks

Extract all links from an HTML file, demonstrating CSS selector queries.

```bash
swift build --target ExtractLinks
.build/debug/ExtractLinks page.html
curl -s https://example.com | .build/debug/ExtractLinks
```

### fetchpage

Fetch and query HTML from URLs using CSS selectors. A jsoup-style CLI demonstrating network fetch combined with queries.

```bash
swift build --target FetchPage
.build/debug/FetchPage https://en.wikipedia.org/
.build/debug/FetchPage https://example.com "a[href]" --attr href
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
# Build specific example by target name
swift build --target HTMLTool
swift build --target HTML2MD
swift build --target ExtractLinks
swift build --target FetchPage

# Run htmltool directly (it's a package product)
swift run htmltool --help

# Run other examples from build directory
.build/debug/HTML2MD --help
.build/debug/ExtractLinks --help
.build/debug/FetchPage --help
```

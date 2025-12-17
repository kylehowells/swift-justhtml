# htmltool

A comprehensive HTML processing CLI tool demonstrating multiple swift-justhtml features.

## Features

- **text**: Extract plain text from HTML
- **html**: Parse and re-serialize HTML (with optional pretty-printing)
- **markdown**: Convert HTML to Markdown
- **query**: Find elements using CSS selectors
- **stream**: Show parsing events (SAX-style)

## Usage

```bash
# Extract text
swift run htmltool text page.html

# Convert to Markdown
swift run htmltool markdown page.html

# Query with CSS selectors
swift run htmltool query "a[href]" page.html
swift run htmltool query ".intro" page.html

# Pretty-print HTML
swift run htmltool html page.html

# Stream parsing events
swift run htmltool stream page.html

# Read from stdin
curl -s https://example.com | swift run htmltool text
```

## APIs Demonstrated

- `JustHTML` - HTML parsing
- `toText()` - Text extraction
- `toHTML(pretty:)` - HTML serialization
- `toMarkdown()` - Markdown conversion
- `query(_:)` - CSS selector queries
- `HTMLStream` - Event-based parsing

# fetchpage

Fetch and query HTML from URLs using CSS selectors. A jsoup-style CLI tool demonstrating network fetch combined with CSS selector queries.

## Usage

```bash
swift build --target FetchPage
.build/debug/FetchPage <url> [selector]
```

## Examples

```bash
# Get page title
.build/debug/FetchPage https://en.wikipedia.org/

# Query elements with CSS selector
.build/debug/FetchPage https://en.wikipedia.org/ "#mp-itn b a"

# Extract specific attribute
.build/debug/FetchPage https://example.com "a[href]" --attr href

# Show title with query results
.build/debug/FetchPage https://example.com "h1" --title
```

## Options

- `-t, --title` - Also print page title before results
- `-a, --attr NAME` - Print attribute value instead of text content
- `-h, --help` - Show help message

## Features Demonstrated

- Fetching HTML from URLs with `URLSession`
- Parsing HTML with `JustHTML`
- CSS selector queries with `doc.query()`
- Resolving relative URLs to absolute (like jsoup's `absUrl()`)
- Text extraction with `toText()`

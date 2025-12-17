# extractlinks

Extract all links from an HTML file.

## Usage

```bash
# Extract links from a file
swift run extractlinks page.html

# Extract from stdin
curl -s https://example.com | swift run extractlinks

# Only show URLs (no link text)
swift run extractlinks --urls-only page.html
```

## Output

```bash
$ echo '<a href="https://google.com">Google</a><a href="https://github.com">GitHub</a>' | swift run extractlinks
Google -> https://google.com
GitHub -> https://github.com

$ swift run extractlinks --urls-only page.html
https://google.com
https://github.com
```

## Options

- `-u, --urls-only`: Only print URLs, not link text
- `-h, --help`: Show help message

## APIs Demonstrated

- `JustHTML` - HTML parsing
- `query(_:)` - CSS selector queries (`a[href]`)
- `Node.attrs` - Accessing element attributes
- `Node.text` - Getting text content

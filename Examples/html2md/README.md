# html2md

A minimal HTML to Markdown converter.

## Usage

```bash
# Convert a file
swift run html2md page.html

# Convert from stdin
echo '<p>Hello <strong>World</strong></p>' | swift run html2md

# Convert from URL
curl -s https://example.com | swift run html2md
```

## Output

```bash
$ echo '<h1>Title</h1><p>Text with <a href="https://example.com">link</a>.</p>' | swift run html2md
# Title

Text with [link](https://example.com).
```

## APIs Demonstrated

- `JustHTML` - HTML parsing
- `toMarkdown()` - Markdown conversion

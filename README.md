# swift-justhtml

A dependency-free HTML5 parser for Swift, following the WHATWG HTML parsing specification.

Swift port of [justhtml](https://github.com/EmilStenstrom/justhtml) (Python) and [justjshtml](https://github.com/nicholasdille/justjshtml) (JavaScript).

## Features

- **Full HTML5 Compliance** - Passes all 1,831 html5lib tree construction tests
- **Zero Dependencies** - Pure Swift using only standard library and Foundation
- **Cross-Platform** - macOS, iOS, tvOS, watchOS, visionOS, and Linux
- **CSS Selectors** - Query documents using standard CSS selector syntax
- **Multiple Output Formats** - Serialize to HTML, plain text, or Markdown
- **Streaming API** - Memory-efficient event-based parsing
- **Fragment Parsing** - Parse HTML fragments in specific contexts

## Installation

### Swift Package Manager

Add swift-justhtml to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kylehowells/swift-justhtml.git", from: "0.2.0")
]
```

Then add it to your target's dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["swift-justhtml"]
    )
]
```

### Xcode

1. File > Add Package Dependencies...
2. Enter: `https://github.com/kylehowells/swift-justhtml.git`
3. Select version: 0.2.0 or later

## Usage

### Basic Parsing

```swift
import swift_justhtml

// Parse an HTML document
let doc = try JustHTML("<html><body><p>Hello, World!</p></body></html>")

// Access the document tree
print(doc.root.children)  // [<html>]
```

### CSS Selectors

```swift
// Query with CSS selectors
let paragraphs = try doc.query("p")
let byClass = try doc.query(".intro")
let byId = try doc.query("#header")
let complex = try doc.query("nav > ul > li > a[href]")

// Check if a node matches a selector
let matches = try node.matches(".highlight")
```

### Extracting Content

```swift
// Get plain text
let text = doc.toText()

// Serialize to HTML
let html = doc.toHTML()
let prettyHtml = doc.toHTML(pretty: true, indentSize: 4)

// Convert to Markdown
let markdown = doc.toMarkdown()
```

### Fragment Parsing

```swift
// Parse HTML as if inside a specific element
let ctx = FragmentContext("tbody")
let fragment = try JustHTML("<tr><td>Cell</td></tr>", fragmentContext: ctx)
```

### Streaming API

```swift
// Memory-efficient event-based parsing
for event in HTMLStream("<p>Hello</p>") {
    switch event {
    case .start(let tag, let attrs):
        print("Start: \(tag)")
    case .end(let tag):
        print("End: \(tag)")
    case .text(let content):
        print("Text: \(content)")
    case .comment(let text):
        print("Comment: \(text)")
    case .doctype(let name, let publicId, let systemId):
        print("Doctype: \(name)")
    }
}
```

### Error Handling

```swift
// Strict mode - throws on first parse error
do {
    let doc = try JustHTML("<p>Unclosed", strict: true)
} catch let error as StrictModeError {
    print("Error: \(error.parseError.code)")
}

// Collect errors without throwing
let doc = try JustHTML("<p>Unclosed", collectErrors: true)
for error in doc.errors {
    print("\(error.line):\(error.column): \(error.code)")
}
```

## Performance

swift-justhtml is optimized for performance, matching or exceeding JavaScript implementations:

### Parse Time

| Implementation | Parse Time | Comparison |
|----------------|-----------|------------|
| **Swift** | 97ms | - |
| JavaScript | 99ms | 1.02x slower |
| Python | 398ms | 4.1x slower |

*Benchmark: Parsing 2.5MB of HTML across 5 Wikipedia articles*

See [Benchmarks/BENCHMARK_RESULTS.md](Benchmarks/BENCHMARK_RESULTS.md) for detailed performance comparison.

### Memory Usage

| Implementation | Peak RSS | Comparison |
|----------------|----------|------------|
| **Swift** | 103 MB | - |
| Python | 106 MB | 1.03x more |
| JavaScript | 226 MB | 2.2x more |

*Benchmark: Average peak memory across 6 test files including 20MB synthetic HTML*

See [Benchmarks/MEMORY_RESULTS.md](Benchmarks/MEMORY_RESULTS.md) for detailed memory comparison.

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| macOS | 13.0+ |
| iOS | 16.0+ |
| tvOS | 16.0+ |
| watchOS | 9.0+ |
| visionOS | 1.0+ |
| Linux | Swift 6.0+ |

## Documentation

- [API Documentation](https://kylehowells.github.io/swift-justhtml/documentation/swift_justhtml/)
- [Getting Started Guide](https://kylehowells.github.io/swift-justhtml/documentation/swift_justhtml/gettingstarted)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- Original Python implementation: [justhtml](https://github.com/EmilStenstrom/justhtml) by Emil Stenstr&#246;m
- JavaScript port: [justjshtml](https://github.com/simonw/justjshtml) by Simon Willison
- Test suite: [html5lib-tests](https://github.com/html5lib/html5lib-tests)

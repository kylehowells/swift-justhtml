# Swift-JustHTML

A dependency-free HTML5 parser for Swift, following the WHATWG HTML parsing specification.

Swift port of [justhtml](https://github.com/EmilStenstrom/justhtml) (Python) and [justjshtml](https://github.com/simonw/justjshtml) (JavaScript).

## Features

- **Full HTML5 Compliance** - Passes all 1,798 non-scripted [html5lib-tests](https://github.com/html5lib/html5lib-tests) tree construction tests in the current external fixture suite
- **Zero Dependencies** - Pure Swift using only standard library and Foundation
- **Cross-Platform** - macOS, iOS, tvOS, watchOS, visionOS, and Linux
- **CSS Selectors** - Query documents using standard CSS selector syntax
- **Multiple Output Formats** - Serialize to HTML, plain text, or Markdown
- **Streaming API** - Event-based parsing without building a DOM or full token list
- **Fragment Parsing** - Parse HTML fragments in specific contexts

## Installation

### Swift Package Manager

Add swift-justhtml to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/kylehowells/swift-justhtml.git", from: "0.4.6")
]
```

Then add it to your target's dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["justhtml"]
    )
]
```

### Xcode

1. File > Add Package Dependencies...
2. Enter: `https://github.com/kylehowells/swift-justhtml.git`
3. Select version: 0.4.6 or later

## Usage

### Basic Parsing

```swift
import justhtml

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
// Event-based parsing without building a DOM or full token list.
// The input string is still held in memory.
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

### DoS Protection

swift-justhtml includes configurable limits to protect against denial-of-service attacks from malicious HTML input:

```swift
// Default limits are applied automatically (recommended)
let doc = try JustHTML(untrustedHTML)

// Custom limits for servers with more resources
var limits = ParserLimits()
limits.maxNestingDepth = 2048
let doc = try JustHTML(html, limits: limits)

// Stricter limits for resource-constrained devices
let doc = try JustHTML(html, limits: .strict)

// Disable limits for trusted content only
let doc = try JustHTML(trustedHTML, limits: .unlimited)
```

Default limits:
- `maxEntityNameLength`: 255 characters (prevents memory attacks from `&aaaa...`)
- `maxNestingDepth`: 512 levels (prevents stack overflow from deep nesting)

See the [DoS Protection Guide](https://kylehowells.github.io/swift-justhtml/documentation/justhtml/dosprotection) for details.

## Spec Compliance

swift-justhtml implements the [WHATWG HTML parsing specification](https://html.spec.whatwg.org/multipage/parsing.html) exactly and passes all tests from the official [html5lib-tests](https://github.com/html5lib/html5lib-tests) suite (used by browser vendors), the same as [justhtml](https://github.com/EmilStenstrom/justhtml).

### Test Results

| Test Suite | Passed | Failed |
|------------|--------|--------|
| Tree Construction | 1,798 | 0 |
| Tokenizer | 6,810 | 0 |
| Serializer | 230 | 0 |
| Encoding | 82 | 0 |
| **Total** | **8,920** | **0** |

### Fuzz Testing

The parser has been fuzz tested with millions of randomized and malformed HTML documents to ensure it never crashes or hangs on any input:

- Random data fuzzing with varying document sizes
- Fragment context fuzzing
- Deep nesting stress tests
- Malformed tag and entity sequences

Run the fuzzer: `swift test --filter fuzzTest`

## Performance

swift-justhtml is optimized for performance. In the current checked-in benchmark results it is much faster than Python, slightly faster than JavaScript overall, faster than the unoptimized rust-justhtml POC, and still slower than html5ever.

### Parse Time

| Implementation | Parse Time | Comparison |
|----------------|-----------|------------|
| html5ever (Rust) | 454ms | 2.2x faster than Swift |
| **Swift** | 996ms | - |
| JavaScript | 1188ms | 1.2x slower than Swift |
| rust-justhtml | 1534ms | 1.5x slower than Swift |
| Python | 4614ms | 4.6x slower than Swift |

*Benchmark: Parsing the checked-in benchmark sample set, including a 20MB synthetic file. See `Benchmarks/BENCHMARK_RESULTS.md` for exact repository versions and fixture details.*

The current benchmark report flags one `wikipedia_ww2.html` output mismatch. Swift matches JavaScript there, and html5ever matches Swift/JavaScript at the differing `<hr>` node; Python JustHTML is the divergent output for that void-element case.

See [Benchmarks/BENCHMARK_RESULTS.md](Benchmarks/BENCHMARK_RESULTS.md) for detailed performance comparison.

### Memory Usage

| Implementation | Peak RSS | Comparison |
|----------------|----------|------------|
| html5ever (Rust) | 40.62 MB | 2.21x less than Swift |
| **Swift** | 89.74 MB | - |
| Python | 138.91 MB | 1.55x more |
| rust-justhtml | 143.23 MB | 1.60x more |
| JavaScript | 255.23 MB | 2.84x more |

*Benchmark: Average peak memory across 6 test files including 20MB synthetic HTML*

See [Benchmarks/MEMORY_RESULTS.md](Benchmarks/MEMORY_RESULTS.md) for detailed memory comparison.

### Swift Library Comparison

| Library | html5lib Pass Rate | Crashes/Hangs | Dependencies |
|---------|-------------------|---------------|--------------|
| **swift-justhtml** | 100% (1798/1798) | None | None |
| Kanna | 94.4% (1542/1633) | None | libxml2 |
| SwiftSoup | 87.9% (1436/1633) | Infinite loop on 197 tests | swift-atomics |
| LilHTML | 47.4% (775/1634) | Crashes on 855 tests | libxml2 |

See [notes/comparison.md](notes/comparison.md) for detailed library comparison.

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

- [API Documentation](https://kylehowells.github.io/swift-justhtml/documentation/justhtml/)
- [Getting Started Guide](https://kylehowells.github.io/swift-justhtml/documentation/justhtml/gettingstarted)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- Original Python implementation: [justhtml](https://github.com/EmilStenstrom/justhtml) by Emil Stenstr&#246;m
- JavaScript port: [justjshtml](https://github.com/simonw/justjshtml) by Simon Willison
- Test suite: [html5lib-tests](https://github.com/html5lib/html5lib-tests)

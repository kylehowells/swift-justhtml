# swift-justhtml – API Spec & Roadmap

This package will become a dependency-free Swift port of `justhtml` (the pure-Python HTML5 parser), following the same approach Simon Willison used to create `justjshtml` (the JavaScript port).

The primary success criterion is passing the full `html5lib-tests` suite while providing an idiomatic Swift API suitable for use on Apple platforms, Linux, and anywhere Swift runs.

## Goals

- **Correctness first**: match the WHATWG HTML parsing algorithm closely enough to pass `html5lib-tests` (tokenizer, tree construction, serializer, encoding).
- **Zero runtime dependencies**: pure Swift only (no external packages); use only Swift standard library and minimal Foundation where necessary.
- **Idiomatic Swift API**: leverage Swift's strong typing, enums, protocols, and naming conventions while maintaining conceptual parity with the Python/JS APIs.
- **Cross-platform**: support macOS, iOS, tvOS, watchOS, visionOS, and Linux.
- **Deterministic output for tests**: provide a `toTestFormat()` serializer matching `html5lib-tests` expectations.

## Non-goals (initially)

- Full Web DOM / Web IDL API compatibility.
- Executing scripts; we only implement the **parser's scripting flag** behavior (required by tests).
- Async/await streaming (can be added later).
- Objective-C interoperability annotations (can be added later via `@objc`).

---

## Public API (proposed)

Package name: `JustHTML` (Swift module name)

### Imports

```swift
import JustHTML

// Primary types
let doc = JustHTML("<p class='intro'>Hello</p>")
let nodes = doc.query("p.intro")
print(nodes.first?.toHTML() ?? "")
```

### Module Exports

```swift
// Core parser
public struct JustHTML { ... }

// Errors
public struct ParseError: Error { ... }
public struct StrictModeError: Error { ... }
public struct SelectorError: Error { ... }

// Nodes
public final class Node { ... }
public enum Namespace: String { ... }

// Fragment parsing
public struct FragmentContext { ... }

// Streaming
public struct HTMLStream: Sequence { ... }
public enum StreamEvent { ... }

// Serialization
public func toHTML(_ node: Node, options: HTMLSerializeOptions) -> String
public func toTestFormat(_ node: Node) -> String

// Selectors
public func query(_ node: Node, selector: String) throws -> [Node]
public func matches(_ node: Node, selector: String) throws -> Bool
```

---

## `JustHTML` – Main Parser

The primary entry point, mirroring Python/JS usage.

```swift
public struct JustHTML {
    /// The parsed document root (#document or #document-fragment)
    public let root: Node

    /// Parse errors encountered (empty unless collectErrors or strict mode)
    public let errors: [ParseError]

    /// Detected encoding when parsing from Data (nil for String input)
    public let encoding: String?

    /// Fragment context if parsing a fragment
    public let fragmentContext: FragmentContext?

    /// Initialize with a string
    public init(
        _ html: String,
        fragmentContext: FragmentContext? = nil,
        collectErrors: Bool = false,
        strict: Bool = false,
        scripting: Bool = false,
        iframeSrcdoc: Bool = false
    ) throws

    /// Initialize with raw bytes (auto-detects encoding)
    public init(
        data: Data,
        encoding: String? = nil,  // transport-layer override
        fragmentContext: FragmentContext? = nil,
        collectErrors: Bool = false,
        strict: Bool = false,
        scripting: Bool = false,
        iframeSrcdoc: Bool = false
    ) throws

    // Convenience methods delegating to root
    public func query(_ selector: String) throws -> [Node]
    public func toHTML(pretty: Bool = true, indentSize: Int = 2) -> String
    public func toText(separator: String = " ", strip: Bool = true) -> String
    public func toMarkdown() -> String
}
```

### Strict Mode

When `strict: true`, the initializer throws `StrictModeError` on the first parse error:

```swift
do {
    let doc = try JustHTML("<p>unclosed", strict: true)
} catch let error as StrictModeError {
    print(error.parseError.code)  // e.g., "end-tag-with-trailing-solidus"
}
```

---

## `Node` – DOM Tree

A simple DOM node class compatible with html5lib-tests expectations.

```swift
public final class Node {
    /// Node type/name: "#document", "#document-fragment", "#text", "#comment", "!doctype", or tag name
    public let name: String

    /// Namespace: .html, .svg, .math, or nil for non-elements
    public let namespace: Namespace?

    /// Parent node (weak reference to avoid cycles)
    public weak var parent: Node?

    /// Child nodes (empty for text/comment nodes)
    public private(set) var children: [Node]

    /// Attributes (empty for non-elements)
    public var attrs: [String: String]

    /// Text content for #text/#comment nodes, or Doctype info
    public var data: NodeData?

    /// Template content (for <template> elements only)
    public var templateContent: Node?

    // DOM manipulation
    public func appendChild(_ node: Node)
    public func removeChild(_ node: Node) throws
    public func insertBefore(_ node: Node, reference: Node?) throws
    public func replaceChild(_ newNode: Node, oldNode: Node) throws -> Node
    public func cloneNode(deep: Bool = false) -> Node

    // Traversal helpers
    public var hasChildNodes: Bool { get }
    public var text: String { get }  // Direct text content of this node only

    // Query and serialization
    public func query(_ selector: String) throws -> [Node]
    public func toHTML(pretty: Bool = true, indentSize: Int = 2) -> String
    public func toText(separator: String = " ", strip: Bool = true) -> String
    public func toMarkdown() -> String
}

/// Node data payload (for text, comments, doctypes)
public enum NodeData {
    case text(String)
    case comment(String)
    case doctype(Doctype)
}

/// Doctype information
public struct Doctype {
    public let name: String?
    public let publicId: String?
    public let systemId: String?
    public let forceQuirks: Bool
}
```

### Namespace

```swift
public enum Namespace: String, Sendable {
    case html = "html"
    case svg = "svg"
    case math = "math"
}
```

---

## `FragmentContext` – Fragment Parsing

For parsing HTML fragments in a specific context (e.g., parsing `<tr>` content as if inside a `<tbody>`).

```swift
public struct FragmentContext {
    public let tagName: String
    public let namespace: Namespace?

    public init(_ tagName: String, namespace: Namespace? = nil) {
        self.tagName = tagName
        self.namespace = namespace
    }
}

// Usage
let ctx = FragmentContext("tbody")
let frag = try JustHTML("<tr><td>x</td></tr>", fragmentContext: ctx)
// frag.root.name == "#document-fragment"
```

---

## Streaming API

Memory-efficient event-based parsing without building a full tree.

```swift
public struct HTMLStream: Sequence {
    public init(_ html: String)
    public init(data: Data, encoding: String? = nil)

    public func makeIterator() -> HTMLStreamIterator
}

public struct HTMLStreamIterator: IteratorProtocol {
    public mutating func next() -> StreamEvent?
}

public enum StreamEvent {
    case start(tagName: String, attrs: [String: String])
    case end(tagName: String)
    case text(String)
    case comment(String)
    case doctype(name: String, publicId: String?, systemId: String?)
}

// Usage
for event in HTMLStream("<p>Hello</p>") {
    switch event {
    case .start(let tag, let attrs):
        print("Start: \(tag)")
    case .text(let content):
        print("Text: \(content)")
    // ...
    }
}
```

---

## CSS Selectors

Implements the same selector subset as the Python/JS versions:

- Tag name, `#id`, `.class`, `*`
- Attribute selectors: `[attr]`, `=`, `~=`, `|=`, `^=`, `$=`, `*=`
- Combinators: descendant (space), `>`, `+`, `~`
- Selector groups: `,`
- Pseudo-classes: `:first-child`, `:last-child`, `:only-child`, `:nth-child()`, `:nth-last-child()`, `:first-of-type`, `:last-of-type`, `:only-of-type`, `:nth-of-type()`, `:nth-last-of-type()`, `:empty`, `:root`, `:not()`

```swift
// On Node
let paragraphs = try doc.root.query("p.intro")
let hasClass = try matches(node, selector: ".highlight")

// Standalone functions
public func query(_ node: Node, selector: String) throws -> [Node]
public func matches(_ node: Node, selector: String) throws -> Bool
```

Throws `SelectorError` on invalid selectors.

---

## Error Types

### ParseError

Represents a parse error with location information.

```swift
public struct ParseError: Error, CustomStringConvertible {
    /// Error code (kebab-case, matches html5lib-tests)
    public let code: String

    /// Human-readable message
    public let message: String

    /// Line number (1-based)
    public let line: Int?

    /// Column number (1-based)
    public let column: Int?

    public var description: String {
        if let line = line, let column = column {
            return "(\(line),\(column)): \(code)"
        }
        return code
    }
}
```

### StrictModeError

Thrown when `strict: true` and a parse error is encountered.

```swift
public struct StrictModeError: Error {
    public let parseError: ParseError
}
```

### SelectorError

Thrown on invalid CSS selector syntax.

```swift
public struct SelectorError: Error {
    public let message: String
    public let position: Int?
}
```

---

## Serialization

### toHTML

Pretty-prints HTML (default) or compact output.

```swift
public struct HTMLSerializeOptions {
    public var pretty: Bool = true
    public var indentSize: Int = 2

    public init(pretty: Bool = true, indentSize: Int = 2)
}

public func toHTML(_ node: Node, options: HTMLSerializeOptions = .init()) -> String
```

### toTestFormat

Exact `html5lib-tests` tree format for test verification.

```swift
public func toTestFormat(_ node: Node) -> String
```

Output format matches html5lib-tests expectations:

```
| <html>
|   <head>
|   <body>
|     <p>
|       "Hello"
```

---

## Internal Architecture

Following the Python/JS implementations, the internal modules are:

| Module | Purpose |
|--------|---------|
| `Tokenizer.swift` | HTML5 tokenizer state machine (~80 states) |
| `TreeBuilder.swift` | Tree construction algorithm + insertion modes |
| `TreeBuilderModes.swift` | Individual insertion mode handlers |
| `TreeBuilderUtils.swift` | Helper algorithms (adoption agency, etc.) |
| `Entities.swift` | Named character reference decoding |
| `EntitiesData.swift` | Entity name → codepoint mapping data |
| `Encoding.swift` | BOM sniffing, meta charset detection, decoding |
| `Constants.swift` | Element categories, void elements, etc. |
| `Tokens.swift` | Token types (Tag, Character, Comment, Doctype, EOF) |
| `Node.swift` | DOM node implementation |
| `Serialize.swift` | HTML and test-format serialization |
| `Selector.swift` | CSS selector parser and matcher |
| `Stream.swift` | Streaming event API |
| `Context.swift` | FragmentContext |

### Token Types (Internal)

```swift
enum Token {
    case startTag(name: String, attrs: [String: String], selfClosing: Bool)
    case endTag(name: String)
    case character(Character)
    case comment(String)
    case doctype(Doctype)
    case eof
}
```

### Tokenizer States

The tokenizer implements all ~80 states from the WHATWG HTML spec:

- Data state, RCDATA, RAWTEXT, Script data, PLAINTEXT
- Tag open, End tag open, Tag name
- Before/After attribute name/value
- Self-closing start tag
- Bogus comment, Markup declaration open
- Comment states, DOCTYPE states
- CDATA section states
- Character reference states
- etc.

### Tree Builder Insertion Modes

All insertion modes from the spec:

- Initial, BeforeHtml, BeforeHead, InHead, InHeadNoscript
- AfterHead, InBody, Text, InTable, InTableText
- InCaption, InColumnGroup, InTableBody, InRow, InCell
- InSelect, InSelectInTable, InTemplate, AfterBody
- InFrameset, AfterFrameset, AfterAfterBody, AfterAfterFrameset

---

## Test Infrastructure

### Test Runner

A dedicated test runner that loads html5lib-tests fixtures:

```
Tests/
├── swift-justhtmlTests/
│   ├── TreeConstructionTests.swift    # .dat file tests
│   ├── TokenizerTests.swift           # .test JSON files
│   ├── SerializerTests.swift          # .test JSON files
│   ├── EncodingTests.swift            # .dat encoding tests
│   └── SelectorTests.swift            # Unit tests for CSS selectors
└── Fixtures/
    └── (symlinks to html5lib-tests directories)
```

### Test File Formats

**Tree Construction (.dat):**
```
#data
<p>Hello
#errors
(1,0): expected-doctype-but-got-start-tag
#document
| <html>
|   <head>
|   <body>
|     <p>
|       "Hello"
```

**Tokenizer (.test JSON):**
```json
{
  "tests": [
    {
      "description": "Start tag",
      "input": "<p>",
      "output": [["StartTag", "p", {}]]
    }
  ]
}
```

### Running Tests

```bash
# Run all tests
swift test

# Run specific test file
swift test --filter TreeConstructionTests

# Verbose output
swift test -v
```

---

## Roadmap / Implementation Plan

### Milestone 0 — Repository Scaffold ✓

- [x] Create `Package.swift` with library and test targets
- [ ] Set up `Sources/JustHTML/` module structure mirroring Python/JS:
  - `Encoding.swift`, `Tokens.swift`, `Errors.swift`
  - `Tokenizer.swift`, `TreeBuilder.swift`, `TreeBuilderModes.swift`, `Constants.swift`
  - `Node.swift`, `Serialize.swift`, `Selector.swift`, `Stream.swift`
  - `JustHTML.swift` (public API), `Context.swift`
- [ ] Add test infrastructure under `Tests/`:
  - Set up symlinks to `html5lib-tests` directories
  - Create base test case classes for loading fixtures
- [ ] Create `Scripts/run-tests.swift` for detailed test output (optional)

### Milestone 0.5 — End-to-End Smoke Test

- [ ] Implement minimal end-to-end parsing:
  - `JustHTML("<html><head></head><body><p>Hello</p></body></html>")` returns correct tree
  - `doc.toText()` returns `"Hello"`
  - `doc.errors` is empty for valid input
- [ ] Add `SmokeTests.swift` that verifies the basic example
- [ ] Gate: `swift test --filter SmokeTests` passes

### Milestone 1 — Encoding (html5lib encoding tests)

- [ ] Port `normalizeEncodingLabel()` for encoding name canonicalization
- [ ] Implement BOM sniffing (UTF-8, UTF-16LE, UTF-16BE)
- [ ] Implement `<meta charset>` prescan algorithm
- [ ] Implement fallback rules (windows-1252 default)
- [ ] Support encodings via Foundation's String(data:encoding:) or custom decoders:
  - `utf-8`, `windows-1252`, `iso-8859-*`, `euc-jp`, `utf-16le`, `utf-16be`
- [ ] Gate: `encoding/*.dat` tests pass

### Milestone 2 — Tokenizer (html5lib tokenizer tests)

- [ ] Port tokenizer state machine from Python/JS (~80 states)
- [ ] Implement all state handlers:
  - Data, RCDATA, RAWTEXT, Script data, PLAINTEXT states
  - Tag parsing states
  - Attribute parsing states
  - Comment and DOCTYPE states
  - CDATA section states
  - Character reference states
- [ ] Port entity decoding (named + numeric character references)
- [ ] Implement error emission with accurate `(line, column)` tracking
- [ ] Gate: `tokenizer/*.test` fixtures pass

### Milestone 3 — Tree Builder (tree-construction tests)

- [ ] Port `TreeBuilder` class with all insertion modes
- [ ] Implement core algorithms:
  - Stack of open elements management
  - Active formatting elements list
  - Foster parenting
  - Adoption agency algorithm
  - Reconstruct active formatting elements
- [ ] Implement all insertion modes:
  - Initial through AfterAfterFrameset
  - Foreign content handling (SVG, MathML)
  - Template insertion mode stack
- [ ] Implement fragment parsing via `FragmentContext`
- [ ] Handle scripting flag (`#script-on` / `#script-off` tests)
- [ ] Handle `iframe-srcdoc` directive
- [ ] Implement `toTestFormat()` serialization matching html5lib expectations
- [ ] Gate: `tree-construction/*.dat` passes

### Milestone 4 — Serializer Tests

- [ ] Implement HTML serialization with options (optional tag omission, attribute quoting)
- [ ] Gate: `serializer/*.test` fixtures pass

### Milestone 5 — Public API Polish + Streaming

- [ ] Finalize `JustHTML` wrapper struct (decode → tokenize → build → expose)
- [ ] Implement `HTMLStream` sequence for event-based parsing
- [ ] Add convenience methods (`query`, `toHTML`, `toText`, `toMarkdown`)
- [ ] Gate: API tests + streaming tests pass

### Milestone 6 — Selectors + Markdown

- [ ] Port CSS selector parser from Python/JS
- [ ] Implement all supported selector types
- [ ] Port `toMarkdown()` (pragmatic GFM subset)
- [ ] Gate: Selector unit tests pass

### Milestone 7 — Final Polish & Documentation

- [ ] Run `swiftformat --lint .` and fix coding style and formatting issues
- [ ] Add comprehensive DocC documentation
- [ ] Performance optimization pass
- [ ] Ensure Sendable conformance where appropriate
- [ ] Consider `@objc` annotations for Objective-C interop (optional)
- [ ] Create example projects / playground
- [ ] Set up `swiftformat --lint . --reporter github-actions-log` GitHub Action

### Milestone 8 — Benchmarking & Comparisons

- [ ] Create benchmark suite with representative HTML files of varying sizes
- [ ] Benchmark Swift implementation against pure Python version (justhtml)
- [ ] Benchmark Swift implementation against pure JavaScript version (justjshtml)
- [ ] Verify all implementations produce identical parse results for test HTML files
- [ ] Create performance comparison table showing parsing speed differences
- [ ] Document memory usage comparisons across implementations
- [ ] Gate: All implementations return identical results for benchmark HTML files

### Milestone 9 — Performance Tuning & Enhancement (Optional)

- [ ] Run benchmarks on test suite and sample HTML files to establish baseline
- [ ] Profile parsing hot paths and identify optimization opportunities
- [ ] Attempt Swift micro-optimizations while maintaining 100% test passing
- [ ] Run `swift test --enable-code-coverage` + `llvm-cov report ...` to analyze test coverage
- [ ] Identify uncovered code paths — if tests pass but code isn't covered, it's likely dead code
- [ ] Remove dead/unreachable code to improve performance and reduce complexity
- [ ] Gate: 100% test passing maintained, measurable performance improvement

> **Note**: This mirrors the original justhtml author's experience: "I ran coverage on the codebase and found that large parts of the code were 'untested'. But this was backwards, because I already knew that the tests were covering everything important. So lines with no test coverage could be removed! I told the agent to start removing code to reach 100% test coverage, which was an interesting reversal of roles. These removals actually sped up the code as much as the microoptimizations."

### Milestone 10 — Fuzz Testing & Hardening (Optional)

- [ ] Write an HTML5 fuzzer that generates edge-case HTML to stress-test the parser
- [ ] Run fuzzer against parser to identify crashes or unexpected behavior
- [ ] For each breaking case: fix the bug and add a regression test to the test suite
- [ ] Target: pass millions of generated HTML documents without crashes
- [ ] Gate: Parser handles all fuzzed inputs gracefully, test suite expanded with new edge cases

> **Note**: This mirrors the original author's approach: "After removing code, I got worried that I had removed too much and missed corner cases. So I asked the agent to write a html5 fuzzer that tried really hard to generate HTML that broke the parser. It did break the parser, and for each breaking case I asked it to fix it, and write a new test for the test suite. Passed 3 million generated webpages without any crashes, and hardened the codebase again."

---

## Development Approach

Following Simon Willison's blog post approach:

1. **Test-Driven**: Run the html5lib-tests suite continuously as the implementation progresses
2. **Incremental**: Start with smoke tests, then encoding, tokenizer, tree builder
3. **Reference Implementation**: Use Python and JS versions as authoritative references
4. **Commit Often**: Make frequent commits as tests pass to track progress
5. **Fix Forward**: When tests fail, analyze the expected output and fix the implementation

### Test Progress Tracking

Track progress with a summary format similar to the Python version:

```
tree-construction/tests1.dat: 93/112 (83%) [....x..x....]
tree-construction/tests2.dat: 45/45 (100%) [.............]
tokenizer/test1.test: 100/100 (100%) [.............]

PASSED: 1750/1782 passed (98.2%), 12 skipped
```

---

## Platform Support

| Platform | Minimum Version |
|----------|-----------------|
| macOS | 13.0+ |
| iOS | 16.0+ |
| tvOS | 16.0+ |
| watchOS | 9.0+ |
| visionOS | 1.0+ |
| Linux | Swift 5.9+ |

---

## Open Questions

1. **Foundation dependency**: Use Foundation for `Data`, `String.Encoding`, or implement pure-Swift alternatives?
   - *Recommendation*: Use Foundation minimally (Data for byte input), pure Swift for parsing logic

2. **Class vs Struct for Node**: Classes allow parent weak references and identity; structs are value types.
   - *Recommendation*: Use `final class` for Node (matches DOM semantics, allows parent references)

3. **Concurrency**: Should Node be `Sendable`? Should parsing be async?
   - *Recommendation*: Make immutable parts Sendable, defer async to later milestone

4. **Error handling**: Use throwing init vs Result type?
   - *Recommendation*: Throwing init for strict mode, non-throwing for normal mode (errors in array)

5. **String vs Substring optimization**: Use Substring internally for zero-copy slicing?
   - *Recommendation*: Start with String, optimize with Substring if profiling shows benefit

---

## References

- [WHATWG HTML Standard - Parsing](https://html.spec.whatwg.org/multipage/parsing.html)
- [html5lib-tests](https://github.com/html5lib/html5lib-tests)
- [justhtml (Python)](https://github.com/EmilStenstrom/justhtml)
- [justjshtml (JavaScript)](https://github.com/simonw/justjshtml)
- [Simon Willison's blog post on porting justhtml to JavaScript](https://simonwillison.net/2025/Dec/15/porting-justhtml/)
- [Idiosyncrasies of the HTML parser](https://htmlparser.info/)

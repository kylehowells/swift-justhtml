# JustHTML Architecture

This document explains how the swift-justhtml parser works, from the public API down to the implementation details.

## Table of Contents

1. [Public API](#public-api)
2. [Key Concepts](#key-concepts)
3. [Parsing Pipeline](#parsing-pipeline)
4. [Tokenizer](#tokenizer)
5. [Tree Builder](#tree-builder)
6. [DOM Nodes](#dom-nodes)
7. [Additional Features](#additional-features)

---

## Public API

### Entry Point: `JustHTML`

The main entry point is the `JustHTML` struct with two initializers:

```swift
// Parse from string
let doc = try JustHTML("<html><body>Hello</body></html>")

// Parse from raw bytes (auto-detects encoding)
let doc = try JustHTML(data: htmlData)
```

### Constructor Options

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `fragmentContext` | `FragmentContext?` | `nil` | Parse as fragment in specific context (e.g., `"tbody"`) |
| `collectErrors` | `Bool` | `false` | Collect parse errors without throwing |
| `strict` | `Bool` | `false` | Throw on first parse error |
| `scripting` | `Bool` | `false` | Enable JavaScript scripting mode |
| `iframeSrcdoc` | `Bool` | `false` | Parse iframe srcdoc content |
| `xmlCoercion` | `Bool` | `false` | Coerce output for XML compatibility |

### Public Properties

```swift
doc.root       // Node - The parsed document root (#document or #document-fragment)
doc.errors     // [ParseError] - Collection of parse errors (if collectErrors: true)
doc.encoding   // String? - Detected encoding (only for Data input)
```

### Convenience Methods

```swift
// Serialize back to HTML
doc.toHTML(pretty: true, indentSize: 2)

// Extract plain text
doc.toText(separator: " ", strip: true, collapseWhitespace: true)

// Query with CSS selectors
let divs = try doc.query("div.container > p")

// Convert to Markdown
doc.toMarkdown()

// Serialize to html5lib test format (for testing)
doc.toTestFormat()
```

---

## Key Concepts

### 1. Document vs Fragment

- **Document parsing**: Creates a full document with `#document` root, `<html>`, `<head>`, and `<body>` elements (even if missing from input)
- **Fragment parsing**: Parses HTML as if it were inside a specific element context, returns `#document-fragment` root

```swift
// Full document
let doc = try JustHTML("<p>Hello</p>")
// Result: #document → html → head + body → p → "Hello"

// Fragment in <body> context
let frag = try JustHTML("<p>Hello</p>", fragmentContext: FragmentContext("body"))
// Result: #document-fragment → p → "Hello"
```

### 2. Error Handling

The parser follows HTML5 error recovery rules by default. Errors are handled in three modes:

| Mode | Behavior |
|------|----------|
| Default | Silently recover from errors (HTML5 spec behavior) |
| `collectErrors: true` | Gather errors in `doc.errors` array |
| `strict: true` | Throw `StrictModeError` on first error |

### 3. Encoding Detection

When parsing from `Data`, the parser auto-detects encoding by:
1. Checking for BOM (UTF-8, UTF-16, UTF-32)
2. Scanning for `<meta charset="...">` declaration
3. Falling back to UTF-8

---

## Parsing Pipeline

The parsing process flows through two main stages:

```
┌─────────────────────────────────────────────────────────────────┐
│                         JustHTML.init()                         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     1. TOKENIZATION                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │ HTML String │ -> │  Tokenizer  │ -> │ Token Stream        │  │
│  │             │    │ (60+ states)│    │ (startTag, endTag,  │  │
│  │             │    │             │    │  text, comment...)  │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   2. TREE CONSTRUCTION                          │
│  ┌─────────────────┐    ┌─────────────┐    ┌────────────────┐   │
│  │ Token Stream    │ -> │ TreeBuilder │ -> │ DOM Node Tree  │   │
│  │                 │    │ (19 modes)  │    │                │   │
│  └─────────────────┘    └─────────────┘    └────────────────┘   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      3. RESULT                                  │
│                                                                 │
│    JustHTML { root: Node, errors: [ParseError] }                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step Flow

1. **Input**: HTML string (or Data converted to string via encoding detection)

2. **Create Components**:
   ```swift
   let treeBuilder = TreeBuilder(...)      // Implements TokenSink protocol
   let tokenizer = Tokenizer(treeBuilder)  // Emits tokens to TreeBuilder
   ```

3. **Run Tokenizer**: `tokenizer.run(html)`
   - Preprocesses line endings (CR/CRLF → LF)
   - Converts string to UTF-8 bytes for fast processing
   - State machine processes each character
   - Emits tokens to TreeBuilder via `processToken()`

4. **Finish**: `treeBuilder.finish()`
   - Final cleanup and validation
   - Returns the root document node

---

## Tokenizer

The tokenizer (`Tokenizer.swift`, ~3,500 lines) implements the HTML5 tokenization state machine.

### State Machine

The tokenizer has 60+ states. Key states include:

| State | Description |
|-------|-------------|
| `.data` | Normal text content |
| `.tagOpen` | Just saw `<` |
| `.tagName` | Reading tag name |
| `.beforeAttributeName` | Before attribute |
| `.attributeName` | Reading attribute name |
| `.attributeValue*` | Reading attribute value |
| `.rawtext` | Inside `<style>`, `<xmp>`, etc. |
| `.rcdata` | Inside `<title>`, `<textarea>` |
| `.scriptData*` | Inside `<script>` (special handling) |
| `.characterReference` | Parsing `&entities;` |
| `.comment*` | Inside `<!-- comments -->` |
| `.doctype*` | Parsing `<!DOCTYPE>` |

### Token Types

```swift
enum Token {
    case startTag(name: String, attrs: [String: String], selfClosing: Bool)
    case endTag(name: String)
    case character(Character)  // Individual characters (batched in practice)
    case comment(String)
    case doctype(Doctype)
    case eof
}
```

### Processing Loop

```
┌──────────────────────────────────────────────────────┐
│                  Tokenizer Loop                      │
│                                                      │
│   for each byte in input:                            │
│       1. Look at current state                       │
│       2. Look at current character                   │
│       3. Transition to new state                     │
│       4. Maybe emit token(s)                         │
│       5. Maybe emit error(s)                         │
│                                                      │
└──────────────────────────────────────────────────────┘
```

### Example: Tokenizing `<div class="foo">Hello</div>`

```
State: .data
  '<' → transition to .tagOpen

State: .tagOpen
  'd' → transition to .tagName, start building "d"

State: .tagName
  'i' → append to name: "di"
  'v' → append to name: "div"
  ' ' → transition to .beforeAttributeName

State: .beforeAttributeName
  'c' → transition to .attributeName, start "c"

State: .attributeName
  'l','a','s','s' → build "class"
  '=' → transition to .beforeAttributeValue

State: .beforeAttributeValue
  '"' → transition to .attributeValueDoubleQuoted

State: .attributeValueDoubleQuoted
  'f','o','o' → build value "foo"
  '"' → transition to .afterAttributeValueQuoted

State: .afterAttributeValueQuoted
  '>' → EMIT startTag("div", {"class": "foo"}, selfClosing: false)
      → transition to .data

State: .data
  'H','e','l','l','o' → EMIT character tokens
  '<' → transition to .tagOpen

State: .tagOpen
  '/' → transition to .endTagOpen

State: .endTagOpen
  'd','i','v' → build end tag name

  '>' → EMIT endTag("div")
      → transition to .data
```

---

## Tree Builder

The tree builder (`TreeBuilder.swift`, ~4,000 lines) implements the HTML5 tree construction algorithm.

### TokenSink Protocol

```swift
protocol TokenSink {
    func processToken(_ token: Token)
    var currentNamespace: Namespace? { get }
}
```

The TreeBuilder receives tokens from the Tokenizer via this protocol.

### Insertion Modes

The tree builder uses 19 insertion modes that determine how tokens are processed:

```
.initial
    ↓
.beforeHtml
    ↓
.beforeHead
    ↓
.inHead ←→ .inHeadNoscript
    ↓
.afterHead
    ↓
.inBody (main mode) ←→ .text
    ↓                   ↓
.afterBody          .inTable → .inCaption
    ↓                        → .inColumnGroup
.afterAfterBody              → .inTableBody → .inRow → .inCell
                             → .inSelect → .inSelectInTable
                             → .inTemplate
```

### Key Data Structures

```swift
class TreeBuilder {
    var document: Node              // Root #document node
    var openElements: [Node]        // Stack of open elements
    var activeFormattingElements: [Node?]  // For <b>, <i>, etc. (nil = marker)
    var insertionMode: InsertionMode

    var headElement: Node?          // Reference to <head>
    var bodyElement: Node?          // Reference to <body>
    var formElement: Node?          // Current <form> for implicit association

    var templateInsertionModes: [InsertionMode]  // Stack for <template>
}
```

### The Open Elements Stack

The open elements stack tracks elements that haven't been closed yet:

```html
<html><body><div><p>Hello
```

Open elements stack: `[html, body, div, p]`

When we see `</p>`:
1. Pop `p` from stack
2. Stack becomes: `[html, body, div]`

### Active Formatting Elements

For inline formatting elements like `<b>`, `<i>`, `<a>`, the spec requires special handling to reconstruct formatting across block boundaries:

```html
<p><b>Bold <p>Still bold</p>
```

The `<b>` must be reconstructed in the second `<p>`. The active formatting elements list tracks these.

### Token Processing

```swift
func processToken(_ token: Token) {
    switch token {
    case .character(let ch):
        processCharacter(ch)
    case .startTag(let name, let attrs, let selfClosing):
        processStartTag(name, attrs, selfClosing)
    case .endTag(let name):
        processEndTag(name)
    case .comment(let text):
        processComment(text)
    case .doctype(let doctype):
        processDoctype(doctype)
    case .eof:
        processEOF()
    }
}
```

Each token type is handled differently based on the current insertion mode.

### Example: Building Tree for `<div><p>Hello</p></div>`

```
Token: startTag("div")
  Mode: .inBody
  Action: Create <div> node, append to current position, push to openElements
  Stack: [html, body, div]

Token: startTag("p")
  Mode: .inBody
  Action: Create <p> node, append to <div>, push to stack
  Stack: [html, body, div, p]

Token: character("H"), character("e"), ...
  Mode: .inBody
  Action: Create text node "Hello", append to <p>

Token: endTag("p")
  Mode: .inBody
  Action: Pop <p> from stack
  Stack: [html, body, div]

Token: endTag("div")
  Mode: .inBody
  Action: Pop <div> from stack
  Stack: [html, body]
```

### Scope Checking

Many tree construction rules require checking if an element is "in scope". The parser maintains fast lookup sets for scope boundaries:

```swift
let SCOPE_ELEMENTS: Set<String> = [
    "applet", "caption", "html", "table", "td", "th",
    "marquee", "object", "template",
    // MathML: "mi", "mo", "mn", "ms", "mtext", "annotation-xml"
    // SVG: "foreignObject", "desc", "title"
]
```

Example: `hasElementInScope("p")` walks up the open elements stack until it finds either `<p>` (return true) or a scope boundary element (return false).

---

## DOM Nodes

### Node Class

```swift
public final class Node {
    // Identity
    public let name: String           // "#document", "div", "#text", etc.
    public let tagId: TagID           // Fast integer comparison
    public let namespace: Namespace?  // .html, .svg, .mathml, or nil

    // Tree structure
    public weak var parent: Node?     // Weak to prevent cycles
    public private(set) var children: [Node]

    // Content
    public var attrs: [String: String]  // Element attributes
    public var data: NodeData?          // For text/comment/doctype
    public var templateContent: Node?   // For <template> elements
}
```

### Node Types

| Name | Description |
|------|-------------|
| `#document` | Root of a full document |
| `#document-fragment` | Root of a fragment |
| `#text` | Text content |
| `#comment` | Comment node |
| Element names (`div`, `p`, etc.) | Element nodes |

### TagID

For performance, common tags have integer IDs for fast comparison:

```swift
enum TagID: UInt16 {
    case document = 0
    case text = 1
    case comment = 2
    // ...
    case div = 10
    case span = 11
    case p = 12
    // ... 200+ tags
}
```

### DOM Manipulation

```swift
node.appendChild(child)
node.insertBefore(newNode, reference: existingChild)
node.removeChild(child)
node.replaceChild(newNode, oldNode: existingChild)
node.cloneNode(deep: true)
```

---

## Additional Features

### CSS Selectors

```swift
// Query from document
let nodes = try doc.query("div.container > p.intro")

// Check if node matches
let matches = try matches(node, selector: "p.intro")
```

Supported selectors:
- Type: `div`, `p`, `*`
- ID: `#myId`
- Class: `.myClass`
- Attribute: `[href]`, `[href="value"]`, `[href^="prefix"]`
- Pseudo-classes: `:first-child`, `:last-child`, `:nth-child(n)`
- Combinators: `A B` (descendant), `A > B` (child), `A + B` (adjacent), `A ~ B` (sibling)

### Serialization

```swift
// HTML output
node.toHTML()                        // Compact
node.toHTML(pretty: true)            // Formatted with newlines
node.toHTML(pretty: true, indentSize: 4)

// Plain text extraction
node.toText()                        // All text content
node.toText(collapseWhitespace: true)  // Normalize whitespace

// Markdown conversion
node.toMarkdown()                    // GitHub-Flavored Markdown

// Test format (for html5lib-tests)
node.toTestFormat()
```

### Streaming API

For memory-efficient processing without building a DOM:

```swift
let stream = HTMLStream("<p>Hello</p><p>World</p>")

for event in stream {
    switch event {
    case .start(let tagName, let attrs):
        print("Open: \(tagName)")
    case .end(let tagName):
        print("Close: \(tagName)")
    case .text(let content):
        print("Text: \(content)")
    case .comment(let content):
        print("Comment: \(content)")
    case .doctype(let name, _, _):
        print("DOCTYPE: \(name ?? "")")
    }
}
```

Note: The current implementation tokenizes the full document on init. The streaming interface is for iteration convenience, not true incremental parsing.

---

## File Summary

| File | Lines | Purpose |
|------|-------|---------|
| `TreeBuilder.swift` | ~4,000 | Tree construction state machine |
| `Tokenizer.swift` | ~3,500 | Tokenization state machine |
| `EntitiesData.swift` | ~2,100 | HTML entity reference data |
| `Selector.swift` | ~900 | CSS selector parsing and matching |
| `Serialize.swift` | ~600 | HTML/Markdown/test format output |
| `Node.swift` | ~550 | DOM node representation |
| `Encoding.swift` | ~500 | Encoding detection and decoding |
| `Entities.swift` | ~350 | Entity decoding logic |
| `Constants.swift` | ~230 | Tag sets and constants |
| `JustHTML.swift` | ~200 | Public API entry point |
| `HTMLStream.swift` | ~140 | Event-based streaming interface |
| `Tokens.swift` | ~80 | Token and error types |
| **Total** | **~13,000** | |

---

## References

- [WHATWG HTML Living Standard - Parsing](https://html.spec.whatwg.org/multipage/parsing.html)
- [html5lib-tests](https://github.com/html5lib/html5lib-tests) - Conformance test suite

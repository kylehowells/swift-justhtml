# Swift JustHTML Performance Optimization History

**Final Result:** 302ms → 98ms (**3.1x faster**, 67% reduction)

This document details all performance optimizations made to the Swift JustHTML parser on the `turbo` branch, achieving performance parity with JavaScript (parse5).

---

## Summary

| Milestone | Total Time | Speedup | Cumulative |
|-----------|-----------|---------|------------|
| Baseline | 302ms | — | 1.0x |
| UTF-8 Byte Tokenizer | 261ms | 1.16x | 1.16x |
| Batch Text Insertion | 182ms | 1.43x | 1.66x |
| Static Set Lookups | 172ms | 1.06x | 1.76x |
| Batch Text Scanning | 159ms | 1.08x | 1.90x |
| Batch Tag/Attr Scanning | 118ms | 1.35x | 2.56x |
| Inline Arrays → Sets | 98ms | 1.20x | **3.08x** |

**Comparison to other implementations:**
| Implementation | Total Time | vs Swift |
|----------------|-----------|----------|
| **Swift** | **98ms** | — |
| **JavaScript (parse5)** | **98ms** | 1.0x |
| Python (html5lib) | 398ms | 4.1x slower |

---

## Optimization 1: UTF-8 Byte-Based Tokenizer

**Commit:** `887bea9`
**Impact:** 302ms → 261ms (**14% faster**)

### Problem
The original tokenizer used Swift's `String.Index` for character iteration, which requires O(n) random access due to Unicode grapheme cluster handling.

### Solution
Converted the tokenizer input from `String` to `ContiguousArray<UInt8>` for direct byte-level access:
- Changed `BufferedInput` to work with raw UTF-8 bytes
- Implemented ASCII fast-path for common characters
- Added byte-based lookahead for tag detection

### Technical Details
Profiling showed that `String.Index` advancement was **6x slower** than byte iteration:
```
UTF-8 byte iteration:     0.79 ms/pass
String.Index advancement: 4.76 ms/pass (6.0x slower)
Character iteration:      8.19 ms/pass (10.4x slower)
```

### Files Changed
- `Sources/swift-justhtml/Tokenizer.swift`
- `Sources/swift-justhtml/BufferedInput.swift`

---

## Optimization 2: Batch Text Insertion

**Commit:** `c61748d`
**Impact:** 261ms → 182ms (**30% faster**)

### Problem
The tree builder was creating a new text node for every character token emitted by the tokenizer, resulting in excessive node allocations and tree manipulations.

### Solution
Added `insertText()` method to TreeBuilder that:
- Coalesces consecutive character tokens before insertion
- Appends to existing text nodes when possible
- Only creates new text nodes when necessary

### Technical Details
For a document with 15,000 text nodes, this reduced the number of `appendChild` calls by ~80% for text content.

### Files Changed
- `Sources/swift-justhtml/TreeBuilder.swift`

---

## Optimization 3: Static Set Constants for Tag Lookups

**Commits:** `2719d8a`, `3207f3a`
**Impact:** 182ms → 172ms (**6% faster**)

### Problem
Tag name lookups used inline array literals (`["td", "th", "tr"].contains(name)`), creating temporary arrays on every call.

### Solution
Defined module-level `Set<String>` constants for all tag name groups:
```swift
private let kTableCellTags: Set<String> = ["td", "th"]
private let kTableRowTags: Set<String> = ["tbody", "tfoot", "thead", "tr"]
private let kHeadingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
// ... 20+ more sets
```

### Technical Details
- Set lookup: O(1) average case
- Array literal lookup: O(n) + allocation overhead
- Sets are initialized once at module load time

### Files Changed
- `Sources/swift-justhtml/TreeBuilder.swift`
- `Sources/swift-justhtml/Constants.swift`

---

## Optimization 4: TagID Integer Comparisons

**Commits:** `23cd290`, `306bc8c`, `711d8a3`, `e339f3e`
**Impact:** Minimal direct impact, but enabled future optimizations

### Problem
String comparisons for tag names, even with Swift's small-string optimization, have overhead from length checks and byte comparisons.

### Solution
Created `TagID` enum with `UInt8` raw values for all 120+ HTML tag names:
```swift
public enum TagID: UInt8 {
    case unknown = 0
    case a = 1
    case abbr = 2
    case address = 3
    // ... 120+ cases
}
```

Added `TagID.from(_ name: String) -> TagID` for conversion and used TagID in scope checking functions.

### Technical Details
Profiling showed TagID comparisons are ~4x faster than string equality:
```
String equality (5 comparisons): 8.4 ns/op
TagID equality (5 comparisons):  2.2 ns/op
```

However, the conversion overhead and Swift's string optimizations meant the net impact was minimal until combined with other optimizations.

### Files Changed
- `Sources/swift-justhtml/Node.swift` (TagID enum)
- `Sources/swift-justhtml/TreeBuilder.swift`

---

## Optimization 5: Batch Text Scanning

**Commit:** `80d20f6`
**Impact:** 172ms → 159ms (**8% faster**)

### Problem
The tokenizer processed text content character-by-character, calling `processToken(.character(...))` for each character or short sequence.

### Solution
Implemented batch scanning that finds the next significant character (`<`, `&`, or null) and emits the entire text run at once:
```swift
// Before: emit each character separately
// After: scan ahead and emit "This is some text" as one token
```

### Technical Details
For a 1.2MB file with ~500KB of text content, this reduced token emissions from ~500,000 character tokens to ~15,000 text tokens.

### Files Changed
- `Sources/swift-justhtml/Tokenizer.swift`

---

## Optimization 6: Batch Tag Name and Attribute Scanning

**Commit:** `717c19b`
**Impact:** 159ms → 118ms (**26% faster**)

### Problem
Tag names and attribute names were being built character-by-character using string concatenation.

### Solution
Implemented batch scanning for tag names and attributes:
- Scan ahead to find the end of the name (non-alphanumeric character)
- Extract the entire name in one operation
- Use `String(bytes:encoding:)` for efficient UTF-8 to String conversion

### Technical Details
```swift
// Before: build name character by character
tagName.append(char)

// After: scan and extract in one operation
let nameEnd = findNameEnd(from: position)
let tagName = String(bytes: buffer[position..<nameEnd], encoding: .utf8)
```

This optimization had the largest single impact because tag/attribute parsing is the hottest path in the tokenizer.

### Files Changed
- `Sources/swift-justhtml/Tokenizer.swift`

---

## Optimization 7: Inline Array Literals to Module-Level Sets

**Commit:** `330c68d`
**Impact:** 118ms → 98ms (**17% faster**)

### Problem
Profiling revealed 7 remaining inline array literals in `processStartTagInBody` that were being created on every tag and searched linearly:

```swift
// This creates an array and does O(n) search on EVERY tag
else if [
    "address", "article", "aside", "blockquote", "center", ...
].contains(name) {
```

For a "span" tag (most common), the code would:
1. Create and search a 10-element array (head tags)
2. Create and search a 26-element array (block tags)
3. Create and search an 11-element array (table tags)
4. ... and more

### Solution
Created 5 new module-level Set constants:
```swift
private let kHeadProcessingTags: Set<String> = [
    "base", "basefont", "bgsound", "link", "meta",
    "noframes", "script", "style", "template", "title",
]

private let kBlockStructureTags: Set<String> = [
    "address", "article", "aside", "blockquote", "center",
    "details", "dialog", "dir", "div", "dl", "fieldset",
    "figcaption", "figure", "footer", "header", "hgroup",
    "main", "menu", "nav", "ol", "p", "search", "section",
    "summary", "ul",
]

private let kIgnoredTableStartTags: Set<String> = [...]
private let kIgnoredTableEndTags: Set<String> = [...]
private let kBlockStructureEndTags: Set<String> = [...]
```

### Technical Details
Tree builder time breakdown:
- **Before:** 34ms (62% of parse time)
- **After:** 21ms (50% of parse time)
- **Improvement:** 39% faster tree builder

This optimization closed the remaining gap with JavaScript.

### Files Changed
- `Sources/swift-justhtml/TreeBuilder.swift`

---

## Optimizations That Did NOT Help

### Pre-computing TagID in Token Enum
**Attempted but reverted**

Tried adding `tagId` field to `Token.startTag` and `Token.endTag` cases to avoid repeated `TagID.from(name)` calls in the tree builder.

**Result:** 117ms → 120ms (3% slower)

**Why it failed:** The overhead of computing TagID in the tokenizer and the increased Token enum size outweighed the savings in the tree builder.

### Replacing Set<String> with Set<TagID>
**Attempted but minimal impact**

Converted scope checking to use `Set<TagID>` instead of `Set<String>`.

**Result:** Negligible improvement

**Why:** Swift's `Set<String>` is already highly optimized with hash caching for small strings.

---

## Performance Characteristics

### Final Throughput
| File | Size | Time | Throughput |
|------|------|------|------------|
| hackernews.html | 34 KB | 2.10ms | 16 MB/s |
| wikipedia_countries.html | 360 KB | 14.65ms | 25 MB/s |
| wikipedia_html.html | 472 KB | 19.21ms | 25 MB/s |
| wikipedia_swift.html | 411 KB | 17.47ms | 24 MB/s |
| wikipedia_ww2.html | 1,204 KB | 44.34ms | 28 MB/s |

### Component Breakdown (wikipedia_ww2.html)
| Component | Time | Percentage |
|-----------|------|------------|
| Tokenizer | 20.5ms | 50% |
| Tree Builder | 20.7ms | 50% |

### Scaling
The parser exhibits linear O(n) scaling with input size. Time per KB is consistent (~0.04ms/KB) across all file sizes.

---

## Profiling Methodology

All benchmarks were run with:
- **Build:** Release mode (`swift build -c release`)
- **Iterations:** 10-50 depending on file size
- **Warmup:** 2 iterations discarded
- **Environment:** Linux x86_64, Swift 6.2

Profiling tests are in `Tests/swift-justhtmlTests/ProfilingTests.swift`.

---

## Conclusion

The Swift JustHTML parser achieved a **3.1x speedup** through systematic profiling and targeted optimizations:

1. **Byte-level tokenization** eliminated Unicode overhead
2. **Batch processing** reduced function call overhead
3. **Static Sets** eliminated temporary allocations
4. **Hot path optimization** focused effort where it mattered most

The result is a Swift HTML5 parser that matches JavaScript (parse5) performance while being 4x faster than Python (html5lib).

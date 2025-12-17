# Swift JustHTML Performance Profile

**Generated:** 2025-12-17
**Version:** turbo branch (commit 195a0c4)
**Total Benchmark Time:** 98ms (all test files)
**Primary Test File:** wikipedia_ww2.html (1,204 KB)

---

## Executive Summary

The 98ms total parse time for all benchmark files breaks down as follows:

| Component | Time | Percentage |
|-----------|------|------------|
| **Tokenizer** | ~44ms | ~45% |
| **Tree Builder** | ~54ms | ~55% |

The **largest optimization opportunities** are:

1. **Tree Builder "Other Overhead"** (41.7% of total) - Mode switching, scope checking, implied end tags, active formatting elements
2. **Tokenizer Tag Parsing** (26% of total) - State machine transitions for tag/attribute parsing
3. **Entity Decoding** (~5-10% of total) - Dictionary lookups and string building

---

## 1. High-Level Breakdown

### Per-File Performance

| File | Size | Time | Tokenizer | Tree Builder | Throughput |
|------|------|------|-----------|--------------|------------|
| hackernews.html | 34 KB | 2.14ms | 48.5% | 51.5% | 15.4 MB/s |
| wikipedia_countries.html | 360 KB | 14.54ms | 44.4% | 55.6% | 24.8 MB/s |
| wikipedia_html.html | 472 KB | 18.30ms | 46.4% | 53.6% | 25.8 MB/s |
| wikipedia_swift.html | 411 KB | 16.39ms | 46.1% | 53.9% | 25.0 MB/s |
| wikipedia_ww2.html | 1,204 KB | 41.31ms | 48.6% | 51.4% | 29.1 MB/s |

**Observation:** Throughput improves with larger files (better cache utilization), ranging from 15-29 MB/s.

### Component Split

The tokenizer and tree builder each consume roughly half the parse time:

```
Tokenizer:     ~47% of total parse time
Tree Builder:  ~53% of total parse time
```

---

## 2. Tokenizer Analysis

### Throughput by Content Type

| Content Type | Throughput | vs Pure Text |
|--------------|------------|--------------|
| **Pure text** | 650 MB/s | 1.0x (baseline) |
| Attribute-heavy | 53.5 MB/s | 12.1x slower |
| Tag-heavy | 30.0 MB/s | 21.7x slower |
| Comment-heavy | 28.6 MB/s | 22.7x slower |
| **Entity-heavy** | 25.4 MB/s | **25.6x slower** |

### Key Findings

1. **Pure text processing is extremely fast** (650 MB/s) - the byte-based scanning is highly optimized
2. **Tag parsing is 21.7x slower** than pure text due to state machine transitions
3. **Entity decoding is the slowest operation** (25.6x overhead) due to dictionary lookups

### Tokenizer Time Breakdown (wikipedia_ww2.html)

| Operation | Estimated Time | % of Tokenizer |
|-----------|---------------|----------------|
| Tag name scanning | ~8ms | 38% |
| Attribute parsing | ~5ms | 24% |
| Entity decoding | ~4ms | 19% |
| State machine overhead | ~2ms | 10% |
| Text scanning | ~2ms | 9% |

### Hot Paths in Tokenizer

**File:** `Sources/swift-justhtml/Tokenizer.swift`

1. **`run()` main loop** (line ~180) - The main tokenization loop that dispatches to state handlers
2. **`consumeTagName()`** - Scans tag names character by character
3. **`consumeAttributeName()` / `consumeAttributeValue()`** - Attribute parsing
4. **`consumeCharacterReference()`** - Entity decoding with dictionary lookups
5. **State machine `switch` statement** - Large switch on `State` enum

---

## 3. Tree Builder Analysis

### Operation Costs (wikipedia_ww2.html)

| Operation | Time | % of Tree Builder | % of Total |
|-----------|------|-------------------|------------|
| **Other overhead** | 18.36ms | 79.4% | **41.7%** |
| Tag dispatch | 2.24ms | 9.7% | 5.1% |
| Node creation | 1.31ms | 5.7% | 3.0% |
| appendChild | 1.22ms | 5.3% | 2.8% |

### What is "Other Overhead"?

The 18.36ms "other overhead" includes:

1. **Insertion mode switching** - Large switch statements in `processToken()`, `processStartTag()`, `processEndTag()`
2. **Scope checking** - `hasElementInScope()`, `hasElementInButtonScope()`, `hasElementInTableScope()`, etc.
3. **Implied end tags** - `generateImpliedEndTags()` called frequently
4. **Active formatting elements** - `reconstructActiveFormattingElements()`, adoption agency algorithm
5. **Foster parenting** - Complex logic for misnested table content
6. **Stack operations** - `openElements` array manipulation

### Document Statistics (wikipedia_ww2.html)

| Metric | Value |
|--------|-------|
| Element nodes | 15,217 |
| Text nodes | 15,340 |
| Total nodes | 30,557 |
| Attributes | 20,805 |
| Attribute bytes | 726,914 |
| Start tags | 15,217 |
| End tags | 14,671 |

### Per-Operation Costs

| Metric | Cost |
|--------|------|
| Per start tag | 2.9 µs |
| Per end tag | 3.0 µs |
| Per node created | 1.4 µs |
| Per KB of input | 0.04 ms |

### Hot Paths in Tree Builder

**File:** `Sources/swift-justhtml/TreeBuilder.swift`

1. **`processToken()`** (line ~400) - Main token dispatch, called for every token
2. **`processStartTag()`** (line ~756) - Large switch on insertion mode
3. **`processStartTagInBody()`** (line ~1522) - Largest function, handles most tags
4. **`processEndTagInBody()`** (line ~2200) - End tag processing
5. **`hasElementInScope()`** (line ~3138) - Called frequently for scope checking
6. **`reconstructActiveFormattingElements()`** (line ~3303) - Called before most element insertions
7. **`generateImpliedEndTags()`** (line ~3230) - Called for block-level elements

---

## 4. Micro-Benchmark Results

### Node Operations

| Operation | Time |
|-----------|------|
| Node creation | 42.9 ns |
| Node with attributes | 115.0 ns |
| Text node creation | 43.2 ns |
| appendChild | 40.2 ns |
| Stack push/pop | 6.1 ns |

### Tag Dispatch

| Strategy | Time per tag |
|----------|-------------|
| String if/else chain | 74.9 ns |
| TagID if/else chain | 57.7 ns |
| TagID switch (optimized away) | ~0 ns |

---

## 5. Hot Path Analysis Summary

### Ranked by Impact on Total Parse Time

| Rank | Hot Path | % of Total | Location |
|------|----------|------------|----------|
| 1 | **Tree builder mode/scope logic** | 41.7% | TreeBuilder.swift |
| 2 | **Tokenizer tag parsing** | 26.0% | Tokenizer.swift |
| 3 | Tree builder tag dispatch | 5.1% | TreeBuilder.swift |
| 4 | Node allocation + appendChild | 5.8% | Node.swift, TreeBuilder.swift |
| 5 | Entity decoding | ~5% | Tokenizer.swift |

### Code Locations

**Tokenizer Hot Spots:**
- `Tokenizer.swift:180` - Main run loop
- `Tokenizer.swift:~500` - Tag name consumption
- `Tokenizer.swift:~700` - Attribute parsing
- `Tokenizer.swift:~1200` - Character reference handling

**Tree Builder Hot Spots:**
- `TreeBuilder.swift:400` - processToken()
- `TreeBuilder.swift:756` - processStartTag()
- `TreeBuilder.swift:1522` - processStartTagInBody()
- `TreeBuilder.swift:3138` - hasElementInScope()
- `TreeBuilder.swift:3303` - reconstructActiveFormattingElements()

---

## 6. Optimization Suggestions

### High Impact (potentially 10-30% improvement)

#### 1. Optimize Tree Builder Mode Switching
**Current cost:** 41.7% of total parse time
**Approach:** The insertion mode dispatch uses multiple levels of switch statements. Consider:
- Flatten the dispatch hierarchy where possible
- Use computed goto / function pointer tables for mode dispatch
- Inline common mode handlers

**Files:** `TreeBuilder.swift` - `processToken()`, `processStartTag()`, `processEndTag()`

#### 2. Optimize Scope Checking
**Current cost:** Part of 41.7% overhead
**Approach:** Scope checking (`hasElementInScope()`) iterates the open elements stack for every check. Consider:
- Maintain a bitmap of elements in scope, updated on push/pop
- Cache scope check results that don't change
- Use TagID-based scope sets (already partially implemented)

**Files:** `TreeBuilder.swift` - `hasElementInScope()`, `hasElementInButtonScope()`, etc.

#### 3. Reduce Implied End Tag Generation
**Current cost:** Part of 41.7% overhead
**Approach:** `generateImpliedEndTags()` is called frequently and may do unnecessary work. Consider:
- Track whether implied tags are actually needed
- Skip generation when stack is known to be clean
- Batch multiple implied end tags

**Files:** `TreeBuilder.swift` - `generateImpliedEndTags()`

### Medium Impact (potentially 5-15% improvement)

#### 4. Optimize Entity Decoding
**Current cost:** ~5-10% of total parse time
**Approach:** Entity lookup uses a 2,125-entry dictionary. Consider:
- Use a trie structure for prefix matching
- Add fast paths for common entities (&amp;, &lt;, &gt;, &quot;)
- Avoid string allocations during lookup

**Files:** `Tokenizer.swift` - `consumeCharacterReference()`, `Entities.swift`

#### 5. SIMD Tag Name Scanning
**Current cost:** Part of 26% tokenizer overhead
**Approach:** Tag names are scanned byte-by-byte. Consider:
- Use SIMD instructions to scan for non-alphanumeric characters
- Process 16 bytes at a time on x86-64

**Files:** `Tokenizer.swift` - tag name scanning functions

#### 6. Reduce Active Formatting Element Overhead
**Current cost:** Part of 41.7% overhead
**Approach:** `reconstructActiveFormattingElements()` is called before most element insertions. Consider:
- Track a "dirty" flag and skip when nothing needs reconstruction
- Optimize the contains() check on openElements

**Files:** `TreeBuilder.swift` - `reconstructActiveFormattingElements()`

### Lower Impact (potentially 2-5% improvement)

#### 7. Node Allocation Pooling
**Current cost:** 5.8% of total parse time
**Approach:** Each node is allocated individually with ARC overhead. Consider:
- Arena allocator for batch allocation
- Node pooling for reuse
- Struct-based nodes (eliminates ARC but complicates tree structure)

**Files:** `Node.swift`

#### 8. Attribute Storage Optimization
**Current cost:** Part of node creation overhead
**Approach:** Attributes use `[String: String]` dictionary. Consider:
- Small-vector optimization for 1-3 attributes
- Inline storage for common attributes (id, class)

**Files:** `Node.swift`

---

## 7. Comparison to JavaScript (parse5)

Swift and JavaScript (parse5) are now tied at 98ms total. The remaining opportunities to beat JavaScript:

| Area | Swift Status | JavaScript Advantage |
|------|-------------|---------------------|
| Byte scanning | Optimized | None |
| Tag dispatch | Optimized | JIT inlining |
| Node allocation | ARC overhead | GC batching |
| String handling | UTF-8 safe | UTF-16 O(1) access |
| Scope checking | O(n) stack scan | O(n) stack scan |

JavaScript benefits from V8's JIT compilation and deferred garbage collection. Swift's remaining overhead is primarily:
- ARC atomic operations on every node
- UTF-8 string safety checks
- Lack of runtime hot-path optimization

---

## 8. Conclusion

The Swift JustHTML parser spends its time as follows:

```
┌─────────────────────────────────────────────────────────────┐
│                    Total: ~44ms (ww2)                       │
├─────────────────────────────────────────────────────────────┤
│  Tokenizer: ~21ms (47%)                                     │
│  ├── Tag parsing:        ~8ms  (38% of tokenizer)           │
│  ├── Attribute parsing:  ~5ms  (24% of tokenizer)           │
│  ├── Entity decoding:    ~4ms  (19% of tokenizer)           │
│  ├── State machine:      ~2ms  (10% of tokenizer)           │
│  └── Text scanning:      ~2ms  (9% of tokenizer)            │
├─────────────────────────────────────────────────────────────┤
│  Tree Builder: ~23ms (53%)                                  │
│  ├── Mode/scope logic:   ~18ms (79% of tree builder) ◄──┐   │
│  ├── Tag dispatch:       ~2ms  (10% of tree builder)    │   │
│  ├── Node creation:      ~1ms  (6% of tree builder)     │   │
│  └── appendChild:        ~1ms  (5% of tree builder)     │   │
│                                                         │   │
│  ◄── BIGGEST OPPORTUNITY: 41.7% of total ───────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

**The single largest optimization opportunity is the tree builder's mode switching, scope checking, and implied end tag logic, which consumes 41.7% of total parse time.**

Further optimization should focus on:
1. Reducing scope checking overhead (bitmap caching)
2. Optimizing implied end tag generation
3. Flattening mode dispatch hierarchy
4. Fast paths for common tag sequences

---

*Report generated from profiling tests in `Tests/swift-justhtmlTests/ProfilingTests.swift`*

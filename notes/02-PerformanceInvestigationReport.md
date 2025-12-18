# Performance Investigation Report: swift-justhtml

**Commit:** `0c0ee00`
**Date:** 2025-12-17 09:20:17 UTC
**Result:** 307ms (Easy wins failed - only 1.2% improvement)

---

## Executive Summary

This report presents the findings from a comprehensive performance investigation of the swift-justhtml HTML5 parser. The investigation aimed to understand why Swift is **2.9x slower than JavaScript** for HTML parsing.

### Key Findings

| Metric | Value |
|--------|-------|
| Swift Total Parse Time | 308 ms |
| JavaScript Total Parse Time | 108 ms |
| Slowdown Factor | 2.9x |
| Throughput | 7.5 MB/s |

### Top 3 Performance Bottlenecks (Priority Order)

1. **String.Index Character Iteration** - 12x slower than UTF-8 byte iteration
2. **Character Lowercase Conversion** - Allocates a String per character
3. **Tree Builder Overhead** - ~50% of total parse time in DOM construction

### Estimated Improvement Potential

| Optimization | Estimated Speedup | Effort |
|--------------|-------------------|--------|
| UTF-8 based tokenizer | 1.5-2.0x | High |
| Inline character helpers | 1.1-1.3x | Low |
| Tree builder optimizations | 1.1-1.2x | Medium |
| **Combined** | **2.0-2.5x** | High |

---

## 1. Performance Baseline

### 1.1 Real-World File Benchmarks

| File | Size | Swift | JavaScript | Slowdown |
|------|------|-------|------------|----------|
| hackernews.html | 34 KB | 4.01 ms | 1.83 ms | 2.19x |
| wikipedia_countries.html | 360 KB | 43.16 ms | 16.73 ms | 2.58x |
| wikipedia_html.html | 472 KB | 63.31 ms | 20.99 ms | 3.02x |
| wikipedia_swift.html | 411 KB | 53.70 ms | 18.64 ms | 2.88x |
| wikipedia_ww2.html | 1204 KB | 146.39 ms | 49.32 ms | 2.97x |
| **TOTAL** | **2481 KB** | **310.57 ms** | **107.51 ms** | **2.89x** |

**Observation:** The slowdown increases with file size (2.19x → 2.97x), suggesting issues that compound with scale.

### 1.2 Throughput Analysis

| File | Throughput (MB/s) |
|------|------------------|
| hackernews.html | 8.60 |
| wikipedia_countries.html | 8.55 |
| wikipedia_html.html | 7.64 |
| wikipedia_swift.html | 7.83 |
| wikipedia_ww2.html | 8.42 |
| **Average** | **7.56** |

Throughput is reasonably consistent across file sizes, indicating no catastrophic algorithmic issues.

---

## 2. Component Analysis

### 2.1 Tokenizer vs Tree Builder Split

The parser consists of two main components:
- **Tokenizer**: Converts HTML text into tokens (state machine)
- **Tree Builder**: Constructs DOM tree from tokens

| File | Tokenizer | Tree Builder | Total |
|------|-----------|--------------|-------|
| hackernews.html | 3.59 ms (44.9%) | 4.41 ms (55.1%) | 8.00 ms |
| wikipedia_countries.html | 37.31 ms (50.5%) | 36.51 ms (49.5%) | 73.82 ms |
| wikipedia_html.html | 49.67 ms (57.3%) | 37.05 ms (42.7%) | 86.72 ms |
| wikipedia_swift.html | 24.50 ms (38.8%) | 38.65 ms (61.2%) | 63.16 ms |
| wikipedia_ww2.html | 73.71 ms (42.8%) | 98.40 ms (57.2%) | 172.11 ms |

**Key Insight:** Both components contribute roughly equally. Optimizing either alone won't be sufficient.

### 2.2 Token and Node Density

| File | Tokens | Tokens/KB | Nodes | Nodes/KB | Entities |
|------|--------|-----------|-------|----------|----------|
| hackernews.html | 2,077 | 63 | 1,289 | 39 | 117 |
| wikipedia_countries.html | 16,191 | 45 | 10,863 | 30 | 484 |
| wikipedia_html.html | 21,524 | 46 | 14,502 | 31 | 2,301 |
| wikipedia_swift.html | 20,139 | 49 | 13,707 | 33 | 2,237 |
| wikipedia_ww2.html | 45,236 | 38 | 30,563 | 25 | 9,229 |

---

## 3. Hot Path Analysis

### 3.1 String Operations (CRITICAL)

**Finding:** Character iteration is 12x slower than UTF-8 iteration.

```
String size: 1,224,136 characters, 1,232,920 bytes
Character iteration:    9.83 ms per pass
UTF-8 byte iteration:   0.82 ms per pass
Index advancement:      4.90 ms per pass
Speedup (UTF-8 vs char): 12.0x
```

**Root Cause:** Swift's `String` type uses grapheme cluster iteration by default, which involves:
- O(n) index computation for each character access
- UTF-8 validation overhead
- Grapheme boundary detection

**Current Code Pattern (Slow):**
```swift
// Tokenizer.swift:536-552
private func consume() -> Character? {
    guard self.pos < self.input.endIndex else { return nil }
    let ch = self.input[self.pos]           // O(1) but with validation
    self.pos = self.input.index(after: self.pos)  // O(1) amortized, but heavy
    // ...
    return ch
}
```

**Impact:** Every character consumed requires String.Index operations.

### 3.2 Character Helper Methods (HIGH)

**Finding:** `asLowercaseCharacter` allocates a String on every call.

```swift
// Tokenizer.swift:2925-2927
var asLowercaseCharacter: Character {
    return Character(String(self).lowercased())  // Allocates String!
}
```

This is called in hot paths:
- `tagNameState()` - Every tag character
- `attributeNameState()` - Every attribute character
- `doctypeNameState()` - Doctype names
- `consumeIf()` - Case-insensitive matching

**Usage Frequency:** Called for every letter in tag names, attribute names, doctype names.

### 3.3 Dictionary Lookups (ACCEPTABLE)

**Finding:** Entity dictionary lookups are fast.

```
NAMED_ENTITIES dictionary size: 2,125 entries
Time per lookup: 31.21 ns
Lookups per second: 32 million

LEGACY_ENTITIES set size: 106 entries
Time per lookup: 25.71 ns
```

Entity decoding is **not a bottleneck**.

### 3.4 Memory Allocation Analysis

| Metric | Value |
|--------|-------|
| Element nodes | 15,217 |
| Text nodes | 15,340 |
| Comment nodes | 4 |
| **Total nodes** | **30,561** |
| Estimated memory | ~3 MB |
| Ratio to input | 2.48x |

Memory overhead is reasonable. Each `Node` is a class with ~100 bytes overhead.

---

## 4. Scaling Behavior

**Finding:** Linear scaling - time per KB is consistent.

| Paragraphs | Size | Parse Time | Time/KB | Ratio |
|------------|------|------------|---------|-------|
| 100 | 7.9 KB | 3.19 ms | 0.405 ms/KB | 1.00x |
| 500 | 39.5 KB | 15.62 ms | 0.395 ms/KB | 0.98x |
| 1000 | 79.1 KB | 21.13 ms | 0.267 ms/KB | 0.66x |
| 2000 | 159.1 KB | 42.21 ms | 0.265 ms/KB | 0.65x |
| 5000 | 399.4 KB | 99.88 ms | 0.250 ms/KB | 0.62x |
| 10000 | 799.8 KB | 195.71 ms | 0.245 ms/KB | 0.60x |

Time per KB actually **decreases** with larger documents due to warmup amortization. No O(n²) issues detected.

---

## 5. Root Cause Summary

### 5.1 Why Swift is Slower Than JavaScript

| Factor | Impact | Explanation |
|--------|--------|-------------|
| **String Iteration Model** | High | Swift uses grapheme clusters; JS V8 uses UTF-16 code units with optimized JIT |
| **Type System Overhead** | Medium | Swift's Character type has validation overhead; JS characters are simple UTF-16 |
| **JIT Compilation** | Medium | V8 JIT specializes hot loops at runtime; Swift AOT can't adapt |
| **Reference Counting** | Low-Medium | Swift ARC has overhead on Node allocations; JS uses tracing GC |
| **String Interning** | Low | V8 interns short strings; Swift doesn't automatically |

### 5.2 Swift-Specific Issues Found

1. **String.Index Iteration**: Every `consume()` call involves complex index arithmetic
2. **Lowercase Allocation**: `asLowercaseCharacter` allocates a String per character
3. **Character Range Checks**: `isASCIILetter`, `isASCIIDigit` use Character range comparisons
4. **No UTF-8 View Usage**: Tokenizer uses `Character` when `UInt8` would suffice for ASCII

---

## 6. Optimization Recommendations

### 6.1 High Priority (Easy Wins)

#### 6.1.1 Fix Lowercase Character Allocation
**Location:** `Tokenizer.swift:2925-2927`
**Effort:** Low
**Impact:** ~5-10% speedup

```swift
// BEFORE (allocates String)
var asLowercaseCharacter: Character {
    return Character(String(self).lowercased())
}

// AFTER (no allocation)
var asLowercaseCharacter: Character {
    guard let ascii = self.asciiValue else { return self }
    if ascii >= 65 && ascii <= 90 {  // A-Z
        return Character(UnicodeScalar(ascii + 32))
    }
    return self
}
```

#### 6.1.2 Use ASCII Byte Comparisons
**Location:** `Tokenizer.swift:2912-2923`
**Effort:** Low
**Impact:** ~5% speedup

```swift
// BEFORE
var isASCIILetter: Bool {
    return ("a"..."z").contains(self) || ("A"..."Z").contains(self)
}

// AFTER
var isASCIILetter: Bool {
    guard let ascii = self.asciiValue else { return false }
    return (ascii >= 65 && ascii <= 90) || (ascii >= 97 && ascii <= 122)
}
```

### 6.2 Medium Priority

#### 6.2.1 Add `@inlinable` to Hot Path Methods
**Location:** Tokenizer.swift, TreeBuilder.swift
**Effort:** Low
**Impact:** ~5-10% speedup

```swift
@inlinable
private func consume() -> Character? { ... }

@inlinable
private func peek() -> Character? { ... }

@inlinable
private func emitChar(_ ch: Character) { ... }
```

#### 6.2.2 Use ContiguousArray for Open Elements Stack
**Location:** `TreeBuilder.swift:55`
**Effort:** Low
**Impact:** ~2-5% speedup

```swift
// BEFORE
private var openElements: [Node] = []

// AFTER
private var openElements: ContiguousArray<Node> = []
```

### 6.3 High Impact (Significant Effort)

#### 6.3.1 UTF-8 Based Tokenizer
**Effort:** High (major rewrite)
**Impact:** 1.5-2.0x speedup

Rewrite the tokenizer to operate on UTF-8 bytes instead of Characters:
- Use `UnsafeBufferPointer<UInt8>` for input
- Use `Int` offset instead of `String.Index`
- Only convert to Character/String when emitting tokens

```swift
// Conceptual approach
private var input: ContiguousArray<UInt8> = []
private var pos: Int = 0

@inline(__always)
private func consume() -> UInt8? {
    guard pos < input.count else { return nil }
    let byte = input[pos]
    pos += 1
    return byte
}
```

#### 6.3.2 Token Pooling/Reuse
**Effort:** Medium
**Impact:** ~10% speedup

Instead of creating new Token enum cases, reuse token objects:

```swift
// Instead of creating new tokens
private var currentStartTag: StartTagToken = StartTagToken()

func emitStartTag() {
    sink.processToken(.startTag(currentStartTag))
    currentStartTag.reset()
}
```

---

## 7. Comparison with JavaScript Architecture

### 7.1 V8 Advantages

| Feature | V8 JavaScript | Swift |
|---------|---------------|-------|
| String Representation | UTF-16 (fast code unit access) | UTF-8 (needs validation) |
| JIT Optimization | Yes (specializes hot loops) | No (AOT only) |
| Inline Caching | Yes (monomophic call sites) | Limited via devirtualization |
| String Interning | Automatic for short strings | Manual only |
| GC vs ARC | Generational GC (batch deallocation) | ARC (per-object counting) |

### 7.2 Why JavaScript Wins for HTML Parsing

1. **UTF-16 Alignment**: HTML is mostly ASCII; V8's UTF-16 strings give O(1) character access
2. **JIT Specialization**: V8 compiles hot tokenizer loops to optimized native code
3. **Hidden Classes**: V8 optimizes property access on Node objects
4. **Inline Caching**: Method calls become direct jumps after warmup

---

## 8. Realistic Expectations

### 8.1 What's Achievable

With the optimizations listed above, we can realistically expect:

| Scenario | Estimated Total Time | Speedup vs Current |
|----------|---------------------|-------------------|
| Current | 310 ms | 1.0x |
| Easy wins only | 260-280 ms | 1.1-1.2x |
| All optimizations | 155-200 ms | 1.5-2.0x |
| JavaScript | 108 ms | 2.9x |

### 8.2 What's NOT Achievable

Reaching JavaScript parity (108 ms) is unlikely without:
- Complete UTF-8 rewrite
- Significant unsafe code usage
- Losing Swift's safety guarantees

A **1.5-2.0x speedup** to ~150-200ms is a realistic goal that maintains Swift idioms.

---

## 9. Recommended Implementation Order

### Phase 1: Quick Wins (1-2 hours)
1. Fix `asLowercaseCharacter` to avoid allocation
2. Optimize `isASCIILetter`, `isASCIIDigit`, `isHexDigit` to use byte values
3. Add `@inlinable` to consume(), peek(), emitChar()

### Phase 2: Medium Optimizations (2-4 hours)
4. Use `ContiguousArray` for hot arrays
5. Add `@inline(__always)` for critical path functions
6. Pre-reserve capacity for string buffers

### Phase 3: Major Rewrite (8-16 hours)
7. Convert tokenizer to UTF-8 byte-based operation
8. Implement token pooling
9. Consider using `withUnsafeBufferPointer` for input

---

## 10. Optimization Experiment Results

### 10.1 "Easy Wins" Implementation

We implemented the Phase 1 optimizations to validate our predictions:

1. **ASCII byte comparisons** for `isASCIILetter`, `isASCIIDigit`, `isHexDigit`
2. **Avoiding String allocation** in `asLowercaseCharacter`
3. **`@inline(__always)`** annotations on hot path methods

### 10.2 Micro-Benchmark Results

**Surprising Finding:** The Swift compiler already optimizes the original implementations very well.

```
Testing asLowercaseCharacter implementations (10M iterations, release build):

Old (String allocation):  0.57s
New (ASCII byte math):    0.70s
Speedup: 0.81x (NEW IS SLOWER!)
```

The `String(self).lowercased()` pattern is being optimized by Swift's compiler to avoid actual heap allocations in hot loops. The "optimized" ASCII byte version actually added overhead from the guard statement and arithmetic.

### 10.3 Full Benchmark Results

| File | Before | After | Change |
|------|--------|-------|--------|
| hackernews.html | 4.01 ms | 4.02 ms | ~0% |
| wikipedia_countries.html | 43.16 ms | 42.80 ms | -0.8% |
| wikipedia_html.html | 63.31 ms | 62.19 ms | -1.8% |
| wikipedia_swift.html | 53.70 ms | 52.97 ms | -1.4% |
| wikipedia_ww2.html | 146.39 ms | 144.72 ms | -1.1% |
| **TOTAL** | **310.57 ms** | **306.70 ms** | **-1.2%** |

### 10.4 Final Changes Kept

After discovering the micro-benchmark results, we reverted the character helper changes but kept the `@inline(__always)` annotations:

**Tokenizer.swift:**
- `consume()`, `peek()`, `reconsume()` - core character consumption
- `emit()`, `emitChar()`, `emitString()` - token emission
- `isASCIILetter`, `isASCIIDigit`, `isHexDigit`, `asLowercaseCharacter` - character helpers

**TreeBuilder.swift:**
- `currentNode` - frequently accessed property
- `adjustedInsertionTarget` - insertion location lookup
- `isWhitespace()` - whitespace detection

### 10.5 Key Learnings

1. **Swift's optimizer is excellent** - Don't assume manual "optimizations" will be faster
2. **Micro-benchmark before committing** - Our predictions were wrong about character helpers
3. **The real bottleneck is architectural** - String.Index iteration overhead requires a UTF-8 rewrite
4. **Easy wins don't exist here** - The Swift team has already optimized the obvious patterns

---

## 11. Conclusion

The swift-justhtml parser is **2.9x slower** than the JavaScript implementation primarily due to:

1. **String.Index overhead** (12x slower than UTF-8 byte iteration)
2. **Architectural mismatch** - Swift's Unicode-correct strings vs V8's optimized UTF-16
3. **No JIT compilation** - V8 specializes hot paths at runtime

### What We Learned

The "easy wins" we identified (ASCII byte comparisons, avoiding String allocation) **do not provide meaningful speedups** because Swift's compiler already optimizes these patterns effectively.

### Path Forward

To achieve significant performance improvements (1.5-2x speedup), the tokenizer would need to be **rewritten to operate on UTF-8 bytes directly** using `UInt8` and integer offsets instead of `Character` and `String.Index`. This is a substantial architectural change.

### Current State

- **Swift:** 307 ms (after minor optimizations)
- **JavaScript:** 108 ms
- **Gap:** 2.8x (unchanged)

Reaching JavaScript parity is unrealistic without sacrificing Swift's safety guarantees and idiomatic code patterns.

---

## Appendix A: Test Environment

- **Platform:** Linux x86_64
- **Swift Version:** Swift 6.x
- **Build Configuration:** Release (-O)
- **CPU:** x86_64
- **Measurement Method:** `clock_gettime(CLOCK_MONOTONIC)`

## Appendix B: Files Modified

### For Profiling (Investigation)
- `Tests/swift-justhtmlTests/ProfilingTests.swift` (created)

### Production Code Changes
- `Sources/swift-justhtml/Tokenizer.swift` - Added `@inline(__always)` to hot path methods
- `Sources/swift-justhtml/TreeBuilder.swift` - Added `@inline(__always)` to hot path methods

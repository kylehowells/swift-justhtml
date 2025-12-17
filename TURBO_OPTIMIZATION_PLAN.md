# Turbo Optimization Plan

**Goal:** Match or beat JavaScript implementation speed (108ms) while maintaining 100% test pass rate.

**Current State:**
- Swift: 308 ms
- JavaScript: 108 ms
- Target: < 108 ms (2.9x improvement needed)

---

## Phase 1: UTF-8 Byte-Based Tokenizer (HIGH IMPACT)

The profiling showed String.Index iteration is 12x slower than UTF-8. This is the primary bottleneck.

### 1.1 Convert Input to UTF-8 Buffer
```swift
// Instead of:
private var input: String = ""
private var pos: String.Index

// Use:
private var inputBytes: [UInt8] = []
private var pos: Int = 0
```

### 1.2 Replace Character Operations with Byte Operations
```swift
// Instead of:
private func consume() -> Character?

// Use:
@inline(__always)
private func consumeByte() -> UInt8?
```

### 1.3 Handle Multi-byte UTF-8 Sequences
- ASCII (0x00-0x7F): Single byte, most common in HTML
- Multi-byte: Only decode when needed for text content

### 1.4 Key Methods to Rewrite
- [ ] `consume()` → byte-based
- [ ] `peek()` → byte-based
- [ ] `reconsume()` → byte-based
- [ ] `consumeIf()` → byte-based
- [ ] All state handlers → byte comparisons

---

## Phase 2: Optimize String Building (MEDIUM IMPACT)

### 2.1 Use ContiguousArray for Buffers
```swift
// Instead of String concatenation:
private var charBuffer: String = ""

// Use byte buffer:
private var charBuffer: ContiguousArray<UInt8> = []
```

### 2.2 Pre-allocate Capacity
```swift
charBuffer.reserveCapacity(estimatedSize)
```

### 2.3 Batch String Creation
- Build up bytes, convert to String only when emitting token

---

## Phase 3: Tree Builder Optimizations (MEDIUM IMPACT)

### 3.1 Use ContiguousArray for Stacks
```swift
private var openElements: ContiguousArray<Node> = []
private var activeFormattingElements: ContiguousArray<Node?> = []
```

### 3.2 Optimize Tag Name Comparisons
- Use integer tag IDs instead of string comparisons
- Create enum or lookup table for common tags

### 3.3 Optimize insertCharacter
- Batch character insertions
- Avoid creating new text nodes for each character

---

## Phase 4: Memory Optimizations (LOW-MEDIUM IMPACT)

### 4.1 Object Pooling
- Reuse Node objects where possible
- Pool temporary strings/buffers

### 4.2 Reduce ARC Traffic
- Use `unowned` where safe
- Minimize reference counting in hot loops

---

## Phase 5: Micro-Optimizations (LOW IMPACT)

### 5.1 Lookup Tables
```swift
// Fast whitespace check
private static let whitespaceTable: [Bool] = {
    var table = [Bool](repeating: false, count: 256)
    table[0x09] = true // tab
    table[0x0A] = true // LF
    table[0x0C] = true // FF
    table[0x0D] = true // CR
    table[0x20] = true // space
    return table
}()
```

### 5.2 Branch Prediction Hints
- Order switch cases by frequency
- Use `@inline(__always)` strategically

---

## Benchmarking Commands

```bash
# Build release
swift build -c release

# Run comparison benchmark
python3 Benchmarks/compare.py

# Quick benchmark
.build/release/benchmark

# Run tests
swift test -c release

# Format code
swiftformat .
```

---

## Progress Tracking

| Iteration | Time (ms) | Speedup | Notes |
|-----------|-----------|---------|-------|
| Baseline | 302 | 1.0x | Original |
| UTF-8 Tokenizer | 261 | 1.16x | ContiguousArray<UInt8> input |
| Batch Text Insert | 182 | 1.66x | insertText() method |
| Set Lookups | 172 | 1.76x | Static Sets for tag names |
| ASCII Optimizations | 173 | 1.75x | UTF-8 case-insensitive compare |
| **Current** | **173** | **1.75x** | Module-level Set constants |
| Target | 106 | 2.85x | Match JS |

**Summary:** Achieved 43% speedup (302ms → 173ms). Still ~63% slower than JavaScript (173ms vs 106ms).

---

## Test Validation

Before each commit, ensure:
1. `swift test` passes all tests
2. Tree construction: 1831/1831
3. Tokenizer: 6810/6810
4. Serializer: 230/230

---

## Commit Strategy

When achieving a new best time:
1. Run full test suite
2. Run `swiftformat .`
3. Commit with benchmark results
4. Push to remote

---

## Current Focus

Starting with Phase 1: UTF-8 Byte-Based Tokenizer

This is expected to provide the largest improvement (potentially 2-3x).

# Performance Investigation Plan: Swift vs JavaScript

## Executive Summary

The swift-justhtml implementation is **2.9x slower** than the JavaScript implementation:
- Swift: 308 ms total
- JavaScript: 108 ms total
- Python: 417 ms total (Swift is 1.4x faster than Python)

This document outlines the plan to investigate why Swift is slower and identify optimization opportunities.

## Current Performance Baseline

| File | Size | Swift | JavaScript | Slowdown |
|------|------|-------|------------|----------|
| hackernews.html | 34 KB | 3.96 ms | 1.83 ms | 2.16x |
| wikipedia_countries.html | 360 KB | 42.27 ms | 16.73 ms | 2.53x |
| wikipedia_html.html | 472 KB | 62.09 ms | 20.99 ms | 2.96x |
| wikipedia_swift.html | 411 KB | 52.85 ms | 18.64 ms | 2.84x |
| wikipedia_ww2.html | 1204 KB | 147.13 ms | 49.32 ms | 2.98x |

**Observation**: The slowdown ratio increases with file size (2.16x → 2.98x), suggesting the issue may be related to memory allocation, string operations, or algorithmic complexity that scales poorly.

---

## Phase 1: Instrumentation & Profiling Tools

### 1.1 Create High-Precision Timing Utility

Create a reusable timing function with `@inline(__always)` to minimize measurement overhead:

```swift
// Sources/swift-justhtml/Profiling.swift

import Foundation

/// High-precision timing utility for performance profiling
@inline(__always)
public func measureTime<T>(
    _ name: String,
    iterations: Int = 1,
    warmup: Int = 0,
    _ block: () throws -> T
) rethrows -> T {
    // Warmup iterations (not measured)
    for _ in 0..<warmup {
        _ = try block()
    }

    // Use clock_gettime for high precision (nanoseconds)
    var start = timespec()
    var end = timespec()

    clock_gettime(CLOCK_MONOTONIC, &start)
    var result: T!
    for _ in 0..<iterations {
        result = try block()
    }
    clock_gettime(CLOCK_MONOTONIC, &end)

    let startNs = Int64(start.tv_sec) * 1_000_000_000 + Int64(start.tv_nsec)
    let endNs = Int64(end.tv_sec) * 1_000_000_000 + Int64(end.tv_nsec)
    let totalNs = endNs - startNs
    let avgNs = totalNs / Int64(iterations)

    let avgMs = Double(avgNs) / 1_000_000.0
    print("[\(name)] \(iterations) iterations: \(String(format: "%.3f", avgMs))ms avg")

    return result
}

/// Measure a specific code section inline
@inline(__always)
public func profile<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
    var start = timespec()
    var end = timespec()

    clock_gettime(CLOCK_MONOTONIC, &start)
    let result = try block()
    clock_gettime(CLOCK_MONOTONIC, &end)

    let startNs = Int64(start.tv_sec) * 1_000_000_000 + Int64(start.tv_nsec)
    let endNs = Int64(end.tv_sec) * 1_000_000_000 + Int64(end.tv_nsec)
    let ns = endNs - startNs

    if ns > 1_000_000 { // Only log if > 1ms
        print("⏱ \(name): \(String(format: "%.3f", Double(ns) / 1_000_000.0))ms")
    }

    return result
}
```

### 1.2 Create Aggregating Profiler

For tracking cumulative time spent in different parser phases:

```swift
/// Thread-local profiler for aggregating timing data
public final class Profiler {
    public static var shared = Profiler()

    private var timings: [String: (count: Int, totalNs: Int64)] = [:]
    private var enabled = false

    public func enable() { enabled = true; timings.removeAll() }
    public func disable() { enabled = false }

    @inline(__always)
    public func measure<T>(_ name: String, _ block: () -> T) -> T {
        guard enabled else { return block() }

        var start = timespec()
        var end = timespec()
        clock_gettime(CLOCK_MONOTONIC, &start)
        let result = block()
        clock_gettime(CLOCK_MONOTONIC, &end)

        let ns = (Int64(end.tv_sec) - Int64(start.tv_sec)) * 1_000_000_000
               + Int64(end.tv_nsec) - Int64(start.tv_nsec)

        if let existing = timings[name] {
            timings[name] = (existing.count + 1, existing.totalNs + ns)
        } else {
            timings[name] = (1, ns)
        }

        return result
    }

    public func report() {
        print("\n=== Profiler Report ===")
        let sorted = timings.sorted { $0.value.totalNs > $1.value.totalNs }
        for (name, data) in sorted {
            let totalMs = Double(data.totalNs) / 1_000_000.0
            let avgUs = Double(data.totalNs) / Double(data.count) / 1000.0
            print("\(name): \(String(format: "%.2f", totalMs))ms total, \(data.count) calls, \(String(format: "%.2f", avgUs))µs avg")
        }
    }
}
```

---

## Phase 2: Profile Major Components

### 2.1 Identify Hot Paths

The parser has three main phases that need profiling:

1. **Tokenizer** (~2900 lines) - Converts HTML text to tokens
2. **TreeBuilder** (~3700 lines) - Builds DOM tree from tokens
3. **Entity Decoding** - Handles `&amp;`, `&#60;`, etc.

### 2.2 Specific Areas to Instrument

#### Tokenizer Hot Paths
```swift
// In Tokenizer.swift, instrument these methods:
- run()                    // Main entry point
- dataState()              // Most common state
- tagOpenState()           // Tag parsing
- characterReferenceState() // Entity handling
- namedCharacterReferenceState() // Named entity lookup
- consume()                // Character consumption
- emit()                   // Token emission
```

#### TreeBuilder Hot Paths
```swift
// In TreeBuilder.swift, instrument these methods:
- processToken()           // Main dispatch
- insertElement()          // Node creation
- reconstructActiveFormattingElements() // Complex algorithm
- adoptionAgencyAlgorithm() // Very complex algorithm
- generateImpliedEndTags() // Frequent operation
```

### 2.3 Create Profiling Test

```swift
@Test func profileLargeFile() async throws {
    let url = URL(fileURLWithPath: "Benchmarks/samples/wikipedia_ww2.html")
    let html = try String(contentsOf: url, encoding: .utf8)

    Profiler.shared.enable()
    _ = try JustHTML(html)
    Profiler.shared.disable()
    Profiler.shared.report()
}
```

---

## Phase 3: Known Swift Performance Issues to Investigate

### 3.1 String Operations (HIGH PRIORITY)

Swift's String is Unicode-correct but slow for byte-level operations:

```swift
// SLOW: Character-by-character iteration
for ch in html { ... }  // O(n) per access due to grapheme clusters

// FASTER: UTF-8 view iteration
for byte in html.utf8 { ... }

// FASTEST: ContiguousArray for working buffer
var buffer = ContiguousArray<UInt8>(html.utf8)
```

**Investigation**: Check if Tokenizer uses Character iteration vs UTF-8.

### 3.2 Class vs Struct (MEDIUM PRIORITY)

Classes have reference counting overhead:

```swift
// Current: Node is a class (reference semantics needed for tree)
public final class Node { ... }

// Ensure 'final' is on all classes to enable devirtualization
```

**Action**: Verify all classes have `final` keyword.

### 3.3 Dictionary Lookups (HIGH PRIORITY)

Entity lookup uses dictionary:

```swift
// Current approach
if let decoded = NAMED_ENTITIES[entityName] { ... }

// Potential issue: String hashing is expensive
// Consider: Pre-computed perfect hash or trie structure
```

**Investigation**: Profile `namedCharacterReferenceState()` specifically.

### 3.4 Array Operations (MEDIUM PRIORITY)

```swift
// SLOW: Repeated appends without reservation
var tokens: [Token] = []
tokens.append(token)  // May reallocate

// FASTER: Reserve capacity if size is estimable
tokens.reserveCapacity(estimatedCount)
```

### 3.5 Copy-on-Write Triggers (HIGH PRIORITY)

```swift
// Potential CoW issue in hot path
self.currentTagName += String(ch)  // May copy entire string

// Better: Use a mutable buffer
self.currentTagName.append(ch)  // In-place if unique reference
```

### 3.6 Protocol Existentials (MEDIUM PRIORITY)

```swift
// SLOW: Protocol existential (dynamic dispatch + allocation)
var sink: TokenSink

// FASTER: Generic constraint (static dispatch)
func run<S: TokenSink>(sink: S) { ... }
```

---

## Phase 4: Specific Optimization Candidates

### 4.1 Tokenizer Optimizations

| Area | Current Issue | Proposed Fix |
|------|---------------|--------------|
| Character consumption | Using String.Index | Use UTF-8 view with Int offset |
| State machine | Switch statement | Jump table or computed goto |
| Tag name building | String concatenation | Pre-allocated buffer |
| Entity lookup | Dictionary<String, String> | Trie or perfect hash |
| Whitespace check | Multiple comparisons | Lookup table |

### 4.2 TreeBuilder Optimizations

| Area | Current Issue | Proposed Fix |
|------|---------------|--------------|
| Element stack | Array of class refs | Consider ContiguousArray |
| Tag name matching | String comparison | Interned strings or enums |
| Attribute storage | [String: String] | Custom struct if small |

### 4.3 Memory Allocation

| Area | Current Issue | Proposed Fix |
|------|---------------|--------------|
| Node creation | Individual allocations | Object pool |
| Token creation | Enum with associated data | Reusable token buffer |
| String building | Multiple small strings | Single StringBuilder |

---

## Phase 5: Investigation Steps

### Step 1: Baseline Measurement
1. Run existing benchmarks with release build (`-O`)
2. Use Instruments.app (macOS) or `perf` (Linux) for system profiling
3. Identify top functions by CPU time

### Step 2: Add Instrumentation
1. Create Profiling.swift with timing utilities
2. Add profiling calls to major functions
3. Run profiled benchmark and collect data

### Step 3: Analyze Results
1. Identify which phase takes the most time (tokenizer vs tree builder)
2. Within each phase, identify the hottest functions
3. Compare with JavaScript implementation approach

### Step 4: Implement Quick Wins
1. Add `final` to all classes
2. Use `@inlinable` on hot path functions
3. Pre-allocate buffers where possible
4. Consider `ContiguousArray` for hot arrays

### Step 5: Targeted Optimizations
1. Based on profiling data, optimize the top 3-5 hot spots
2. Re-benchmark after each change
3. Document performance gains

---

## Phase 6: Comparison with JavaScript Implementation

### Key Questions to Answer

1. **String representation**: How does JS handle strings internally vs Swift?
2. **Memory model**: V8's generational GC vs Swift's ARC
3. **JIT advantages**: What optimizations does V8 apply that Swift can't?
4. **Algorithm differences**: Are there algorithmic differences between implementations?

### Potential Unavoidable Differences

- V8's JIT can specialize hot paths at runtime
- JavaScript strings are often optimized for common cases
- V8 has decades of optimization for web parsing workloads

---

## Deliverables

### Report Contents

1. **Profiling Results**: Breakdown of time spent in each major component
2. **Hot Spot Analysis**: Top 10 functions by CPU time
3. **Memory Analysis**: Allocation patterns and potential issues
4. **Optimization Recommendations**: Prioritized list of changes
5. **Expected Improvements**: Estimated gains from each optimization
6. **Implementation Plan**: Ordered list of changes to make

### Success Criteria

- Identify where 80%+ of parsing time is spent
- Find at least 3 concrete optimization opportunities
- Estimate potential speedup for each optimization
- Create actionable implementation tickets

---

## Timeline

| Phase | Description | Estimated Effort |
|-------|-------------|------------------|
| Phase 1 | Create profiling tools | 1-2 hours |
| Phase 2 | Instrument code | 2-3 hours |
| Phase 3 | Investigate known issues | 2-3 hours |
| Phase 4 | Detailed analysis | 3-4 hours |
| Phase 5 | Write report | 2-3 hours |
| **Total** | | **10-15 hours** |

---

## Quick Reference: Swift Performance Best Practices

```swift
// 1. Mark classes as final
final class Node { ... }

// 2. Use @inlinable for hot path functions
@inlinable
func consume() -> Character { ... }

// 3. Use @inline(__always) sparingly for critical paths
@inline(__always)
func isWhitespace(_ c: UInt8) -> Bool { ... }

// 4. Prefer value types on stack
struct Token { ... }  // vs class Token

// 5. Use ContiguousArray for performance-critical arrays
var stack = ContiguousArray<Node>()

// 6. Reserve capacity for collections
var results: [Node] = []
results.reserveCapacity(100)

// 7. Avoid String.Index arithmetic in hot loops
// Use utf8 view with integer offsets instead

// 8. Use withUnsafeBufferPointer for read-only access
html.utf8.withContiguousStorageIfAvailable { buffer in
    // Direct memory access
}

// 9. Avoid creating intermediate strings
// Bad: let sub = String(html[start..<end])
// Good: work with indices directly

// 10. Use lazy evaluation where appropriate
let filtered = array.lazy.filter { ... }.map { ... }
```

---

## Appendix: Useful Commands

```bash
# Build with optimizations
swift build -c release

# Run with profiling (Linux)
perf record -g .build/release/benchmark
perf report

# Run with profiling (macOS)
xcrun xctrace record --template 'Time Profiler' --launch .build/release/benchmark

# Check for ARC traffic
swift build -c release -Xswiftc -emit-sil | grep -c "strong_retain\|strong_release"

# Generate assembly for hot function
swift build -c release -Xswiftc -emit-assembly
```

# Performance

Swift-justhtml performance characteristics and optimization history.

## Overview

Swift-justhtml is a high-performance HTML5 parser that matches JavaScript ([justjshtml](https://github.com/simonw/justjshtml)) performance while maintaining full spec compliance. This document covers performance benchmarks, memory usage, and the optimization journey.

## Performance Summary

*As of December 17, 2025 (commit `fab4f5b`)*

### Parse Time Comparison

| Implementation | Total Time | Comparison |
|----------------|-----------|------------|
| **Swift** | 97ms | - |
| JavaScript (justjshtml) | 99ms | 1.02x slower |
| Python ([justhtml](https://github.com/EmilStenstrom/justhtml)) | 398ms | 4.1x slower |

*Benchmark: Parsing 2.5MB of HTML across 5 Wikipedia articles*

### Memory Usage Comparison

| Implementation | Peak RSS | Comparison |
|----------------|----------|------------|
| **Swift** | 103 MB | - |
| Python | 106 MB | 1.03x more |
| JavaScript | 226 MB | 2.2x more |

*Benchmark: Average peak memory across 6 test files including 20MB synthetic HTML*

### Throughput

| File | Size | Time | Throughput |
|------|------|------|------------|
| hackernews.html | 34 KB | 2.05ms | 17 MB/s |
| wikipedia_countries.html | 360 KB | 14.25ms | 25 MB/s |
| wikipedia_html.html | 472 KB | 19.69ms | 24 MB/s |
| wikipedia_swift.html | 411 KB | 16.80ms | 24 MB/s |
| wikipedia_ww2.html | 1,204 KB | 44.39ms | 27 MB/s |

## Current Performance Profile

The parser achieves ~98ms total parse time with the following component breakdown:

```
Tokenizer:     ~47% of total parse time (~44ms)
Tree Builder:  ~53% of total parse time (~54ms)
```

### Tokenizer Breakdown

| Operation | % of Tokenizer |
|-----------|----------------|
| Tag name scanning | 38% |
| Attribute parsing | 24% |
| Entity decoding | 19% |
| State machine overhead | 10% |
| Text scanning | 9% |

Key finding: Pure text processing is extremely fast (650 MB/s). Tag parsing is 21.7x slower than pure text due to state machine transitions.

### Tree Builder Breakdown

| Operation | % of Tree Builder |
|-----------|-------------------|
| Mode/scope logic | 79% |
| Tag dispatch | 10% |
| Node creation | 6% |
| appendChild | 5% |

The "mode/scope logic" includes:
- Insertion mode switching (large switch statements)
- Scope checking (`hasElementInScope()`)
- Implied end tag generation
- Active formatting element reconstruction
- Foster parenting logic

## Optimization History

The parser achieved a **3.1x speedup** (302ms to 97ms) through systematic profiling and targeted optimizations.

### Optimization Timeline

| Milestone | Total Time | Speedup | Cumulative |
|-----------|-----------|---------|------------|
| Baseline | 302ms | - | 1.0x |
| UTF-8 Byte Tokenizer | 261ms | 1.16x | 1.16x |
| Batch Text Insertion | 182ms | 1.43x | 1.66x |
| Static Set Lookups | 172ms | 1.06x | 1.76x |
| Batch Text Scanning | 159ms | 1.08x | 1.90x |
| Batch Tag/Attr Scanning | 118ms | 1.35x | 2.56x |
| Inline Arrays to Sets | 98ms | 1.20x | 3.08x |
| Reusable Name Buffer | 97ms | 1.01x | **3.11x** |

### Key Optimizations

#### 1. UTF-8 Byte-Based Tokenizer (14% faster)

The original tokenizer used Swift's `String.Index` for character iteration, which requires O(n) random access due to Unicode grapheme cluster handling.

```
UTF-8 byte iteration:     0.79 ms/pass
String.Index advancement: 4.76 ms/pass (6.0x slower)
Character iteration:      8.19 ms/pass (10.4x slower)
```

Converting to `ContiguousArray<UInt8>` for direct byte-level access provided significant speedup.

#### 2. Batch Text Insertion (30% faster)

The tree builder was creating a new text node for every character token. The optimization coalesces consecutive character tokens before insertion and appends to existing text nodes when possible.

#### 3. Static Set Constants (6% faster)

Tag name lookups used inline array literals (`["td", "th", "tr"].contains(name)`), creating temporary arrays on every call. Defined module-level `Set<String>` constants for O(1) lookup.

#### 4. Batch Tag/Attribute Scanning (26% faster)

Tag names and attributes were being built character-by-character. Implemented batch scanning to find the end of names and extract the entire name in one operation.

#### 5. Inline Arrays to Module-Level Sets (17% faster)

Profiling revealed remaining inline array literals in `processStartTagInBody` that were being created on every tag. Converting these to static sets closed the gap with JavaScript.

### Optimizations That Did NOT Help

- **Pre-computing TagID in Token Enum** - 3% slower due to overhead
- **Set<TagID> vs Set<String>** - Negligible impact (Swift's Set<String> is highly optimized)
- **Fast Path for Common Entities** - Caused 23 test failures due to edge cases
- **Dictionary removeAll(keepingCapacity:)** - 5% slower for small dictionaries

### Key Lessons Learned

1. **Measure before optimizing** - Many "obvious" optimizations actually hurt performance
2. **Trust the compiler** - Swift's optimizer is sophisticated; hand-crafted fast paths often add overhead
3. **Profile real workloads** - Micro-benchmarks can be misleading
4. **Know when to stop** - The remaining overhead is fundamental to the HTML5 algorithm

## Performance Characteristics

### Scaling Behavior

The parser exhibits linear O(n) scaling with input size. Time per KB is consistent (~0.04ms/KB) across all file sizes.

| Input Size | Parse Time | Time/KB |
|------------|------------|---------|
| 7.9 KB | 1.73 ms | 0.219 ms/KB |
| 79.1 KB | 11.17 ms | 0.141 ms/KB |
| 799.8 KB | 104.30 ms | 0.130 ms/KB |

Time per KB actually improves with larger documents due to better cache utilization.

### Why JavaScript is Competitive

V8 JavaScript benefits from:
- JIT compilation with hot-path optimization
- UTF-16 strings with O(1) character access
- Inline caching for property access
- Generational garbage collection (batch deallocation vs ARC per-object counting)

Swift's remaining overhead is primarily:
- ARC atomic operations on every node
- UTF-8 string safety checks
- Lack of runtime hot-path optimization

## See Also

- <doc:Benchmarking>
- [Optimization History](https://github.com/kylehowells/swift-justhtml/blob/master/notes/05-OptimizationHistory.md)
- [Performance Profile](https://github.com/kylehowells/swift-justhtml/blob/master/notes/06-PerformanceProfile.md)

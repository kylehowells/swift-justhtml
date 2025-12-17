# Benchmarking

Testing and benchmarking methodology for swift-justhtml.

## Overview

Swift-justhtml includes comprehensive benchmarking infrastructure to measure parse time, memory usage, and compare performance against Python (justhtml) and JavaScript (justjshtml) implementations.

## Benchmark Suite

### Test Files

The benchmark suite uses real-world HTML files to ensure realistic performance measurements:

| File | Source | Size | Characteristics |
|------|--------|------|-----------------|
| hackernews.html | Hacker News | 34 KB | Simple structure, minimal nesting |
| wikipedia_countries.html | Wikipedia | 360 KB | Large tables, moderate entities |
| wikipedia_html.html | Wikipedia | 472 KB | Dense links, many attributes |
| wikipedia_swift.html | Wikipedia | 411 KB | Code blocks, technical content |
| wikipedia_ww2.html | Wikipedia | 1,204 KB | Large document, 9,000+ entities |
| synthetic.html | Generated | ~20 MB | Stress test with all HTML features |

The synthetic file is generated using `Benchmarks/generate_synthetic.py` and includes:
- Deeply nested elements
- Many attributes per element
- HTML entities
- Large tables
- Nested lists
- Comments
- Forms with various input types

### Benchmark Scripts

#### Performance Comparison (`compare.py`)

Runs all three implementations and generates a comparison report:

```bash
cd Benchmarks
python3 compare.py
```

This:
1. Downloads sample HTML files if not present
2. Builds Swift in release mode
3. Runs Swift, Python, and JavaScript benchmarks
4. Compares output for consistency
5. Generates `BENCHMARK_RESULTS.md`

#### Memory Comparison (`memory_compare.py`)

Measures peak memory usage (RSS) for each implementation:

```bash
cd Benchmarks
python3 memory_compare.py
```

This:
1. Creates temporary test scripts for each implementation
2. Measures peak RSS using `/usr/bin/time -v` (Linux) or `/usr/bin/time -l` (macOS)
3. Generates `MEMORY_RESULTS.md`

## Methodology

### Parse Time Measurement

- **Build Configuration:** Release mode (`swift build -c release`)
- **Warmup:** 2-3 iterations discarded before measurement
- **Iterations:** Varies by file size:
  - Files > 5MB: 3 iterations
  - Files > 500KB: 10 iterations
  - Files > 100KB: 25 iterations
  - Smaller files: 50 iterations
- **Timing:** `Date()` / `clock_gettime(CLOCK_MONOTONIC)` / `performance.now()`
- **Metric:** Average time across iterations

### Memory Measurement

- **Metric:** Peak Resident Set Size (RSS)
- **Method:** External process measurement via `/usr/bin/time`
- **Note:** Includes shared libraries and may vary between runs

### Output Verification

All implementations output a normalized tree format for comparison:

```
<html>
  <head>
  </head>
  <body>
    <p>
      "Hello, World!"
    </p>
  </body>
</html>
```

This ensures all parsers produce identical DOM trees from the same input.

## Running Profiling Tests

### Swift Profiling Tests

The profiling test suite is in `Tests/swift-justhtmlTests/ProfilingTests.swift`:

```bash
# Run all profiling tests
swift test --filter Profiling -c release

# Run specific test
swift test --filter testOverallTiming -c release
```

### Available Profiling Tests

| Test | Purpose |
|------|---------|
| `testOverallTiming` | Measures total parse time per file |
| `testTokenizerVsTreeBuilder` | Component breakdown |
| `testTokenizerContentTypes` | Throughput by content type |
| `testTreeBuilderOperationCosts` | Tree builder operation timing |
| `testNodeOperationCosts` | Micro-benchmarks for node operations |
| `testScaling` | Linear scaling verification |
| `testEntityDecodingOverhead` | Entity processing cost |

## Generating Reports

### Benchmark Results

```bash
cd Benchmarks
python3 compare.py
# Creates BENCHMARK_RESULTS.md
```

### Memory Results

```bash
cd Benchmarks
python3 memory_compare.py
# Creates MEMORY_RESULTS.md
```

### Synthetic Test File

```bash
cd Benchmarks
python3 generate_synthetic.py
# Creates test_files/synthetic.html (~20MB)
```

## Interpreting Results

### Parse Time

- **Throughput (MB/s):** Higher is better; expect 15-30 MB/s
- **Time per KB:** Should be consistent (~0.04 ms/KB) indicating linear scaling
- **Comparison ratios:** Swift should match or beat JavaScript

### Memory Usage

- **Peak RSS:** Lower is better
- **Memory/input ratio:** Typically 2-3x the input size
- **Comparison:** Swift uses ~2x less memory than JavaScript

### Output Consistency

All three implementations should produce identical output. Mismatches indicate parser bugs that should be investigated.

## Continuous Benchmarking

To track performance over time:

1. Run `compare.py` and `memory_compare.py` after significant changes
2. Commit the updated `BENCHMARK_RESULTS.md` and `MEMORY_RESULTS.md`
3. Review the git history to track performance trends

## See Also

- <doc:Performance>
- [Benchmarks/BENCHMARK_RESULTS.md](https://github.com/kylehowells/swift-justhtml/blob/master/Benchmarks/BENCHMARK_RESULTS.md)
- [Benchmarks/MEMORY_RESULTS.md](https://github.com/kylehowells/swift-justhtml/blob/master/Benchmarks/MEMORY_RESULTS.md)

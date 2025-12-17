# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 01:59:11

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `ac9b364474d5` | 2025-12-17 |
| justhtml (Python) | main | `63c29b26be64` | 2025-12-16 |
| justjshtml (JavaScript) | main | `e29dbd3166e9` | 2025-12-16 |

## Output Consistency

All implementations produce **identical output** for all test files.

| File | Status |
|------|--------|
| hackernews.html | ✅ OK |
| wikipedia_countries.html | ✅ OK |
| wikipedia_html.html | ✅ OK |
| wikipedia_swift.html | ✅ OK |
| wikipedia_ww2.html | ✅ OK |

## Performance Comparison

| File | Size | Swift | Python | JavaScript | Swift vs Python | Swift vs JS |
|------|------|-------|--------|------------|-----------------|-------------|
| hackernews.html | 34 KB | 3.93 ms | 7.85 ms | 1.62 ms | 2.00x faster | 2.43x slower |
| wikipedia_countries.html | 360 KB | 40.77 ms | 61.92 ms | 15.42 ms | 1.52x faster | 2.64x slower |
| wikipedia_html.html | 472 KB | 60.37 ms | 79.90 ms | 19.49 ms | 1.32x faster | 3.10x slower |
| wikipedia_swift.html | 411 KB | 50.90 ms | 67.56 ms | 17.17 ms | 1.33x faster | 2.96x slower |
| wikipedia_ww2.html | 1204 KB | 140.95 ms | 179.76 ms | 46.29 ms | 1.28x faster | 3.04x slower |
| **TOTAL** | | **297 ms** | **397 ms** | **100 ms** | **1.34x faster** | **2.97x slower** |

## Summary

- **Swift** total parse time: 297 ms
- **Python** total parse time: 397 ms
- **JavaScript** total parse time: 100 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **1.3x faster** than Python.
JavaScript is **3.0x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 09:41:38

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `887bea9baf42` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.26 ms | 7.88 ms | 1.97 ms | 2.42x faster | 1.66x slower |
| wikipedia_countries.html | 360 KB | 26.85 ms | 64.62 ms | 15.78 ms | 2.41x faster | 1.70x slower |
| wikipedia_html.html | 472 KB | 35.63 ms | 82.99 ms | 20.50 ms | 2.33x faster | 1.74x slower |
| wikipedia_swift.html | 411 KB | 31.35 ms | 68.61 ms | 17.63 ms | 2.19x faster | 1.78x slower |
| wikipedia_ww2.html | 1204 KB | 84.45 ms | 182.65 ms | 47.68 ms | 2.16x faster | 1.77x slower |
| **TOTAL** | | **182 ms** | **407 ms** | **104 ms** | **2.24x faster** | **1.75x slower** |

## Summary

- **Swift** total parse time: 182 ms
- **Python** total parse time: 407 ms
- **JavaScript** total parse time: 104 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **2.2x faster** than Python.
JavaScript is **1.8x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

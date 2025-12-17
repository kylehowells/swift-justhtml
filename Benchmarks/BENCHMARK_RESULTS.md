# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 09:56:16

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `2719d8a6212a` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.09 ms | 7.96 ms | 1.85 ms | 2.58x faster | 1.67x slower |
| wikipedia_countries.html | 360 KB | 26.08 ms | 64.62 ms | 15.51 ms | 2.48x faster | 1.68x slower |
| wikipedia_html.html | 472 KB | 35.32 ms | 82.70 ms | 20.85 ms | 2.34x faster | 1.69x slower |
| wikipedia_swift.html | 411 KB | 30.97 ms | 69.86 ms | 17.79 ms | 2.26x faster | 1.74x slower |
| wikipedia_ww2.html | 1204 KB | 82.38 ms | 186.29 ms | 50.47 ms | 2.26x faster | 1.63x slower |
| **TOTAL** | | **178 ms** | **411 ms** | **106 ms** | **2.31x faster** | **1.67x slower** |

## Summary

- **Swift** total parse time: 178 ms
- **Python** total parse time: 411 ms
- **JavaScript** total parse time: 106 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **2.3x faster** than Python.
JavaScript is **1.7x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

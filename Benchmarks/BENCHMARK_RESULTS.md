# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 13:01:41

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `33be1052b504` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.00 ms | 7.72 ms | 1.61 ms | 2.57x faster | 1.86x slower |
| wikipedia_countries.html | 360 KB | 23.30 ms | 61.73 ms | 14.78 ms | 2.65x faster | 1.58x slower |
| wikipedia_html.html | 472 KB | 30.66 ms | 79.60 ms | 19.11 ms | 2.60x faster | 1.60x slower |
| wikipedia_swift.html | 411 KB | 28.07 ms | 67.04 ms | 16.75 ms | 2.39x faster | 1.68x slower |
| wikipedia_ww2.html | 1204 KB | 73.51 ms | 179.92 ms | 45.72 ms | 2.45x faster | 1.61x slower |
| **TOTAL** | | **159 ms** | **396 ms** | **98 ms** | **2.50x faster** | **1.62x slower** |

## Summary

- **Swift** total parse time: 159 ms
- **Python** total parse time: 396 ms
- **JavaScript** total parse time: 98 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **2.5x faster** than Python.
JavaScript is **1.6x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

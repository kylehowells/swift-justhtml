# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 10:06:50

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `43f265b8bf40` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.25 ms | 7.97 ms | 1.75 ms | 2.45x faster | 1.85x slower |
| wikipedia_countries.html | 360 KB | 25.59 ms | 63.85 ms | 15.29 ms | 2.50x faster | 1.67x slower |
| wikipedia_html.html | 472 KB | 34.10 ms | 82.38 ms | 20.67 ms | 2.42x faster | 1.65x slower |
| wikipedia_swift.html | 411 KB | 30.17 ms | 69.57 ms | 17.28 ms | 2.31x faster | 1.75x slower |
| wikipedia_ww2.html | 1204 KB | 80.27 ms | 186.43 ms | 49.81 ms | 2.32x faster | 1.61x slower |
| **TOTAL** | | **173 ms** | **410 ms** | **105 ms** | **2.37x faster** | **1.65x slower** |

## Summary

- **Swift** total parse time: 173 ms
- **Python** total parse time: 410 ms
- **JavaScript** total parse time: 105 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **2.4x faster** than Python.
JavaScript is **1.7x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

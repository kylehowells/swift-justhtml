# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 11:58:26

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `9885cbaaaa46` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.09 ms | 7.65 ms | 1.69 ms | 2.47x faster | 1.83x slower |
| wikipedia_countries.html | 360 KB | 25.41 ms | 62.15 ms | 14.47 ms | 2.45x faster | 1.76x slower |
| wikipedia_html.html | 472 KB | 33.38 ms | 79.97 ms | 19.74 ms | 2.40x faster | 1.69x slower |
| wikipedia_swift.html | 411 KB | 29.79 ms | 66.88 ms | 16.51 ms | 2.24x faster | 1.80x slower |
| wikipedia_ww2.html | 1204 KB | 79.15 ms | 181.38 ms | 46.74 ms | 2.29x faster | 1.69x slower |
| **TOTAL** | | **171 ms** | **398 ms** | **99 ms** | **2.33x faster** | **1.72x slower** |

## Summary

- **Swift** total parse time: 171 ms
- **Python** total parse time: 398 ms
- **JavaScript** total parse time: 99 ms

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

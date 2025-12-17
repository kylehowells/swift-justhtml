# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 18:39:43

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `76fee4992b72` | 2025-12-17 |
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
| hackernews.html | 34 KB | 2.09 ms | 7.65 ms | 1.59 ms | 3.67x faster | 1.31x slower |
| wikipedia_countries.html | 360 KB | 14.61 ms | 62.27 ms | 14.60 ms | 4.26x faster | 1.00x slower |
| wikipedia_html.html | 472 KB | 18.81 ms | 79.89 ms | 19.65 ms | 4.25x faster | 1.04x faster |
| wikipedia_swift.html | 411 KB | 16.96 ms | 67.02 ms | 16.96 ms | 3.95x faster | 1.00x faster |
| wikipedia_ww2.html | 1204 KB | 44.02 ms | 181.64 ms | 46.39 ms | 4.13x faster | 1.05x faster |
| **TOTAL** | | **96 ms** | **398 ms** | **99 ms** | **4.13x faster** | **1.03x faster** |

## Summary

- **Swift** total parse time: 96 ms
- **Python** total parse time: 398 ms
- **JavaScript** total parse time: 99 ms

**Swift** is the fastest implementation.

Swift is **4.1x faster** than Python.
JavaScript is **1.0x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

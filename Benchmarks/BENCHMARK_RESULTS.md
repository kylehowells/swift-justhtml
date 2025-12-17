# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 15:29:30

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `d4e1c0049aae` | 2025-12-17 |
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
| hackernews.html | 34 KB | 2.05 ms | 7.77 ms | 1.68 ms | 3.78x faster | 1.23x slower |
| wikipedia_countries.html | 360 KB | 14.55 ms | 62.29 ms | 14.58 ms | 4.28x faster | 1.00x faster |
| wikipedia_html.html | 472 KB | 18.50 ms | 79.98 ms | 19.42 ms | 4.32x faster | 1.05x faster |
| wikipedia_swift.html | 411 KB | 17.25 ms | 67.29 ms | 16.49 ms | 3.90x faster | 1.05x slower |
| wikipedia_ww2.html | 1204 KB | 44.83 ms | 181.37 ms | 47.81 ms | 4.05x faster | 1.07x faster |
| **TOTAL** | | **97 ms** | **399 ms** | **100 ms** | **4.10x faster** | **1.03x faster** |

## Summary

- **Swift** total parse time: 97 ms
- **Python** total parse time: 399 ms
- **JavaScript** total parse time: 100 ms

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

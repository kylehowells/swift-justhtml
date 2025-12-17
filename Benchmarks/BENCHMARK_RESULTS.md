# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 14:39:16

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `e339f3e8de90` | 2025-12-17 |
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
| hackernews.html | 34 KB | 2.10 ms | 7.77 ms | 1.59 ms | 3.70x faster | 1.32x slower |
| wikipedia_countries.html | 360 KB | 14.65 ms | 61.77 ms | 15.03 ms | 4.22x faster | 1.03x faster |
| wikipedia_html.html | 472 KB | 19.21 ms | 79.44 ms | 19.41 ms | 4.13x faster | 1.01x faster |
| wikipedia_swift.html | 411 KB | 17.47 ms | 68.06 ms | 16.95 ms | 3.90x faster | 1.03x slower |
| wikipedia_ww2.html | 1204 KB | 44.34 ms | 180.69 ms | 45.20 ms | 4.07x faster | 1.02x faster |
| **TOTAL** | | **98 ms** | **398 ms** | **98 ms** | **4.07x faster** | **1.00x faster** |

## Summary

- **Swift** total parse time: 98 ms
- **Python** total parse time: 398 ms
- **JavaScript** total parse time: 98 ms

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

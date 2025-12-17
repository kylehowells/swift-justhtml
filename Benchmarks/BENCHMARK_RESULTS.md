# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 09:33:38

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `62313f749b5e` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.28 ms | 7.98 ms | 1.76 ms | 2.43x faster | 1.86x slower |
| wikipedia_countries.html | 360 KB | 35.90 ms | 63.44 ms | 15.63 ms | 1.77x faster | 2.30x slower |
| wikipedia_html.html | 472 KB | 54.30 ms | 81.91 ms | 20.24 ms | 1.51x faster | 2.68x slower |
| wikipedia_swift.html | 411 KB | 45.47 ms | 69.34 ms | 17.41 ms | 1.52x faster | 2.61x slower |
| wikipedia_ww2.html | 1204 KB | 121.85 ms | 187.00 ms | 48.51 ms | 1.53x faster | 2.51x slower |
| **TOTAL** | | **261 ms** | **410 ms** | **104 ms** | **1.57x faster** | **2.52x slower** |

## Summary

- **Swift** total parse time: 261 ms
- **Python** total parse time: 410 ms
- **JavaScript** total parse time: 104 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **1.6x faster** than Python.
JavaScript is **2.5x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

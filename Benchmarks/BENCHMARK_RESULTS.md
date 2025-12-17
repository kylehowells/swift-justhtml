# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 09:48:47

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `c61748d285a9` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.03 ms | 7.83 ms | 1.96 ms | 2.58x faster | 1.54x slower |
| wikipedia_countries.html | 360 KB | 24.95 ms | 62.77 ms | 15.59 ms | 2.52x faster | 1.60x slower |
| wikipedia_html.html | 472 KB | 33.74 ms | 84.15 ms | 20.72 ms | 2.49x faster | 1.63x slower |
| wikipedia_swift.html | 411 KB | 30.74 ms | 70.66 ms | 17.23 ms | 2.30x faster | 1.78x slower |
| wikipedia_ww2.html | 1204 KB | 79.41 ms | 184.47 ms | 49.89 ms | 2.32x faster | 1.59x slower |
| **TOTAL** | | **172 ms** | **410 ms** | **105 ms** | **2.38x faster** | **1.63x slower** |

## Summary

- **Swift** total parse time: 172 ms
- **Python** total parse time: 410 ms
- **JavaScript** total parse time: 105 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **2.4x faster** than Python.
JavaScript is **1.6x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

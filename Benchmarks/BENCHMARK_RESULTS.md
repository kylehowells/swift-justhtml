# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 13:30:48

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `717c19b02c44` | 2025-12-17 |
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
| hackernews.html | 34 KB | 2.58 ms | 7.75 ms | 1.65 ms | 3.00x faster | 1.56x slower |
| wikipedia_countries.html | 360 KB | 16.93 ms | 62.27 ms | 15.04 ms | 3.68x faster | 1.13x slower |
| wikipedia_html.html | 472 KB | 23.16 ms | 79.52 ms | 19.32 ms | 3.43x faster | 1.20x slower |
| wikipedia_swift.html | 411 KB | 21.03 ms | 67.43 ms | 16.89 ms | 3.21x faster | 1.25x slower |
| wikipedia_ww2.html | 1204 KB | 53.38 ms | 181.94 ms | 45.95 ms | 3.41x faster | 1.16x slower |
| **TOTAL** | | **117 ms** | **399 ms** | **99 ms** | **3.41x faster** | **1.18x slower** |

## Summary

- **Swift** total parse time: 117 ms
- **Python** total parse time: 399 ms
- **JavaScript** total parse time: 99 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **3.4x faster** than Python.
JavaScript is **1.2x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

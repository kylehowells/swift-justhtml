# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 13:12:35

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `492431c10699` | 2025-12-17 |
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
| hackernews.html | 34 KB | 2.43 ms | 7.74 ms | 1.67 ms | 3.19x faster | 1.46x slower |
| wikipedia_countries.html | 360 KB | 17.08 ms | 62.28 ms | 15.23 ms | 3.65x faster | 1.12x slower |
| wikipedia_html.html | 472 KB | 23.55 ms | 79.97 ms | 19.45 ms | 3.40x faster | 1.21x slower |
| wikipedia_swift.html | 411 KB | 21.50 ms | 67.93 ms | 17.15 ms | 3.16x faster | 1.25x slower |
| wikipedia_ww2.html | 1204 KB | 53.66 ms | 180.26 ms | 45.95 ms | 3.36x faster | 1.17x slower |
| **TOTAL** | | **118 ms** | **398 ms** | **99 ms** | **3.37x faster** | **1.19x slower** |

## Summary

- **Swift** total parse time: 118 ms
- **Python** total parse time: 398 ms
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

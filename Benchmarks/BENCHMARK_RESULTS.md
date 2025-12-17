# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 11:41:01

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `9885cbaaaa46` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.06 ms | 7.71 ms | 1.63 ms | 2.52x faster | 1.88x slower |
| wikipedia_countries.html | 360 KB | 24.59 ms | 61.62 ms | 15.74 ms | 2.51x faster | 1.56x slower |
| wikipedia_html.html | 472 KB | 32.71 ms | 79.18 ms | 19.41 ms | 2.42x faster | 1.68x slower |
| wikipedia_swift.html | 411 KB | 29.21 ms | 66.72 ms | 17.35 ms | 2.28x faster | 1.68x slower |
| wikipedia_ww2.html | 1204 KB | 78.16 ms | 179.32 ms | 46.56 ms | 2.29x faster | 1.68x slower |
| **TOTAL** | | **168 ms** | **395 ms** | **101 ms** | **2.35x faster** | **1.67x slower** |

## Summary

- **Swift** total parse time: 168 ms
- **Python** total parse time: 395 ms
- **JavaScript** total parse time: 101 ms

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

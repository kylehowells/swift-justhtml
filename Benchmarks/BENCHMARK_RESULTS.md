# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 08:16:23

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `ddc0af112c4b` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.96 ms | 7.92 ms | 1.83 ms | 2.00x faster | 2.16x slower |
| wikipedia_countries.html | 360 KB | 42.27 ms | 64.13 ms | 16.73 ms | 1.52x faster | 2.53x slower |
| wikipedia_html.html | 472 KB | 62.09 ms | 84.41 ms | 20.99 ms | 1.36x faster | 2.96x slower |
| wikipedia_swift.html | 411 KB | 52.85 ms | 71.12 ms | 18.64 ms | 1.35x faster | 2.84x slower |
| wikipedia_ww2.html | 1204 KB | 147.13 ms | 189.05 ms | 49.32 ms | 1.28x faster | 2.98x slower |
| **TOTAL** | | **308 ms** | **417 ms** | **108 ms** | **1.35x faster** | **2.87x slower** |

## Summary

- **Swift** total parse time: 308 ms
- **Python** total parse time: 417 ms
- **JavaScript** total parse time: 108 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **1.4x faster** than Python.
JavaScript is **2.9x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

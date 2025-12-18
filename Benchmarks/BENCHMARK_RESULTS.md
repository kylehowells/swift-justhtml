# Cross-Implementation Benchmark Results

**Generated:** 2025-12-18 08:25:27

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `0d8b61ecd58e` | 2025-12-18 |
| justhtml (Python) | main | `63c29b26be64` | 2025-12-16 |
| justjshtml (JavaScript) | main | `e29dbd3166e9` | 2025-12-16 |

## Output Consistency

All implementations produce **identical output** for all test files.

| File | Status |
|------|--------|
| hackernews.html | ✅ OK |
| synthetic.html | ✅ OK |
| wikipedia_countries.html | ✅ OK |
| wikipedia_html.html | ✅ OK |
| wikipedia_swift.html | ✅ OK |
| wikipedia_ww2.html | ✅ OK |

## Performance Comparison

| File | Size | Swift | Python | JavaScript | Swift vs Python | Swift vs JS |
|------|------|-------|--------|------------|-----------------|-------------|
| hackernews.html | 34 KB | 2.12 ms | 7.79 ms | 1.71 ms | 3.68x faster | 1.24x slower |
| synthetic.html | 20498 KB | 1221.96 ms | 3595.00 ms | 933.79 ms | 2.94x faster | 1.31x slower |
| wikipedia_countries.html | 360 KB | 14.27 ms | 90.08 ms | 14.99 ms | 6.31x faster | 1.05x faster |
| wikipedia_html.html | 472 KB | 18.89 ms | 104.40 ms | 20.56 ms | 5.53x faster | 1.09x faster |
| wikipedia_swift.html | 411 KB | 16.98 ms | 132.85 ms | 16.54 ms | 7.82x faster | 1.03x slower |
| wikipedia_ww2.html | 1204 KB | 44.00 ms | 238.61 ms | 47.92 ms | 5.42x faster | 1.09x faster |
| **TOTAL** | | **1318 ms** | **4169 ms** | **1036 ms** | **3.16x faster** | **1.27x slower** |

## Summary

- **Swift** total parse time: 1318 ms
- **Python** total parse time: 4169 ms
- **JavaScript** total parse time: 1036 ms

**JavaScript** is the fastest implementation (V8 JIT optimization).

Swift is **3.2x faster** than Python.
JavaScript is **1.3x faster** than Swift.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| synthetic.html | Generated (stress test) | 20,990,426 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

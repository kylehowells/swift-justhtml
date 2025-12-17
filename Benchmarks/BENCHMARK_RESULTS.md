# Cross-Implementation Benchmark Results

**Generated:** 2025-12-17 10:01:01

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | turbo | `83ce217a1114` | 2025-12-17 |
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
| hackernews.html | 34 KB | 3.13 ms | 7.86 ms | 2.15 ms | 2.51x faster | 1.46x slower |
| wikipedia_countries.html | 360 KB | 25.53 ms | 63.78 ms | 15.83 ms | 2.50x faster | 1.61x slower |
| wikipedia_html.html | 472 KB | 33.67 ms | 82.93 ms | 20.83 ms | 2.46x faster | 1.62x slower |
| wikipedia_swift.html | 411 KB | 30.30 ms | 70.32 ms | 17.75 ms | 2.32x faster | 1.71x slower |
| wikipedia_ww2.html | 1204 KB | 80.19 ms | 182.19 ms | 48.95 ms | 2.27x faster | 1.64x slower |
| **TOTAL** | | **173 ms** | **407 ms** | **106 ms** | **2.36x faster** | **1.64x slower** |

## Summary

- **Swift** total parse time: 173 ms
- **Python** total parse time: 407 ms
- **JavaScript** total parse time: 106 ms

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

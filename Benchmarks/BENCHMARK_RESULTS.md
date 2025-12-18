# Cross-Implementation Benchmark Results

**Generated:** 2025-12-18 09:45:09

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `ed2401f881f9` | 2025-12-18 |
| justhtml (Python) | main | `63c29b26be64` | 2025-12-16 |
| justjshtml (JavaScript) | main | `e29dbd3166e9` | 2025-12-16 |
| html5ever (Rust) | main | `795caf4166a8` | 2025-12-05 |

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

| File | Size | Rust | Swift | JavaScript | Python | Rust vs Swift |
|------|------|------|-------|------------|--------|---------------|
| hackernews.html | 34 KB | 0.51 ms | 2.05 ms | 1.80 ms | 7.68 ms | 4.06x faster |
| synthetic.html | 20498 KB | 275.14 ms | 1217.81 ms | 934.22 ms | 3612.26 ms | 4.43x faster |
| wikipedia_countries.html | 360 KB | 4.09 ms | 14.23 ms | 15.37 ms | 90.21 ms | 3.48x faster |
| wikipedia_html.html | 472 KB | 5.23 ms | 18.83 ms | 19.98 ms | 104.87 ms | 3.60x faster |
| wikipedia_swift.html | 411 KB | 4.58 ms | 16.92 ms | 16.42 ms | 133.16 ms | 3.69x faster |
| wikipedia_ww2.html | 1204 KB | 13.26 ms | 43.56 ms | 47.36 ms | 240.67 ms | 3.28x faster |
| **TOTAL** | | **303 ms** | **1313 ms** | **1035 ms** | **4189 ms** | **4.34x faster** |

## Summary

- **Rust (html5ever)** total parse time: 303 ms
- **Swift** total parse time: 1313 ms
- **JavaScript** total parse time: 1035 ms
- **Python** total parse time: 4189 ms

**Rust (html5ever)** is the fastest implementation.

Rust is **4.3x faster** than Swift.
Rust is **3.4x faster** than JavaScript.
Rust is **13.8x faster** than Python.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| synthetic.html | Generated (stress test) | 20,990,426 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

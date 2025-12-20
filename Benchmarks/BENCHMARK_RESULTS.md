# Cross-Implementation Benchmark Results

**Generated:** 2025-12-20 08:25:39

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `8a175066b4d9` | 2025-12-19 |
| justhtml (Python) | main | `63c29b26be64` | 2025-12-16 |
| justjshtml (JavaScript) | main | `e29dbd3166e9` | 2025-12-16 |
| html5ever (Rust) | main | `795caf4166a8` | 2025-12-05 |
| rust-justhtml | master | `7956af8c95fa` | 2025-12-19 |

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

| File | Size | html5ever | rust-justhtml | Swift | JavaScript | Python |
|------|------|-----------|---------------|-------|------------|--------|
| hackernews.html | 34 KB | 0.49 ms | 0.82 ms | 2.07 ms | 1.78 ms | 7.75 ms |
| synthetic.html | 20498 KB | 277.46 ms | N/A | 1218.07 ms | 911.40 ms | 3598.33 ms |
| wikipedia_countries.html | 360 KB | 3.95 ms | 7.29 ms | 14.27 ms | 15.29 ms | 90.98 ms |
| wikipedia_html.html | 472 KB | 5.19 ms | 10.89 ms | 19.04 ms | 21.49 ms | 104.24 ms |
| wikipedia_swift.html | 411 KB | 4.55 ms | 9.70 ms | 16.96 ms | 16.40 ms | 133.33 ms |
| wikipedia_ww2.html | 1204 KB | 12.62 ms | 24.61 ms | 43.82 ms | 46.10 ms | 240.23 ms |
| **TOTAL** | | **304 ms** | **53 ms** | **1314 ms** | **1012 ms** | **4175 ms** |

## Summary

- **Rust (html5ever)** total parse time: 304 ms
- **rust-justhtml** total parse time: 53 ms
- **Swift** total parse time: 1314 ms
- **JavaScript** total parse time: 1012 ms
- **Python** total parse time: 4175 ms

**rust-justhtml** is the fastest implementation.

html5ever is **4.3x faster** than Swift.
html5ever is **0.2x faster** than rust-justhtml.
html5ever is **3.3x faster** than JavaScript.
html5ever is **13.7x faster** than Python.
rust-justhtml is **24.6x faster** than Swift.
rust-justhtml is **78.3x faster** than Python.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| synthetic.html | Generated (stress test) | 20,990,426 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

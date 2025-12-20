# Cross-Implementation Benchmark Results

**Generated:** 2025-12-20 08:43:16

## Repository Versions

| Project | Branch | Commit | Date |
|---------|--------|--------|------|
| swift-justhtml | master | `95140a64878b` | 2025-12-20 |
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
| hackernews.html | 34 KB | 0.51 ms | 0.82 ms | 2.09 ms | 1.86 ms | 7.71 ms |
| synthetic.html | 20498 KB | 274.73 ms | 642.55 ms | 1222.32 ms | 1083.18 ms | 3619.55 ms |
| wikipedia_countries.html | 360 KB | 4.19 ms | 7.67 ms | 14.27 ms | 19.23 ms | 90.88 ms |
| wikipedia_html.html | 472 KB | 5.41 ms | 10.81 ms | 18.93 ms | 25.03 ms | 105.46 ms |
| wikipedia_swift.html | 411 KB | 4.61 ms | 8.98 ms | 17.23 ms | 19.89 ms | 133.11 ms |
| wikipedia_ww2.html | 1204 KB | 12.64 ms | 25.14 ms | 43.78 ms | 57.04 ms | 240.39 ms |
| **TOTAL** | | **302 ms** | **696 ms** | **1319 ms** | **1206 ms** | **4197 ms** |

## Summary

- **Rust (html5ever)** total parse time: 302 ms
- **rust-justhtml** total parse time: 696 ms
- **Swift** total parse time: 1319 ms
- **JavaScript** total parse time: 1206 ms
- **Python** total parse time: 4197 ms

**html5ever** is the fastest implementation.

html5ever is **4.4x faster** than Swift.
html5ever is **2.3x faster** than rust-justhtml.
html5ever is **4.0x faster** than JavaScript.
html5ever is **13.9x faster** than Python.
rust-justhtml is **1.9x faster** than Swift.
rust-justhtml is **6.0x faster** than Python.

## Test Files

| File | Source | Size |
|------|--------|------|
| hackernews.html | Hacker News | 34,478 bytes |
| synthetic.html | Generated (stress test) | 20,990,426 bytes |
| wikipedia_countries.html | Wikipedia | 369,101 bytes |
| wikipedia_html.html | Wikipedia | 483,786 bytes |
| wikipedia_swift.html | Wikipedia | 420,395 bytes |
| wikipedia_ww2.html | Wikipedia | 1,232,920 bytes |

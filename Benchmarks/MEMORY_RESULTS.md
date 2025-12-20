# Memory Usage Comparison

**Generated:** 2025-12-20 08:28:29

## Repository Versions

| Project | Commit |
|---------|--------|
| swift-justhtml | `8a175066b4d9` |
| justhtml (Python) | `63c29b26be64` |
| justjshtml (JavaScript) | `e29dbd3166e9` |
| html5ever (Rust) | `795caf4166a8` |
| rust-justhtml | `7956af8c95fa` |

## Peak Memory Usage (RSS)

| File | Size | html5ever | rust-justhtml | Swift | JavaScript | Python |
|------|------|-----------|---------------|-------|------------|--------|
| hackernews.html | 33.67 KB | 3.32 MB | 4.26 MB | 19.83 MB | 58.35 MB | 14.80 MB |
| synthetic.html | 20.02 MB | 216.38 MB | 792.37 MB | 475.37 MB | 869.07 MB | 505.92 MB |
| wikipedia_countries.html | 360.45 KB | 6.13 MB | 15.92 MB | 26.47 MB | 88.44 MB | 23.01 MB |
| wikipedia_html.html | 472.45 KB | 6.82 MB | 20.23 MB | 28.05 MB | 92.59 MB | 25.15 MB |
| wikipedia_swift.html | 410.54 KB | 6.69 MB | 18.62 MB | 27.09 MB | 90.66 MB | 24.53 MB |
| wikipedia_ww2.html | 1.18 MB | 12.53 MB | 40.86 MB | 40.21 MB | 156.39 MB | 42.66 MB |

## Summary

Average peak memory usage across 6 files:

- **html5ever (Rust)**: 41.98 MB
- **rust-justhtml**: 148.71 MB
- **Swift**: 102.84 MB
- **JavaScript**: 225.92 MB
- **Python**: 106.01 MB

html5ever uses **3.54x less memory** than rust-justhtml on average.
html5ever uses **2.45x less memory** than Swift on average.
html5ever uses **5.38x less memory** than JavaScript on average.
html5ever uses **2.53x less memory** than Python on average.
rust-justhtml uses **0.69x less memory** than Swift on average.
rust-justhtml uses **0.71x less memory** than Python on average.

*Note: Memory measurements are peak RSS (Resident Set Size) which includes shared libraries and may vary between runs.*

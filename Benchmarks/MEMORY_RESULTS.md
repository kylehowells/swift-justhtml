# Memory Usage Comparison

**Generated:** 2025-12-20 09:00:18

## Repository Versions

| Project | Commit |
|---------|--------|
| swift-justhtml | `958875a09c18` |
| justhtml (Python) | `63c29b26be64` |
| justjshtml (JavaScript) | `e29dbd3166e9` |
| html5ever (Rust) | `795caf4166a8` |
| rust-justhtml | `23099eba0d7c` |

## Peak Memory Usage (RSS)

| File | Size | html5ever | rust-justhtml | Swift | JavaScript | Python |
|------|------|-----------|---------------|-------|------------|--------|
| hackernews.html | 33.67 KB | 3.21 MB | 4.06 MB | 19.94 MB | 59.03 MB | 14.88 MB |
| synthetic.html | 20.02 MB | 216.25 MB | 792.31 MB | 475.26 MB | 870.23 MB | 505.49 MB |
| wikipedia_countries.html | 360.45 KB | 6.00 MB | 15.88 MB | 26.30 MB | 90.88 MB | 22.93 MB |
| wikipedia_html.html | 472.45 KB | 7.00 MB | 19.99 MB | 28.24 MB | 93.24 MB | 25.22 MB |
| wikipedia_swift.html | 410.54 KB | 6.44 MB | 18.61 MB | 26.52 MB | 88.90 MB | 24.48 MB |
| wikipedia_ww2.html | 1.18 MB | 12.46 MB | 40.98 MB | 40.21 MB | 155.52 MB | 42.41 MB |

## Summary

Average peak memory usage across 6 files:

- **html5ever (Rust)**: 41.90 MB
- **rust-justhtml**: 148.64 MB
- **Swift**: 102.75 MB
- **JavaScript**: 226.30 MB
- **Python**: 105.90 MB

html5ever uses **3.55x less memory** than rust-justhtml on average.
html5ever uses **2.45x less memory** than Swift on average.
html5ever uses **5.40x less memory** than JavaScript on average.
html5ever uses **2.53x less memory** than Python on average.
rust-justhtml uses **0.69x less memory** than Swift on average.
rust-justhtml uses **0.71x less memory** than Python on average.

*Note: Memory measurements are peak RSS (Resident Set Size) which includes shared libraries and may vary between runs.*

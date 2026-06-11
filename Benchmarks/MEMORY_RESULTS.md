# Memory Usage Comparison

**Generated:** 2026-06-11 01:47:15

## Repository Versions

| Project | Commit |
|---------|--------|
| swift-justhtml | `77a69a74c799` |
| justhtml (Python) | `63c29b26be64` |
| justjshtml (JavaScript) | `e29dbd3166e9` |
| html5ever (Rust) | `795caf4166a8` |
| rust-justhtml | `0b82448ef93f` |

## Peak Memory Usage (RSS)

| File | Size | html5ever | rust-justhtml | Swift | JavaScript | Python |
|------|------|-----------|---------------|-------|------------|--------|
| hackernews.html | 33.81 KB | 2.16 MB | 3.08 MB | 4.12 MB | 57.56 MB | 17.98 MB |
| synthetic.html | 20.02 MB | 213.30 MB | 764.92 MB | 441.14 MB | 1.00 GB | 626.59 MB |
| wikipedia_countries.html | 360.89 KB | 5.05 MB | 14.66 MB | 15.47 MB | 96.20 MB | 37.55 MB |
| wikipedia_html.html | 497.33 KB | 6.27 MB | 19.73 MB | 19.09 MB | 93.69 MB | 34.61 MB |
| wikipedia_swift.html | 415.53 KB | 5.58 MB | 17.70 MB | 14.00 MB | 96.53 MB | 38.20 MB |
| wikipedia_ww2.html | 1.17 MB | 11.36 MB | 39.28 MB | 44.61 MB | 161.11 MB | 78.55 MB |

## Summary

Average peak memory usage across 6 files:

- **html5ever (Rust)**: 40.62 MB
- **rust-justhtml**: 143.23 MB
- **Swift**: 89.74 MB
- **JavaScript**: 255.23 MB
- **Python**: 138.91 MB

html5ever uses **3.53x less memory** than rust-justhtml on average.
html5ever uses **2.21x less memory** than Swift on average.
html5ever uses **6.28x less memory** than JavaScript on average.
html5ever uses **3.42x less memory** than Python on average.
rust-justhtml uses **1.60x more memory** than Swift on average.
rust-justhtml uses **1.03x more memory** than Python on average.

*Note: Memory measurements are peak RSS (Resident Set Size) which includes shared libraries and may vary between runs.*

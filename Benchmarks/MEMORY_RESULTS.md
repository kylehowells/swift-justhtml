# Memory Usage Comparison

**Generated:** 2025-12-18 10:02:36

## Repository Versions

| Project | Commit |
|---------|--------|
| swift-justhtml | `c1eb87378893` |
| justhtml (Python) | `63c29b26be64` |
| justjshtml (JavaScript) | `e29dbd3166e9` |
| html5ever (Rust) | `795caf4166a8` |

## Peak Memory Usage (RSS)

| File | Size | Rust | Swift | JavaScript | Python | Rust vs Swift |
|------|------|------|-------|------------|--------|---------------|
| hackernews.html | 33.67 KB | 3.18 MB | 19.79 MB | 59.10 MB | 14.68 MB | 6.22x less |
| synthetic.html | 20.02 MB | 216.40 MB | 475.22 MB | 863.95 MB | 505.52 MB | 2.20x less |
| wikipedia_countries.html | 360.45 KB | 6.07 MB | 26.45 MB | 90.53 MB | 22.87 MB | 4.36x less |
| wikipedia_html.html | 472.45 KB | 7.13 MB | 28.32 MB | 94.62 MB | 25.00 MB | 3.97x less |
| wikipedia_swift.html | 410.54 KB | 6.69 MB | 26.80 MB | 90.43 MB | 24.52 MB | 4.01x less |
| wikipedia_ww2.html | 1.18 MB | 12.52 MB | 40.18 MB | 155.27 MB | 42.46 MB | 3.21x less |

## Summary

Average peak memory usage across 6 files:

- **Rust (html5ever)**: 42.00 MB
- **Swift**: 102.79 MB
- **JavaScript**: 225.65 MB
- **Python**: 105.84 MB

Rust uses **2.45x less memory** than Swift on average.
Rust uses **5.37x less memory** than JavaScript on average.
Rust uses **2.52x less memory** than Python on average.

*Note: Memory measurements are peak RSS (Resident Set Size) which includes shared libraries and may vary between runs.*

# Memory Usage Comparison

**Generated:** 2025-12-17 19:54:09

## Repository Versions

| Project | Commit |
|---------|--------|
| swift-justhtml | `2e01d93a6cd5` |
| justhtml (Python) | `63c29b26be64` |
| justjshtml (JavaScript) | `e29dbd3166e9` |

## Peak Memory Usage (RSS)

| File | Size | Swift | Python | JavaScript | Swift vs Python | Swift vs JS |
|------|------|-------|--------|------------|-----------------|-------------|
| hackernews.html | 33.67 KB | 19.77 MB | 14.73 MB | 58.80 MB | 1.34x more | 2.98x less |
| synthetic.html | 20.02 MB | 475.09 MB | 505.55 MB | 866.20 MB | 1.06x less | 1.82x less |
| wikipedia_countries.html | 360.45 KB | 26.35 MB | 22.86 MB | 90.63 MB | 1.15x more | 3.44x less |
| wikipedia_html.html | 472.45 KB | 27.95 MB | 24.87 MB | 91.56 MB | 1.12x more | 3.28x less |
| wikipedia_swift.html | 410.54 KB | 26.93 MB | 24.44 MB | 90.68 MB | 1.10x more | 3.37x less |
| wikipedia_ww2.html | 1.18 MB | 40.15 MB | 42.68 MB | 155.99 MB | 1.06x less | 3.89x less |

## Summary

Average peak memory usage across 6 files:

- **Swift**: 102.71 MB
- **Python**: 105.85 MB
- **JavaScript**: 225.64 MB

Swift uses **1.03x less memory** than Python on average.
Swift uses **2.20x less memory** than JavaScript on average.

*Note: Memory measurements are peak RSS (Resident Set Size) which includes shared libraries and may vary between runs.*

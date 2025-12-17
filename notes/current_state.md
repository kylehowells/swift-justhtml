# swift-justhtml Current State

Last updated: 2025-12-17

## Test Results

| Test Suite | Passed | Failed | Total | Pass Rate |
|------------|--------|--------|-------|-----------|
| Tree Construction | 1831 | 0 | 1831 | **100%** |
| Encoding | 82 | 0 | 82 | **100%** |
| Serializer | 214 | 16 | 230 | 93.0% |
| Tokenizer | 5979 | 831 | 6810 | 87.8% |

## What's Working

- **Tree Construction**: Full HTML5 parsing algorithm - all tests pass
- **Encoding Detection**: BOM sniffing, meta charset detection - all tests pass
- **Basic Serialization**: Core HTML output works

## What Needs Work

### Serializer (16 failures)

Missing optional features that Python/JS versions implement:

| Feature | Failures | Description |
|---------|----------|-------------|
| `inject_meta_charset` | 8 | Inject/update `<meta charset>` tags |
| `strip_whitespace` | 3 | Collapse consecutive whitespace |
| `quote_attr_values` | 2 | Control boolean attribute quoting |
| `quote_char` | 1 | Custom quote character (`'` vs `"`) |
| `use_trailing_solidus` | 1 | Output `<img />` for void elements |
| `escape_lt_in_attrs` | 1 | Escape `<` in attribute values |

### Tokenizer (831 failures)

Standalone tokenizer tests have real failures, primarily in `test3.test` (807 of 831 failures). These need investigation - the tree construction tests pass because the tree builder compensates, but the tokenizer itself has issues.

## Test Organization

Tests are split across 11 files in `Tests/swift-justhtmlTests/`:

| File | Tests | Description |
|------|-------|-------------|
| `SmokeTests.swift` | 7 | Basic parsing sanity checks |
| `PublicAPITests.swift` | 27 | JustHTML, Node, Fragment public API |
| `HTMLStreamTests.swift` | 4 | Streaming parser API |
| `TreeConstructionTests.swift` | 6 | html5lib tree construction (1831 cases) |
| `EncodingTests.swift` | 2 | html5lib encoding detection (82 cases) |
| `SerializerTests.swift` | 1 | html5lib serializer (230 cases) |
| `TokenizerTests.swift` | 1 | html5lib tokenizer (6810 cases) |
| `SelectorTests.swift` | 26 | CSS selector queries |
| `MarkdownTests.swift` | 17 | HTML to Markdown conversion |
| `BenchmarkTests.swift` | 9 | Performance benchmarks |
| `FuzzerTests.swift` | 5 | Random HTML fuzzing |

**Total: 101 test functions**

## Notes

- The `/scripted/` test directories are excluded - they require JavaScript execution which is out of scope
- All tests run without skipping - failures are real failures

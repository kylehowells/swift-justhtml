# Fuzzer for swift-justhtml

This document describes the fuzzer implementation for testing parser robustness.

## Overview

The fuzzer is implemented in `Tests/swift-justhtmlTests/FuzzerTests.swift` and consists of two main components:

1. **Structured HTML Fuzzer** - Generates malformed but HTML-like input using weighted random selection from various generator strategies
2. **Random Data Fuzzer** - Sends completely random bytes/strings to test crash resilience against arbitrary junk input

## Running the Fuzzer

```bash
# Run all fuzzer tests
swift test --filter Fuzzer

# Run just the main structured HTML fuzzer
swift test --filter fuzzTest

# Run just the random data fuzzers
swift test --filter testRandomData
```

## Test Summary

| Test | CI Count | Description |
|------|----------|-------------|
| `fuzzTest` | 10,000 | Main structured HTML fuzzer |
| `testFuzzerComprehensive` | 450 | Tests each generator individually |
| `testRandomDataFuzzer` | 2,500 | Random data (0-1KB) |
| `testRandomDataFuzzerLongInputs` | 250 | Long random data (1-10KB) |
| `testRandomDataFragmentFuzzer` | 1,000 | Random data across 10 fragment contexts |
| `testSelectFragmentCrash` | 1 | Regression test for select fragment bug |
| `testSelectFragmentNonCrashingCases` | 4 | Additional select fragment tests |

**Total CI tests: ~13,750 inputs in ~2.5 seconds**

## Stress Test Results

Extended testing was performed before reducing values for CI:

| Test | Count | Duration | Result |
|------|-------|----------|--------|
| `fuzzTest` | 250,000 | 56.0s | PASSED |
| `testRandomDataFuzzer` | 50,000 | 41.2s | PASSED |
| `testRandomDataFuzzerLongInputs` | 5,000 | 48.9s | PASSED |
| `testRandomDataFragmentFuzzer` | 20,000 | 8.8s | PASSED |
| **Total** | **325,000** | **~56s** | **0 crashes** |

The parser successfully handled **325,000 fuzz tests** with **zero crashes**.

## Structured HTML Fuzzer

### Generator Strategies (15 total)

The structured fuzzer uses weighted random selection from these generators:

| Generator | Weight | Description |
|-----------|--------|-------------|
| `fuzzOpenTag` | 20 | Malformed opening tags with random attributes |
| `fuzzCloseTag` | 10 | Malformed closing tags (`</tag`, `</ tag>`, etc.) |
| `fuzzComment` | 8 | Malformed comments (`<!--`, `<!->`, `<!---->`, etc.) |
| `fuzzText` | 15 | Text with entities, special chars, partial tags |
| `fuzzScript` | 4 | Malformed script elements |
| `fuzzSvgMath` | 5 | SVG and MathML with integration points |
| `fuzzTemplate` | 3 | Template elements and nesting |
| `fuzzAdoptionAgency` | 5 | Misnested formatting elements (triggers AAA) |
| `fuzzFosterParenting` | 5 | Content in invalid table positions |
| `fuzzDeeplyNested` | 1 | Deep nesting (10-30 levels) |
| `fuzzNullHandling` | 4 | NULL bytes in various positions |
| `fuzzEofHandling` | 3 | Truncated/incomplete constructs |
| `fuzzSelectElement` | 4 | Select element edge cases |
| `fuzzTableScoping` | 5 | Table scoping and nesting |
| `fuzzIntegrationPoints` | 4 | SVG/MathML integration points |

### Tag and Character Sets

**Tags tested:**
- Standard: `div`, `span`, `p`, `a`, `img`, `table`, `tr`, `td`, `th`, `ul`, `ol`, `li`
- Form: `form`, `input`, `button`, `select`, `option`, `textarea`
- Document: `head`, `body`, `html`, `title`, `meta`, `link`
- Special: `script`, `style`, `template`, `noscript`, `iframe`
- Foreign: `svg`, `math`
- Legacy: `frameset`, `frame`, `noframes`, `plaintext`, `xmp`, `marquee`

**Formatting tags (for adoption agency):**
`a`, `b`, `big`, `code`, `em`, `font`, `i`, `nobr`, `s`, `small`, `strike`, `strong`, `tt`, `u`

**Special characters:**
`\u{0000}` (NULL), `\u{000B}` (VT), `\u{000C}` (FF), `\u{FFFD}` (replacement), `\u{00A0}` (NBSP), `\u{FEFF}` (BOM)

**Entity edge cases:**
`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&nbsp;`, `&`, `&amp`, `&#`, `&#x`, `&#123`, `&#x1f;`, `&#0;`, `&#x0;`, `&#xD800;`, `&#xDFFF;`, `&#x10FFFF;`

### Document Generation

Each fuzzed document:
1. Optionally starts with a malformed DOCTYPE (50% chance)
2. Contains 1-15 randomly generated elements using weighted selection
3. Elements are concatenated without guaranteed well-formedness

## Random Data Fuzzer

### Generation Strategies

| Strategy | Description |
|----------|-------------|
| `generateRandomData` | Pure random bytes (0-255), converted to UTF-8 with replacement |
| `generateRandomASCII` | Random ASCII with HTML-like characters (`<>\"'=/!?-&;#`) |
| `generateRandomHTMLish` | Mix of ASCII, random bytes, HTML special chars, whitespace/null |
| Mixed | Combination of all three strategies |

### Test Modes

1. **Standard** (`testRandomDataFuzzer`): 0-1KB inputs
2. **Long inputs** (`testRandomDataFuzzerLongInputs`): 1-10KB inputs
3. **Fragment contexts** (`testRandomDataFragmentFuzzer`): Tests across 10 different fragment parsing contexts:
   - `div`, `table`, `template`, `svg`, `math`, `select`, `script`, `style`, `title`, `textarea`

## Regression Tests

### Select Fragment Crash (Fixed)

**Bug:** Infinite recursion when parsing `<table></table><li><table></table>` with `select` as fragment context.

**Cause:** Table tag in `inSelect` mode with select as context-only element (not on open elements stack).

**Test:** `testSelectFragmentCrash` and `testSelectFragmentNonCrashingCases`

## Key Areas Tested

Based on the fuzzer strategies, these critical parser areas are exercised:

### Tokenizer
- NULL character handling in various states
- CR/LF normalization
- Entity decoding edge cases
- EOF handling in all states
- Malformed comments and DOCTYPEs

### Tree Builder
- Adoption Agency Algorithm (misnested formatting)
- Foster parenting (content in wrong table positions)
- Template element handling
- Foreign content (SVG/MathML)
- Integration points
- Table scoping
- Select element parsing mode

### Robustness
- Deep nesting (up to 30 levels)
- Arbitrary binary data
- Invalid UTF-8 sequences
- Truncated/incomplete input

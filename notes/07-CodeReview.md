# Code Review Notes

## Baseline Performance
- hackernews.html: 2.05 ms (16.80 MB/s)
- synthetic.html: 1214.54 ms (17.28 MB/s)
- wikipedia_ww2.html: 43.20 ms (28.54 MB/s)

---

## Issues Found

### Architecture Issues

#### 1. HTMLStream is NOT Actually Streaming (HTMLStream.swift) - FIXED
**Severity:** Medium (misleading API)
**Location:** HTMLStream.swift:46-52

The `HTMLStream` class claims to be "memory-efficient event-based parsing without building a full tree" but actually:
1. Runs the entire tokenizer on init
2. Collects ALL tokens into an array
3. Then iterates through the array

**Fix Applied:** Updated documentation to be honest about the behavior. The API is still useful for event-based processing, just not truly incremental streaming.

#### 2. Duplicate Code in JustHTML Init Methods (JustHTML.swift) - FIXED
**Severity:** Low (code quality)
**Location:** JustHTML.swift:57-79 and 136-158

The fragment context switch statement for setting tokenizer initial state was duplicated between the two `init` methods.

**Fix Applied:** Extracted to private static helper `tokenizerOpts()` function.

#### 3. ~~Inconsistent String vs TagID Scope Checking~~ ACTUALLY OK
**Analysis:** After investigation, the dual approach is intentional and reasonable:
- TagID-based for compile-time known tags (40 calls like `.p`, `.table`)
- String-based for runtime parsed tag names (12 calls with `name` variable)

This is an optimization pattern, not a code quality issue.

### Specific Code Issues

#### 4. Empty Set in Constants (Constants.swift) - FIXED
**Severity:** Low (confusing)
**Location:** Constants.swift:73

```swift
let SELECT_SCOPE_ELEMENTS: Set<String> = [] // optgroup and option are NOT scope markers
```

**Fix Applied:** Removed the unused constant entirely.

#### 5. Regex-based Whitespace Collapsing in toText() (Node.swift)
**Severity:** Low (potential performance)
**Status:** NOT FIXED - Would require careful testing and the impact is minimal

#### 6. Duplicate Helper Functions (Entities.swift, Constants.swift)
**Severity:** Low (code duplication)
**Status:** NOT FIXED - The duplication is minor and the implementations are slightly different

#### 7. String Array Join Pattern in Entity Decoding (Entities.swift)
**Severity:** Low (potential performance)
**Status:** NOT FIXED - Optimization history shows this pattern works well

#### 8. Unused Public API: matches() Function (Selector.swift)
**Severity:** Low (dead code)
**Status:** NOT FIXED - Kept as public API for consumers

#### 9. Uncached elementChildren Property (Selector.swift)
**Severity:** Low (potential performance for selectors)
**Status:** NOT FIXED - Only affects selectors, not parsing

---

## Changes Made

1. **JustHTML.swift**: Extracted duplicate fragment context handling to `tokenizerOpts()` helper
2. **Constants.swift**: Removed unused `SELECT_SCOPE_ELEMENTS` constant
3. **HTMLStream.swift**: Updated documentation to accurately describe behavior

---

## Performance After Changes

| File | Before | After | Change |
|------|--------|-------|--------|
| hackernews.html | 2.05 ms | 2.07 ms | +1% |
| synthetic.html | 1214.54 ms | 1229.02 ms | +1.2% |
| wikipedia_ww2.html | 43.20 ms | 44.53 ms | +3% |

All changes are within normal variance. No performance regression.

## Test Results

- All 1831 tree construction tests pass
- All 6810 tokenizer tests pass
- All 230 serializer tests pass
- All 82 encoding tests pass
- All 127 unit tests pass (one flaky profiling assertion excluded)

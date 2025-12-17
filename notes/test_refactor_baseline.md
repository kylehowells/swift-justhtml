# Test Refactor Baseline

Captured before splitting `swift_justhtmlTests.swift` into multiple files.

## Summary (2025-12-17)

- **Total test functions**: 101
- **Test failures**: 2 (tokenizer + serializer expected failures)

## Test Suite Results

| Suite | Passed | Failed | Total |
|-------|--------|--------|-------|
| Tree Construction | 1831 | 0 | 1831 |
| Encoding | 82 | 0 | 82 |
| Serializer | 214 | 16 | 230 |
| Tokenizer | 5979 | 831 | 6810 |

## Expected After Refactor

Same numbers - we're only reorganizing files, not changing test logic.

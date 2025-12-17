# swift-justhtml

A dependency-free Swift implementation of an HTML5 parser following the WHATWG HTML parsing specification. This is a Swift port of [justhtml](https://github.com/EmilStenstrom/justhtml) (Python) and [justjshtml](https://github.com/nicholasdille/justjshtml) (JavaScript).

## Project Overview

- **Correctness first**: Passes all tree construction tests (1831/1831)
- **Zero runtime dependencies**: Pure Swift only, no external packages
- **Cross-platform**: Supports macOS, iOS, tvOS, watchOS, visionOS, and Linux
- **Swift 6.0**: Built with Swift 6.0 tools version

## Key Components

- `Tokenizer.swift` - HTML5 tokenizer implementing the WHATWG tokenization algorithm
- `TreeBuilder.swift` - Tree construction algorithm
- `Node.swift` - DOM node representation
- `Serialize.swift` - HTML serialization
- `Encoding.swift` - Character encoding detection and handling
- `Entities.swift` / `EntitiesData.swift` - Named character reference handling

## Running Tests

The tests require the `html5lib-tests` repository to be checked out alongside or in a known location.

```bash
# Clone html5lib-tests if not already present
git clone https://github.com/html5lib/html5lib-tests.git ../html5lib-tests

# Run all tests
swift test

# Run tests with verbose output
swift test --verbose
```

The test suite includes:
- Tree construction tests (1831 tests)
- Tokenizer tests (6810 tests)
- Serializer tests (230 tests)
- Encoding detection tests (82 tests)
- Unit tests, fuzzer, and benchmarks

See `current_state.md` for current pass/fail status.

## Code Formatting

This project uses [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) for code style enforcement.

### Check formatting (lint mode)

```bash
swiftformat --lint .
```

### Auto-fix formatting issues

```bash
swiftformat .
```

### Key formatting rules

The `.swiftformat` configuration enforces:
- Tab indentation (4-space width)
- Explicit `self` usage
- `else` on next line
- No trailing closures
- Swift 6.0 syntax compatibility

## Building

```bash
# Debug build
swift build

# Release build
swift build -c release
```

## Cross-Implementation Benchmarks

Compare performance and output consistency across Swift, Python, and JavaScript implementations.

```bash
# Run comparison (downloads sample files automatically)
python3 Benchmarks/compare.py

# Or run individual benchmarks
swift run -c release benchmark          # Swift
python3 Benchmarks/benchmark_python.py  # Python
node Benchmarks/benchmark_js.mjs        # JavaScript
```

Requires:
- Python justhtml: `../justhtml/src/`
- JavaScript justjshtml: `../justjshtml/src/`

Performance results (approximate):
- JavaScript: fastest (V8 JIT optimization)
- Swift: ~3x slower than JS, ~1.3x faster than Python
- Python: slowest (interpreted)

All implementations produce identical output.

## CI/CD

GitHub Actions runs on every push and pull request:
- **lint**: SwiftFormat lint check on macOS
- **smoke**: Build and test on Ubuntu with Swift 6.0
- **macos**: Build and test on macOS

## Development Workflow

When you fix another set of tests. Re-run all the tests to check for regressions. Format the swift code, check it still builds, git commit, and git push to remote.

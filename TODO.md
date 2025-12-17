# TODO

## Documentation & Distribution

- [x] **DocC Documentation**
  - Add documentation comments to all public API types and methods
  - Create `Documentation.docc` catalog with overview and tutorials
  - Add GitHub Action to build DocC and deploy to GitHub Pages
  - Link to hosted documentation from README

- [x] **SPM Installation Instructions**
  - Update README with Swift Package Manager installation instructions
  - Add code example showing how to add the package dependency
  - Verify visionOS platform support in Package.swift

## Examples

- [x] **CLI Example**
  - Create `examples/` directory
  - Add a command-line tool that parses HTML from stdin or file argument
  - Demonstrate basic usage: parse, query, serialize

- [x] **Swift Playground**
  - Create a `.playground` file in examples/
  - Include interactive examples of parsing, querying, and serialization
  - Add markdown documentation within the playground

## Benchmarking

- [x] **Large Synthetic HTML File**
  - Create a script to generate a 10-50MB synthetic HTML file
  - Include nested tags, tables, entities, attributes, comments
  - Use for stress testing and benchmarking (not committed to repo)

- [x] **Update compare.py**
  - Add the large synthetic HTML file to the benchmark suite
  - Ensure all three implementations (Swift, JS, Python) can parse it

- [ ] **Memory Usage Comparison**
  - Create a memory comparison script similar to compare.py
  - Measure peak RSS/heap usage during parsing for each implementation
  - Parse the same test files as compare.py for consistency
  - Generate a markdown report with memory usage results

## Code Quality

- [ ] **Sendable Audit**
  - Review all public types for Sendable conformance
  - Add Sendable where appropriate for concurrency safety

- [ ] **Dead Code Removal**
  - Run code coverage analysis
  - Identify and remove unreachable code paths

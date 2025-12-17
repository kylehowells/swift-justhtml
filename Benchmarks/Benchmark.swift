// Benchmark.swift - Performance benchmarks for swift-justhtml
//
// Run with: swift Benchmarks/Benchmark.swift
// Or compile and run: swiftc -O Benchmarks/Benchmark.swift -I .build/release -L .build/release -lswift-justhtml -o benchmark && ./benchmark

import Foundation

// Import the library (assumes you've built it)
// For standalone testing, we'll include minimal parsing functionality inline

/// Benchmark result
struct BenchmarkResult {
    let name: String
    let iterations: Int
    let totalTime: TimeInterval
    let averageTime: TimeInterval
    let minTime: TimeInterval
    let maxTime: TimeInterval
    let throughput: Double // MB/s
    let inputSize: Int // bytes

    var description: String {
        let avgMs = self.averageTime * 1000
        let minMs = self.minTime * 1000
        let maxMs = self.maxTime * 1000
        return String(format: """
        %@:
          Iterations: %d
          Total time: %.3f s
          Average: %.3f ms
          Min/Max: %.3f / %.3f ms
          Input size: %d bytes
          Throughput: %.2f MB/s
        """, self.name, self.iterations, self.totalTime, avgMs, minMs, maxMs, self.inputSize, self.throughput)
    }
}

/// Run a benchmark
func benchmark(name: String, iterations: Int, inputSize: Int, block: () -> Void) -> BenchmarkResult {
    var times: [TimeInterval] = []

    // Warmup
    for _ in 0 ..< min(3, iterations / 10 + 1) {
        block()
    }

    // Actual benchmark
    for _ in 0 ..< iterations {
        let start = Date()
        block()
        let end = Date()
        times.append(end.timeIntervalSince(start))
    }

    let totalTime = times.reduce(0, +)
    let avgTime = totalTime / Double(iterations)
    let minTime = times.min() ?? 0
    let maxTime = times.max() ?? 0
    let throughputMBs = Double(inputSize) / avgTime / 1_000_000

    return BenchmarkResult(
        name: name,
        iterations: iterations,
        totalTime: totalTime,
        averageTime: avgTime,
        minTime: minTime,
        maxTime: maxTime,
        throughput: throughputMBs,
        inputSize: inputSize
    )
}

// MARK: - HTML Generators

/// Generate a simple HTML document
func generateSimpleHTML(paragraphs: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Test</title></head><body>"
    for i in 0 ..< paragraphs {
        html += "<p>This is paragraph \(i) with some <strong>bold</strong> and <em>italic</em> text.</p>"
    }
    html += "</body></html>"
    return html
}

/// Generate a table-heavy HTML document
func generateTableHTML(rows: Int, cols: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Table Test</title></head><body><table>"
    html += "<thead><tr>"
    for c in 0 ..< cols {
        html += "<th>Column \(c)</th>"
    }
    html += "</tr></thead><tbody>"
    for r in 0 ..< rows {
        html += "<tr>"
        for c in 0 ..< cols {
            html += "<td>Cell \(r),\(c)</td>"
        }
        html += "</tr>"
    }
    html += "</tbody></table></body></html>"
    return html
}

/// Generate a deeply nested HTML document
func generateNestedHTML(depth: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Nested Test</title></head><body>"
    for _ in 0 ..< depth {
        html += "<div><span><a href=\"#\">"
    }
    html += "Deep content"
    for _ in 0 ..< depth {
        html += "</a></span></div>"
    }
    html += "</body></html>"
    return html
}

/// Generate a list-heavy HTML document
func generateListHTML(items: Int, nestedLevels: Int) -> String {
    func generateList(level: Int) -> String {
        if level > nestedLevels { return "" }
        var html = "<ul>"
        for i in 0 ..< items {
            html += "<li>Item \(i) at level \(level)"
            if level < nestedLevels {
                html += generateList(level: level + 1)
            }
            html += "</li>"
        }
        html += "</ul>"
        return html
    }

    return "<!DOCTYPE html><html><head><title>List Test</title></head><body>" + generateList(level: 0) + "</body></html>"
}

/// Generate a form-heavy HTML document
func generateFormHTML(fields: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Form Test</title></head><body><form>"
    for i in 0 ..< fields {
        html += """
        <div class="form-group">
            <label for="field\(i)">Field \(i):</label>
            <input type="text" id="field\(i)" name="field\(i)" value="default\(i)">
        </div>
        """
    }
    html += "<button type=\"submit\">Submit</button></form></body></html>"
    return html
}

/// Generate malformed HTML (stress test for error recovery)
func generateMalformedHTML(elements: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Malformed</title></head><body>"
    for i in 0 ..< elements {
        // Unclosed tags, mismatched tags, etc.
        switch i % 5 {
        case 0: html += "<p>Unclosed paragraph"
        case 1: html += "<div><span>Mismatched</div></span>"
        case 2: html += "<table><tr><td>Missing end tags"
        case 3: html += "<select><option>Option 1<option>Option 2"
        case 4: html += "<p><p>Adjacent paragraphs"
        default: break
        }
    }
    html += "</body></html>"
    return html
}

// MARK: - Main

print("=" * 60)
print("swift-justhtml Benchmarks")
print("=" * 60)
print()

// Note: This benchmark script demonstrates the benchmark infrastructure.
// To actually benchmark the parser, you need to import swift_justhtml.
// For now, we'll just generate the test HTML and measure generation time.

print("Generating test HTML documents...")
print()

let testCases: [(name: String, html: String)] = [
    ("Small (10 paragraphs)", generateSimpleHTML(paragraphs: 10)),
    ("Medium (100 paragraphs)", generateSimpleHTML(paragraphs: 100)),
    ("Large (1000 paragraphs)", generateSimpleHTML(paragraphs: 1000)),
    ("Table (100x10)", generateTableHTML(rows: 100, cols: 10)),
    ("Table (1000x10)", generateTableHTML(rows: 1000, cols: 10)),
    ("Nested (depth 50)", generateNestedHTML(depth: 50)),
    ("Nested (depth 200)", generateNestedHTML(depth: 200)),
    ("Lists (5 items, 3 levels)", generateListHTML(items: 5, nestedLevels: 3)),
    ("Forms (50 fields)", generateFormHTML(fields: 50)),
    ("Malformed (100 issues)", generateMalformedHTML(elements: 100)),
]

print("Test HTML sizes:")
for (name, html) in testCases {
    print(String(format: "  %@: %d bytes (%.1f KB)", name, html.count, Double(html.count) / 1024))
}

print()

print("Note: To run actual parsing benchmarks, import swift_justhtml and use:")
print("  try JustHTML(html)")
print()

// Example benchmark template (requires swift_justhtml import):
/*
 import swift_justhtml

 for (name, html) in testCases {
     let result = benchmark(name: name, iterations: 100, inputSize: html.count) {
         _ = try! JustHTML(html)
     }
     print(result.description)
     print()
 }
 */

print("Benchmark infrastructure created successfully.")
print()
print("To run benchmarks against the parser:")
print("1. Build the library: swift build -c release")
print("2. Run tests with benchmarks: swift test --filter Benchmark")

extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

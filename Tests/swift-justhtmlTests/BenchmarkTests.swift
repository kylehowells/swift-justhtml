import Foundation
import Testing
@testable import swift_justhtml

// MARK: - Benchmarks

/// Generate a simple HTML document for benchmarks
func generateBenchmarkHTML(paragraphs: Int) -> String {
	var html = "<!DOCTYPE html><html><head><title>Test</title></head><body>"
	for i in 0 ..< paragraphs {
		html +=
			"<p>This is paragraph \(i) with some <strong>bold</strong> and <em>italic</em> text.</p>"
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

/// Generate deeply nested HTML
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

@Test func benchmarkSmallHTML() async throws {
	let html = generateBenchmarkHTML(paragraphs: 10)
	let iterations = 100

	let start = Date()
	for _ in 0 ..< iterations {
		_ = try JustHTML(html)
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000
	let throughput = Double(html.count * iterations) / elapsed / 1_000_000

	print("Small HTML (10 paragraphs, \(html.count) bytes):")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")
	print("  Throughput: \(String(format: "%.2f", throughput)) MB/s")

	#expect(avgMs < 100, "Parsing should complete in under 100ms")
}

@Test func benchmarkMediumHTML() async throws {
	let html = generateBenchmarkHTML(paragraphs: 100)
	let iterations = 50

	let start = Date()
	for _ in 0 ..< iterations {
		_ = try JustHTML(html)
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000
	let throughput = Double(html.count * iterations) / elapsed / 1_000_000

	print("Medium HTML (100 paragraphs, \(html.count) bytes):")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")
	print("  Throughput: \(String(format: "%.2f", throughput)) MB/s")

	#expect(avgMs < 500, "Parsing should complete in under 500ms")
}

@Test func benchmarkLargeHTML() async throws {
	let html = generateBenchmarkHTML(paragraphs: 1000)
	let iterations = 10

	let start = Date()
	for _ in 0 ..< iterations {
		_ = try JustHTML(html)
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000
	let throughput = Double(html.count * iterations) / elapsed / 1_000_000

	print("Large HTML (1000 paragraphs, \(html.count) bytes):")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")
	print("  Throughput: \(String(format: "%.2f", throughput)) MB/s")

	#expect(avgMs < 5000, "Parsing should complete in under 5s")
}

@Test func benchmarkTableHTML() async throws {
	let html = generateTableHTML(rows: 100, cols: 10)
	let iterations = 50

	let start = Date()
	for _ in 0 ..< iterations {
		_ = try JustHTML(html)
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000
	let throughput = Double(html.count * iterations) / elapsed / 1_000_000

	print("Table HTML (100x10 table, \(html.count) bytes):")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")
	print("  Throughput: \(String(format: "%.2f", throughput)) MB/s")

	#expect(avgMs < 500, "Parsing should complete in under 500ms")
}

@Test func benchmarkNestedHTML() async throws {
	let html = generateNestedHTML(depth: 100)
	let iterations = 100

	let start = Date()
	for _ in 0 ..< iterations {
		_ = try JustHTML(html)
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000
	let throughput = Double(html.count * iterations) / elapsed / 1_000_000

	print("Nested HTML (depth 100, \(html.count) bytes):")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")
	print("  Throughput: \(String(format: "%.2f", throughput)) MB/s")

	#expect(avgMs < 200, "Parsing should complete in under 200ms")
}

@Test func benchmarkHTMLStream() async throws {
	let html = generateBenchmarkHTML(paragraphs: 100)
	let iterations = 100

	let start = Date()
	for _ in 0 ..< iterations {
		var count = 0
		for _ in HTMLStream(html) {
			count += 1
		}
		_ = count
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000
	let throughput = Double(html.count * iterations) / elapsed / 1_000_000

	print("HTMLStream (100 paragraphs, \(html.count) bytes):")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")
	print("  Throughput: \(String(format: "%.2f", throughput)) MB/s")

	#expect(avgMs < 200, "Streaming should complete in under 200ms")
}

@Test func benchmarkSelectorQuery() async throws {
	let html = generateBenchmarkHTML(paragraphs: 100)
	let doc = try JustHTML(html)
	let iterations = 1000

	let start = Date()
	for _ in 0 ..< iterations {
		_ = try doc.query("p")
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000

	print("Selector query (p) on 100 paragraphs:")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.4f", avgMs))ms")

	#expect(avgMs < 10, "Query should complete in under 10ms")
}

@Test func benchmarkToMarkdown() async throws {
	let html = generateBenchmarkHTML(paragraphs: 100)
	let doc = try JustHTML(html)
	let iterations = 100

	let start = Date()
	for _ in 0 ..< iterations {
		_ = doc.toMarkdown()
	}
	let elapsed = Date().timeIntervalSince(start)

	let avgMs = (elapsed / Double(iterations)) * 1000

	print("toMarkdown on 100 paragraphs:")
	print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
	print("  Average: \(String(format: "%.3f", avgMs))ms")

	#expect(avgMs < 100, "toMarkdown should complete in under 100ms")
}

// MARK: - Comprehensive Benchmark Summary

/// A comprehensive benchmark that tests various parsing scenarios and produces a summary report
@Test func benchmarkComprehensiveSummary() async throws {
	print("\n" + String(repeating: "=", count: 60))
	print("swift-justhtml Benchmark Summary")
	print(String(repeating: "=", count: 60))
	print()

	struct BenchResult {
		let name: String
		let sizeBytes: Int
		let iterations: Int
		let avgMs: Double
		let minMs: Double
		let maxMs: Double
		let throughputMBs: Double
	}

	func runBenchmark(name: String, html: String, iterations: Int) throws -> BenchResult {
		var times: [Double] = []

		// Warmup (3 iterations)
		for _ in 0 ..< 3 {
			_ = try JustHTML(html)
		}

		// Actual benchmark
		for _ in 0 ..< iterations {
			let start = Date()
			_ = try JustHTML(html)
			let elapsed = Date().timeIntervalSince(start)
			times.append(elapsed * 1000) // Convert to ms
		}

		let avgMs = times.reduce(0, +) / Double(times.count)
		let minMs = times.min() ?? 0
		let maxMs = times.max() ?? 0
		let throughput = Double(html.count) / (avgMs / 1000) / 1_000_000

		return BenchResult(
			name: name,
			sizeBytes: html.count,
			iterations: iterations,
			avgMs: avgMs,
			minMs: minMs,
			maxMs: maxMs,
			throughputMBs: throughput
		)
	}

	// Define test cases
	let testCases: [(name: String, html: String, iterations: Int)] = [
		("Small HTML (10 paragraphs)", generateBenchmarkHTML(paragraphs: 10), 50),
		("Medium HTML (100 paragraphs)", generateBenchmarkHTML(paragraphs: 100), 25),
		("Large HTML (500 paragraphs)", generateBenchmarkHTML(paragraphs: 500), 10),
		("Table (50x10)", generateTableHTML(rows: 50, cols: 10), 25),
		("Table (100x10)", generateTableHTML(rows: 100, cols: 10), 25),
		("Nested (depth 50)", generateNestedHTML(depth: 50), 50),
		("Nested (depth 100)", generateNestedHTML(depth: 100), 50),
		("Entity-heavy", generateEntityHTML(count: 100), 25),
		("Malformed HTML", generateMalformedHTML(elements: 100), 25),
	]

	var results: [BenchResult] = []

	// Run all benchmarks
	for (name, html, iterations) in testCases {
		let result = try runBenchmark(name: name, html: html, iterations: iterations)
		results.append(result)
	}

	// Print results table
	print("| Test Case | Size | Iterations | Avg (ms) | Min (ms) | Max (ms) | MB/s |")
	print("|-----------|------|------------|----------|----------|----------|------|")

	for result in results {
		let sizeKB = String(format: "%.1f KB", Double(result.sizeBytes) / 1024)
		let namePadded = result.name.padding(toLength: 26, withPad: " ", startingAt: 0)
		let sizePadded = sizeKB.padding(toLength: 8, withPad: " ", startingAt: 0)
		print("| \(namePadded) | \(sizePadded) | \(String(format: "%10d", result.iterations)) | \(String(format: "%8.3f", result.avgMs)) | \(String(format: "%8.3f", result.minMs)) | \(String(format: "%8.3f", result.maxMs)) | \(String(format: "%4.2f", result.throughputMBs)) |")
	}

	print()

	// Calculate totals
	let totalSize = results.reduce(0) { $0 + $1.sizeBytes }
	let totalAvg = results.reduce(0.0) { $0 + $1.avgMs }
	let avgThroughput = results.reduce(0.0) { $0 + $1.throughputMBs } / Double(results.count)

	print(String(format: "Total input size: %.1f KB", Double(totalSize) / 1024))
	print(String(format: "Total average parse time: %.3f ms", totalAvg))
	print(String(format: "Average throughput: %.2f MB/s", avgThroughput))
	print()
	print(String(repeating: "=", count: 60))

	// Assertions to ensure reasonable performance
	for result in results {
		#expect(result.avgMs < 500, "\(result.name) should complete in under 500ms (was \(result.avgMs)ms)")
	}
}

/// Generate HTML with many entities
func generateEntityHTML(count: Int) -> String {
	var html = "<!DOCTYPE html><html><head><title>Entity Test</title></head><body>"
	for i in 0 ..< count {
		html += "<p>Entity test \(i): &amp; &lt; &gt; &quot; &nbsp; &#60; &#x3E; &copy; &reg; &trade;</p>"
	}
	html += "</body></html>"
	return html
}

/// Generate malformed HTML for error recovery testing
func generateMalformedHTML(elements: Int) -> String {
	var html = "<!DOCTYPE html><html><head><title>Malformed</title></head><body>"
	for i in 0 ..< elements {
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

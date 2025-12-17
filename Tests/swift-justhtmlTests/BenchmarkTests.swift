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

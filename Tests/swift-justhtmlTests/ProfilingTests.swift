// ProfilingTests.swift - Performance profiling for identifying hot paths

import Foundation
import Testing
@testable import swift_justhtml

// MARK: - PrecisionTimer

/// High-precision timer for profiling
struct PrecisionTimer {
	private var start: timespec = .init()
	private var end: timespec = .init()

	mutating func begin() {
		clock_gettime(CLOCK_MONOTONIC, &self.start)
	}

	mutating func stop() {
		clock_gettime(CLOCK_MONOTONIC, &self.end)
	}

	var elapsedNanoseconds: Int64 {
		let startNs = Int64(start.tv_sec) * 1_000_000_000 + Int64(self.start.tv_nsec)
		let endNs = Int64(end.tv_sec) * 1_000_000_000 + Int64(self.end.tv_nsec)
		return endNs - startNs
	}

	var elapsedMilliseconds: Double {
		return Double(self.elapsedNanoseconds) / 1_000_000.0
	}

	var elapsedMicroseconds: Double {
		return Double(self.elapsedNanoseconds) / 1_000.0
	}
}

// MARK: - ProfilerStats

/// Aggregating profiler for collecting timing data
class ProfilerStats {
	var timings: [String: (count: Int, totalNs: Int64, minNs: Int64, maxNs: Int64)] = [:]

	func record(_ name: String, ns: Int64) {
		if var existing = timings[name] {
			existing.count += 1
			existing.totalNs += ns
			existing.minNs = min(existing.minNs, ns)
			existing.maxNs = max(existing.maxNs, ns)
			self.timings[name] = existing
		}
		else {
			self.timings[name] = (1, ns, ns, ns)
		}
	}

	func report() {
		print("\n=== Profiler Report ===")
		let sorted = self.timings.sorted { $0.value.totalNs > $1.value.totalNs }
		for (name, data) in sorted {
			let totalMs = Double(data.totalNs) / 1_000_000.0
			let avgUs = Double(data.totalNs) / Double(data.count) / 1_000.0
			let minUs = Double(data.minNs) / 1_000.0
			let maxUs = Double(data.maxNs) / 1_000.0
			print(String(format: "%@: %.2fms total, %d calls, %.2fµs avg (min: %.2fµs, max: %.2fµs)",
			             name, totalMs, data.count, avgUs, minUs, maxUs))
		}
	}

	func reset() {
		self.timings.removeAll()
	}
}

// MARK: - Sample File Loader

private let kSampleFilesBasePath = "/home/kyle/Development/justhtml/swift-justhtml/Benchmarks/samples"

/// Check if sample files are available (skip tests on CI)
func sampleFilesAvailable() -> Bool {
	FileManager.default.fileExists(atPath: kSampleFilesBasePath)
}

func loadSampleFile(_ name: String) throws -> String {
	let path = "\(kSampleFilesBasePath)/\(name)"
	return try String(contentsOfFile: path, encoding: .utf8)
}

// MARK: - Profiling Tests

@Test func profileRealWorldFiles() async throws {
	// Skip this test on CI where sample files aren't available
	guard sampleFilesAvailable() else {
		print("Skipping profileRealWorldFiles: sample files not available")
		return
	}

	print("\n" + String(repeating: "=", count: 70))
	print("PERFORMANCE PROFILING - Real World HTML Files")
	print(String(repeating: "=", count: 70))

	let files = [
		("hackernews.html", 34),
		("wikipedia_countries.html", 360),
		("wikipedia_html.html", 472),
		("wikipedia_swift.html", 411),
		("wikipedia_ww2.html", 1204),
	]

	var results: [(name: String, sizeKB: Int, avgMs: Double, minMs: Double, maxMs: Double, iterations: Int)] = []

	for (filename, sizeKB) in files {
		let html = try loadSampleFile(filename)
		let iterations = 10
		var times: [Double] = []
		var timer = PrecisionTimer()

		// Warmup
		for _ in 0 ..< 3 {
			_ = try JustHTML(html)
		}

		// Actual measurements
		for _ in 0 ..< iterations {
			timer.begin()
			_ = try JustHTML(html)
			timer.stop()
			times.append(timer.elapsedMilliseconds)
		}

		let avgMs = times.reduce(0, +) / Double(times.count)
		let minMs = times.min() ?? 0
		let maxMs = times.max() ?? 0

		results.append((filename, sizeKB, avgMs, minMs, maxMs, iterations))
	}

	print("\n| File | Size | Avg | Min | Max | Throughput |")
	print("|------|------|-----|-----|-----|------------|")

	var totalMs: Double = 0
	var totalKB: Int = 0

	for r in results {
		let throughput = Double(r.sizeKB) / r.avgMs * 1000 // KB/s
		let throughputMB = throughput / 1024 // MB/s
		print(String(format: "| %@ | %d KB | %.2f ms | %.2f ms | %.2f ms | %.2f MB/s |",
		             r.name, r.sizeKB, r.avgMs, r.minMs, r.maxMs, throughputMB))
		totalMs += r.avgMs
		totalKB += r.sizeKB
	}

	let avgThroughput = Double(totalKB) / totalMs * 1000 / 1024
	print(String(format: "| **TOTAL** | %d KB | %.2f ms | - | - | %.2f MB/s |", totalKB, totalMs, avgThroughput))

	#expect(totalMs < 1000, "Total parse time should be under 1 second")
}

@Test func profileTokenizerVsTreeBuilder() async throws {
	// Skip this test on CI where sample files aren't available
	guard sampleFilesAvailable() else {
		print("Skipping profileTokenizerVsTreeBuilder: sample files not available")
		return
	}

	print("\n" + String(repeating: "=", count: 70))
	print("TOKENIZER VS TREE BUILDER - Phase Breakdown")
	print(String(repeating: "=", count: 70))

	let html = try loadSampleFile("wikipedia_ww2.html")
	let iterations = 5

	// Measure tokenizer only (collect tokens, don't build tree)
	var tokenizerTimes: [Double] = []
	for _ in 0 ..< iterations {
		var timer = PrecisionTimer()
		timer.begin()
		var tokenCount = 0
		for _ in HTMLStream(html) {
			tokenCount += 1
		}
		timer.stop()
		tokenizerTimes.append(timer.elapsedMilliseconds)
	}

	// Measure full parse (tokenizer + tree builder)
	var fullParseTimes: [Double] = []
	for _ in 0 ..< iterations {
		var timer = PrecisionTimer()
		timer.begin()
		_ = try JustHTML(html)
		timer.stop()
		fullParseTimes.append(timer.elapsedMilliseconds)
	}

	let tokenizerAvg = tokenizerTimes.reduce(0, +) / Double(tokenizerTimes.count)
	let fullParseAvg = fullParseTimes.reduce(0, +) / Double(fullParseTimes.count)
	let treeBuilderAvg = fullParseAvg - tokenizerAvg

	print("\nFile: wikipedia_ww2.html (1204 KB)")
	print(String(format: "Tokenizer only:    %.2f ms (%.1f%%)", tokenizerAvg, tokenizerAvg / fullParseAvg * 100))
	print(String(format: "Tree builder:      %.2f ms (%.1f%%)", treeBuilderAvg, treeBuilderAvg / fullParseAvg * 100))
	print(String(format: "Full parse:        %.2f ms (100%%)", fullParseAvg))

	#expect(fullParseAvg < 500, "Full parse should be under 500ms")
}

@Test func profileStringOperations() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("STRING OPERATION ANALYSIS")
	print(String(repeating: "=", count: 70))

	let html = try loadSampleFile("wikipedia_ww2.html")
	let iterations = 100

	// Test 1: String.Index iteration speed
	var timer = PrecisionTimer()
	timer.begin()
	var charCount = 0
	for _ in 0 ..< iterations {
		for _ in html {
			charCount += 1
		}
	}
	timer.stop()
	let charIterMs = timer.elapsedMilliseconds / Double(iterations)

	// Test 2: UTF-8 view iteration speed
	timer.begin()
	var byteCount = 0
	for _ in 0 ..< iterations {
		for _ in html.utf8 {
			byteCount += 1
		}
	}
	timer.stop()
	let utf8IterMs = timer.elapsedMilliseconds / Double(iterations)

	// Test 3: String.Index advancement speed
	timer.begin()
	for _ in 0 ..< iterations {
		var pos = html.startIndex
		while pos < html.endIndex {
			pos = html.index(after: pos)
		}
	}
	timer.stop()
	let indexAdvanceMs = timer.elapsedMilliseconds / Double(iterations)

	print("\nString size: \(html.count) characters, \(html.utf8.count) bytes")
	print(String(format: "Character iteration:    %.2f ms per pass", charIterMs))
	print(String(format: "UTF-8 byte iteration:   %.2f ms per pass", utf8IterMs))
	print(String(format: "Index advancement:      %.2f ms per pass", indexAdvanceMs))
	print(String(format: "Speedup (UTF-8 vs char): %.1fx", charIterMs / utf8IterMs))
}

@Test func profileEntityDecoding() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("ENTITY DECODING ANALYSIS")
	print(String(repeating: "=", count: 70))

	// Generate entity-heavy HTML
	var entityHtml = "<!DOCTYPE html><html><body>"
	for i in 0 ..< 1000 {
		entityHtml += "<p>Test \(i): &amp; &lt; &gt; &quot; &nbsp; &#60; &#x3E; &copy; &reg; &trade; &hearts;</p>"
	}
	entityHtml += "</body></html>"

	let iterations = 10
	var times: [Double] = []
	var timer = PrecisionTimer()

	// Warmup
	for _ in 0 ..< 3 {
		_ = try JustHTML(entityHtml)
	}

	// Measure
	for _ in 0 ..< iterations {
		timer.begin()
		_ = try JustHTML(entityHtml)
		timer.stop()
		times.append(timer.elapsedMilliseconds)
	}

	let avgMs = times.reduce(0, +) / Double(times.count)
	let minMs = times.min() ?? 0
	let maxMs = times.max() ?? 0

	print("\nEntity-heavy HTML: \(entityHtml.count) bytes")
	print(String(format: "Parse time: %.2f ms avg (min: %.2f ms, max: %.2f ms)", avgMs, minMs, maxMs))
	print(String(format: "Throughput: %.2f KB/ms", Double(entityHtml.count) / 1024 / avgMs))

	// Count entities in sample Wikipedia file
	let wikiHtml = try loadSampleFile("wikipedia_ww2.html")
	var ampCount = 0
	for ch in wikiHtml {
		if ch == "&" { ampCount += 1 }
	}
	print("\nwikipedia_ww2.html has \(ampCount) potential entity references")

	#expect(avgMs < 200, "Entity-heavy parsing should be under 200ms")
}

@Test func profileDictionaryLookup() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("DICTIONARY LOOKUP ANALYSIS")
	print(String(repeating: "=", count: 70))

	let entityNames = ["amp", "lt", "gt", "quot", "nbsp", "copy", "reg", "trade", "hearts", "spades",
	                   "nonexistent", "notaentity", "AElig", "Aacute", "Alpha", "Beta", "Gamma", "Delta"]

	let iterations = 100_000
	var timer = PrecisionTimer()

	// Test NAMED_ENTITIES dictionary lookup
	timer.begin()
	var foundCount = 0
	for _ in 0 ..< iterations {
		for name in entityNames {
			if NAMED_ENTITIES[name] != nil {
				foundCount += 1
			}
		}
	}
	timer.stop()

	let totalLookups = iterations * entityNames.count
	let nsPerLookup = Double(timer.elapsedNanoseconds) / Double(totalLookups)

	print("\nNAMED_ENTITIES dictionary size: \(NAMED_ENTITIES.count) entries")
	print(String(format: "Total lookups: %d", totalLookups))
	print(String(format: "Total time: %.2f ms", timer.elapsedMilliseconds))
	print(String(format: "Time per lookup: %.2f ns", nsPerLookup))
	print(String(format: "Lookups per second: %.0f M", Double(totalLookups) / timer.elapsedMilliseconds * 1000 / 1_000_000))

	// Test LEGACY_ENTITIES set lookup
	timer.begin()
	var legacyFoundCount = 0
	for _ in 0 ..< iterations {
		for name in entityNames {
			if LEGACY_ENTITIES.contains(name) {
				legacyFoundCount += 1
			}
		}
	}
	timer.stop()

	let nsPerSetLookup = Double(timer.elapsedNanoseconds) / Double(totalLookups)
	print(String(format: "\nLEGACY_ENTITIES set size: %d entries", LEGACY_ENTITIES.count))
	print(String(format: "Time per lookup: %.2f ns", nsPerSetLookup))
}

@Test func profileMemoryAllocation() async throws {
	// Skip this test on CI where sample files aren't available
	guard sampleFilesAvailable() else {
		print("Skipping profileMemoryAllocation: sample files not available")
		return
	}

	print("\n" + String(repeating: "=", count: 70))
	print("MEMORY ALLOCATION ANALYSIS")
	print(String(repeating: "=", count: 70))

	let html = try loadSampleFile("wikipedia_ww2.html")

	// Parse and count nodes
	let doc = try JustHTML(html)

	func countNodes(_ node: Node) -> (elements: Int, text: Int, comments: Int, total: Int) {
		var elements = 0
		var text = 0
		var comments = 0

		switch node.name {
			case "#text": text = 1

			case "#comment": comments = 1

			case "#document", "#document-fragment", "!doctype": break

			default: elements = 1 // Element nodes have their tag name
		}

		for child in node.children {
			let childCounts = countNodes(child)
			elements += childCounts.elements
			text += childCounts.text
			comments += childCounts.comments
		}

		return (elements, text, comments, elements + text + comments)
	}

	let counts = countNodes(doc.root)

	print("\nwikipedia_ww2.html node counts:")
	print("  Element nodes: \(counts.elements)")
	print("  Text nodes: \(counts.text)")
	print("  Comment nodes: \(counts.comments)")
	print("  Total nodes: \(counts.total)")

	// Estimate allocations
	// Each Node is a class - estimate ~100 bytes overhead per instance
	let estimatedNodeBytes = counts.total * 100
	print(String(format: "\nEstimated node allocation: %.2f KB", Double(estimatedNodeBytes) / 1024))
	print(String(format: "Ratio to input size: %.2fx", Double(estimatedNodeBytes) / Double(html.utf8.count)))
}

@Test func profileScalingBehavior() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("SCALING BEHAVIOR ANALYSIS")
	print(String(repeating: "=", count: 70))

	// Generate HTML of different sizes
	func generateHTML(paragraphs: Int) -> String {
		var html = "<!DOCTYPE html><html><head><title>Test</title></head><body>"
		for i in 0 ..< paragraphs {
			html += "<p>This is paragraph \(i) with <strong>bold</strong> and <em>italic</em> text.</p>"
		}
		html += "</body></html>"
		return html
	}

	let sizes = [100, 500, 1000, 2000, 5000, 10000]
	var results: [(paragraphs: Int, sizeKB: Double, avgMs: Double)] = []

	for paragraphs in sizes {
		let html = generateHTML(paragraphs: paragraphs)
		let sizeKB = Double(html.utf8.count) / 1024
		var times: [Double] = []
		var timer = PrecisionTimer()

		// Warmup
		for _ in 0 ..< 2 {
			_ = try JustHTML(html)
		}

		// Measure
		let iterations = max(3, 50 / (paragraphs / 100))
		for _ in 0 ..< iterations {
			timer.begin()
			_ = try JustHTML(html)
			timer.stop()
			times.append(timer.elapsedMilliseconds)
		}

		let avgMs = times.reduce(0, +) / Double(times.count)
		results.append((paragraphs, sizeKB, avgMs))
	}

	print("\n| Paragraphs | Size | Parse Time | Time/KB | Ratio to Linear |")
	print("|------------|------|------------|---------|-----------------|")

	let baselineTimePerKB = results[0].avgMs / results[0].sizeKB

	for r in results {
		let timePerKB = r.avgMs / r.sizeKB
		let ratioToLinear = timePerKB / baselineTimePerKB
		print(String(format: "| %d | %.1f KB | %.2f ms | %.3f ms/KB | %.2fx |",
		             r.paragraphs, r.sizeKB, r.avgMs, timePerKB, ratioToLinear))
	}

	// Check for non-linear scaling
	let firstRatio = results[0].avgMs / results[0].sizeKB
	let lastRatio = results.last!.avgMs / results.last!.sizeKB
	let scalingFactor = lastRatio / firstRatio

	print(String(format: "\nScaling factor (10000 vs 100 paragraphs): %.2fx", scalingFactor))
	if scalingFactor > 1.5 {
		print("⚠️ WARNING: Non-linear scaling detected! Time per KB increases with document size.")
	}
	else {
		print("✅ Linear scaling - time per KB is consistent")
	}
}

@Test func profileComprehensiveSummary() async throws {
	// Skip this test on CI where sample files aren't available
	guard sampleFilesAvailable() else {
		print("Skipping profileComprehensiveSummary: sample files not available")
		return
	}

	print("\n" + String(repeating: "=", count: 70))
	print("COMPREHENSIVE PERFORMANCE SUMMARY")
	print(String(repeating: "=", count: 70))

	let files = [
		("hackernews.html", "Hacker News"),
		("wikipedia_countries.html", "Wikipedia Countries"),
		("wikipedia_html.html", "Wikipedia HTML"),
		("wikipedia_swift.html", "Wikipedia Swift"),
		("wikipedia_ww2.html", "Wikipedia WW2"),
	]

	var grandTotal: Double = 0
	var grandTotalSize: Int = 0

	print("\n=== Per-File Analysis ===\n")

	for (filename, description) in files {
		let html = try loadSampleFile(filename)
		let sizeKB = html.utf8.count / 1024

		// Measure tokenizer only
		var timer = PrecisionTimer()
		timer.begin()
		var tokenCount = 0
		for _ in HTMLStream(html) {
			tokenCount += 1
		}
		timer.stop()
		let tokenizerMs = timer.elapsedMilliseconds

		// Measure full parse
		timer.begin()
		let doc = try JustHTML(html)
		timer.stop()
		let fullParseMs = timer.elapsedMilliseconds

		// Count nodes
		func countAllNodes(_ node: Node) -> Int {
			return 1 + node.children.reduce(0) { $0 + countAllNodes($1) }
		}
		let nodeCount = countAllNodes(doc.root)

		// Count entities
		var ampCount = 0
		for ch in html {
			if ch == "&" { ampCount += 1 }
		}

		print("\(description) (\(filename))")
		print("  Size: \(sizeKB) KB")
		print(String(format: "  Tokens: %d (%.0f tokens/KB)", tokenCount, Double(tokenCount) / Double(sizeKB)))
		print(String(format: "  Nodes: %d (%.0f nodes/KB)", nodeCount, Double(nodeCount) / Double(sizeKB)))
		print(String(format: "  Entities: %d (%.1f entities/KB)", ampCount, Double(ampCount) / Double(sizeKB)))
		print(String(format: "  Tokenizer: %.2f ms (%.1f%%)", tokenizerMs, tokenizerMs / fullParseMs * 100))
		print(String(format: "  Tree Builder: %.2f ms (%.1f%%)", fullParseMs - tokenizerMs, (fullParseMs - tokenizerMs) / fullParseMs * 100))
		print(String(format: "  Total: %.2f ms", fullParseMs))
		print(String(format: "  Throughput: %.2f MB/s", Double(sizeKB) / fullParseMs))
		print()

		grandTotal += fullParseMs
		grandTotalSize += sizeKB
	}

	print("=== Grand Total ===")
	print(String(format: "Total size: %d KB (%.2f MB)", grandTotalSize, Double(grandTotalSize) / 1024))
	print(String(format: "Total time: %.2f ms", grandTotal))
	print(String(format: "Average throughput: %.2f MB/s", Double(grandTotalSize) / 1024 / grandTotal * 1000))
}

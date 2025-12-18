// ProfilingTests.swift - Performance profiling for identifying hot paths

import Foundation
import Testing
@testable import justhtml

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
			print(
				String(
					format: "%@: %.2fms total, %d calls, %.2fµs avg (min: %.2fµs, max: %.2fµs)",
					name, totalMs, data.count, avgUs, minUs, maxUs))
		}
	}

	func reset() {
		self.timings.removeAll()
	}
}

// MARK: - Sample File Loader

private let kSampleFilesBasePath =
	"/home/kyle/Development/justhtml/swift-justhtml/Benchmarks/samples"

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

	var results:
		[(name: String, sizeKB: Int, avgMs: Double, minMs: Double, maxMs: Double, iterations: Int)] = []

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
		print(
			String(
				format: "| %@ | %d KB | %.2f ms | %.2f ms | %.2f ms | %.2f MB/s |",
				r.name, r.sizeKB, r.avgMs, r.minMs, r.maxMs, throughputMB))
		totalMs += r.avgMs
		totalKB += r.sizeKB
	}

	let avgThroughput = Double(totalKB) / totalMs * 1000 / 1024
	print(
		String(
			format: "| **TOTAL** | %d KB | %.2f ms | - | - | %.2f MB/s |", totalKB, totalMs, avgThroughput
		))

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
	print(
		String(
			format: "Tokenizer only:    %.2f ms (%.1f%%)", tokenizerAvg, tokenizerAvg / fullParseAvg * 100
		))
	print(
		String(
			format: "Tree builder:      %.2f ms (%.1f%%)", treeBuilderAvg,
			treeBuilderAvg / fullParseAvg * 100))
	print(String(format: "Full parse:        %.2f ms (100%%)", fullParseAvg))

	#expect(fullParseAvg < 500, "Full parse should be under 500ms")
}

@Test func profileStringOperations() async throws {
	// Skip this test on CI where sample files aren't available
	guard sampleFilesAvailable() else {
		print("Skipping profileStringOperations: sample files not available")
		return
	}

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

@Test func profileDictionaryLookup() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("DICTIONARY LOOKUP ANALYSIS")
	print(String(repeating: "=", count: 70))

	let entityNames = [
		"amp", "lt", "gt", "quot", "nbsp", "copy", "reg", "trade", "hearts", "spades",
		"nonexistent", "notaentity", "AElig", "Aacute", "Alpha", "Beta", "Gamma", "Delta",
	]

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
	print(
		String(
			format: "Lookups per second: %.0f M",
			Double(totalLookups) / timer.elapsedMilliseconds * 1000 / 1_000_000))

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
	print(
		String(
			format: "Ratio to input size: %.2fx", Double(estimatedNodeBytes) / Double(html.utf8.count)))
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
		print(
			String(
				format: "| %d | %.1f KB | %.2f ms | %.3f ms/KB | %.2fx |",
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
		print(
			String(
				format: "  Tokens: %d (%.0f tokens/KB)", tokenCount, Double(tokenCount) / Double(sizeKB)))
		print(
			String(format: "  Nodes: %d (%.0f nodes/KB)", nodeCount, Double(nodeCount) / Double(sizeKB)))
		print(
			String(
				format: "  Entities: %d (%.1f entities/KB)", ampCount, Double(ampCount) / Double(sizeKB)))
		print(
			String(format: "  Tokenizer: %.2f ms (%.1f%%)", tokenizerMs, tokenizerMs / fullParseMs * 100))
		print(
			String(
				format: "  Tree Builder: %.2f ms (%.1f%%)", fullParseMs - tokenizerMs,
				(fullParseMs - tokenizerMs) / fullParseMs * 100))
		print(String(format: "  Total: %.2f ms", fullParseMs))
		print(String(format: "  Throughput: %.2f MB/s", Double(sizeKB) / fullParseMs))
		print()

		grandTotal += fullParseMs
		grandTotalSize += sizeKB
	}

	print("=== Grand Total ===")
	print(
		String(format: "Total size: %d KB (%.2f MB)", grandTotalSize, Double(grandTotalSize) / 1024))
	print(String(format: "Total time: %.2f ms", grandTotal))
	print(
		String(
			format: "Average throughput: %.2f MB/s", Double(grandTotalSize) / 1024 / grandTotal * 1000))
}

// MARK: - Tokenizer Micro-Benchmarks

@Test func profileTokenizerMicroBenchmarks() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("TOKENIZER MICRO-BENCHMARKS")
	print(String(repeating: "=", count: 70))

	// Test 1: Pure text scanning speed (no tags, no entities)
	let pureText = String(repeating: "Hello world this is a test. ", count: 10000)
	let pureTextHTML = "<!DOCTYPE html><html><body>\(pureText)</body></html>"

	// Test 2: Tag-heavy content (many short tags)
	var tagHeavy = "<!DOCTYPE html><html><body>"
	for i in 0 ..< 5000 {
		tagHeavy += "<span>x\(i)</span>"
	}
	tagHeavy += "</body></html>"

	// Test 3: Attribute-heavy content
	var attrHeavy = "<!DOCTYPE html><html><body>"
	for i in 0 ..< 2000 {
		attrHeavy += "<div id=\"id\(i)\" class=\"cls\(i)\" data-value=\"val\(i)\">x</div>"
	}
	attrHeavy += "</body></html>"

	// Test 4: Entity-heavy content
	var entityHeavy = "<!DOCTYPE html><html><body>"
	for i in 0 ..< 2000 {
		entityHeavy += "<p>&amp;\(i) &lt; &gt; &quot;</p>"
	}
	entityHeavy += "</body></html>"

	// Test 5: Whitespace-heavy content
	let whitespace = String(repeating: " \t\n", count: 5000)
	let whitespaceHTML = "<!DOCTYPE html><html><body>\(whitespace)</body></html>"

	let testCases = [
		("Pure text (300KB)", pureTextHTML),
		("Tag-heavy (5000 spans)", tagHeavy),
		("Attribute-heavy (2000 divs)", attrHeavy),
		("Entity-heavy (2000 entities)", entityHeavy),
		("Whitespace-heavy", whitespaceHTML),
	]

	print("\n| Test Case | Size | Parse Time | Throughput |")
	print("|-----------|------|------------|------------|")

	for (name, html) in testCases {
		let iterations = 10
		var times: [Double] = []
		var timer = PrecisionTimer()

		// Warmup
		for _ in 0 ..< 3 {
			_ = try JustHTML(html)
		}

		// Measure
		for _ in 0 ..< iterations {
			timer.begin()
			_ = try JustHTML(html)
			timer.stop()
			times.append(timer.elapsedMilliseconds)
		}

		let avgMs = times.reduce(0, +) / Double(times.count)
		let sizeKB = html.utf8.count / 1024
		let throughput = Double(sizeKB) / avgMs * 1000 / 1024 // MB/s

		let namePadded = name.padding(toLength: 28, withPad: " ", startingAt: 0)
		print(
			"| \(namePadded) | \(String(format: "%4dKB", sizeKB)) | \(String(format: "%8.2f ms", avgMs)) | \(String(format: "%6.2f MB/s", throughput)) |"
		)
	}

	print("\n=== Analysis ===")
	print("Compare throughput across test cases to identify bottlenecks:")
	print("- If 'Pure text' is much faster → tag parsing is the bottleneck")
	print("- If 'Tag-heavy' is slow → state machine overhead is high")
	print("- If 'Entity-heavy' is slow → entity decoding is expensive")
	print("- If 'Attribute-heavy' is slow → attribute parsing needs work")
}

@Test func profileTokenizerOperations() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("TOKENIZER OPERATION COSTS")
	print(String(repeating: "=", count: 70))

	let iterations = 100_000

	// Test: String append (character)
	var timer = PrecisionTimer()
	var str1 = ""
	str1.reserveCapacity(iterations)
	timer.begin()
	for _ in 0 ..< iterations {
		str1.append("x")
	}
	timer.stop()
	let strAppendCharNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: String append (string)
	var str2 = ""
	str2.reserveCapacity(iterations * 5)
	timer.begin()
	for _ in 0 ..< iterations {
		str2.append("hello")
	}
	timer.stop()
	let strAppendStrNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: Byte array append
	var bytes1 = ContiguousArray<UInt8>()
	bytes1.reserveCapacity(iterations)
	timer.begin()
	for _ in 0 ..< iterations {
		bytes1.append(0x78) // 'x'
	}
	timer.stop()
	let byteAppendNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: Byte array append contiguous
	var bytes2 = ContiguousArray<UInt8>()
	bytes2.reserveCapacity(iterations * 5)
	let fiveBytes: [UInt8] = [0x68, 0x65, 0x6c, 0x6c, 0x6f] // "hello"
	timer.begin()
	for _ in 0 ..< iterations {
		bytes2.append(contentsOf: fiveBytes)
	}
	timer.stop()
	let byteAppendMultiNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: String(decoding:as:) conversion
	let testBytes = ContiguousArray<UInt8>(repeating: 0x78, count: 100)
	timer.begin()
	for _ in 0 ..< iterations {
		let _ = String(decoding: testBytes, as: UTF8.self)
	}
	timer.stop()
	let strDecodeNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: Character creation from UInt8
	timer.begin()
	for _ in 0 ..< iterations {
		let _ = Character(UnicodeScalar(0x78))
	}
	timer.stop()
	let charCreateNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: Dictionary lookup
	let dict: [String: Int] = ["amp": 1, "lt": 2, "gt": 3, "nbsp": 4]
	timer.begin()
	for _ in 0 ..< iterations {
		let _ = dict["amp"]
	}
	timer.stop()
	let dictLookupNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test: Set contains
	let set: Set<String> = ["div", "span", "p", "a", "table"]
	timer.begin()
	for _ in 0 ..< iterations {
		let _ = set.contains("div")
	}
	timer.stop()
	let setContainsNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	print()
	print("Operation costs (nanoseconds per operation):")
	print(String(format: "  String.append(char):       %6.1f ns", strAppendCharNs))
	print(String(format: "  String.append(string):     %6.1f ns", strAppendStrNs))
	print(String(format: "  Byte array append:         %6.1f ns", byteAppendNs))
	print(String(format: "  Byte array append multi:   %6.1f ns", byteAppendMultiNs))
	print(String(format: "  String(decoding:) 100B:    %6.1f ns", strDecodeNs))
	print(String(format: "  Character creation:        %6.1f ns", charCreateNs))
	print(String(format: "  Dictionary lookup:         %6.1f ns", dictLookupNs))
	print(String(format: "  Set.contains:              %6.1f ns", setContainsNs))

	print()
	print("Key insights:")
	print(
		String(
			format: "  Byte append is %.1fx faster than String.append(char)",
			strAppendCharNs / byteAppendNs))
	print(
		String(format: "  Batch String decode is %.1f ns per char (for 100 chars)", strDecodeNs / 100.0)
	)
}

@Test func profileInputScanningStrategies() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("INPUT SCANNING STRATEGY COMPARISON")
	print(String(repeating: "=", count: 70))

	guard sampleFilesAvailable() else {
		print("Skipping: sample files not available")
		return
	}

	let html = try loadSampleFile("wikipedia_ww2.html")
	let bytes = ContiguousArray(html.utf8)
	let iterations = 100

	var timer = PrecisionTimer()

	// Strategy 1: Scan for '<' using byte comparison
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for byte in bytes {
			if byte == 0x3C { count += 1 }
		}
		_ = count
	}
	timer.stop()
	let byteScanMs = timer.elapsedMilliseconds / Double(iterations)

	// Strategy 2: Scan using array index
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for i in 0 ..< bytes.count {
			if bytes[i] == 0x3C { count += 1 }
		}
		_ = count
	}
	timer.stop()
	let indexScanMs = timer.elapsedMilliseconds / Double(iterations)

	// Strategy 3: Scan using withUnsafeBufferPointer
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		bytes.withUnsafeBufferPointer { ptr in
			for i in 0 ..< ptr.count {
				if ptr[i] == 0x3C { count += 1 }
			}
		}
		_ = count
	}
	timer.stop()
	let unsafeScanMs = timer.elapsedMilliseconds / Double(iterations)

	// Strategy 4: Character iteration
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for ch in html {
			if ch == "<" { count += 1 }
		}
		_ = count
	}
	timer.stop()
	let charScanMs = timer.elapsedMilliseconds / Double(iterations)

	print()
	print("Scanning for '<' in wikipedia_ww2.html (1.2MB):")
	print(String(format: "  Byte iteration:            %6.2f ms", byteScanMs))
	print(String(format: "  Index-based access:        %6.2f ms", indexScanMs))
	print(String(format: "  Unsafe buffer pointer:     %6.2f ms", unsafeScanMs))
	print(String(format: "  Character iteration:       %6.2f ms", charScanMs))
	print()
	print(String(format: "Character scan is %.1fx slower than byte scan", charScanMs / byteScanMs))
	print(String(format: "Unsafe pointer is %.2fx vs index-based", indexScanMs / unsafeScanMs))
}

// MARK: - Tree Builder Micro-Benchmarks

@Test func profileTreeBuilderOperations() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("TREE BUILDER OPERATION COSTS")
	print(String(repeating: "=", count: 70))

	let iterations = 100_000
	var timer = PrecisionTimer()

	// Test 1: Node creation cost
	timer.begin()
	for _ in 0 ..< iterations {
		let node = Node(name: "div", namespace: .html)
		_ = node
	}
	timer.stop()
	let nodeCreateNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test 2: Node creation with attributes
	timer.begin()
	for _ in 0 ..< iterations {
		let node = Node(name: "div", namespace: .html, attrs: ["id": "test", "class": "foo bar"])
		_ = node
	}
	timer.stop()
	let nodeWithAttrsNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test 3: appendChild cost
	let parent = Node(name: "div")
	let children: [Node] = (0 ..< iterations).map { _ in Node(name: "span") }
	timer.begin()
	for child in children {
		parent.appendChild(child)
	}
	timer.stop()
	let appendChildNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	// Test 4: Array push/pop (simulating open elements stack)
	var stack: [Node] = []
	stack.reserveCapacity(100)
	let stackNodes: [Node] = (0 ..< 100).map { _ in Node(name: "div") }
	timer.begin()
	for _ in 0 ..< iterations {
		for node in stackNodes {
			stack.append(node)
		}
		for _ in 0 ..< stackNodes.count {
			_ = stack.removeLast()
		}
	}
	timer.stop()
	let stackOpsNs =
		Double(timer.elapsedNanoseconds) / Double(iterations) / Double(stackNodes.count * 2)

	// Test 5: String comparison (tag name matching)
	let tagNames = ["div", "span", "p", "a", "script", "style", "table", "tr", "td"]
	let testTag = "table"
	timer.begin()
	var matchCount = 0
	for _ in 0 ..< iterations {
		for tag in tagNames {
			if tag == testTag { matchCount += 1 }
		}
	}
	timer.stop()
	let stringCompareNs = Double(timer.elapsedNanoseconds) / Double(iterations * tagNames.count)

	// Test 6: TagID comparison (integer matching)
	let tagIds: [TagID] = [.div, .span, .p, .a, .script, .style, .table, .tr, .td]
	let testTagId = TagID.table
	timer.begin()
	var tagIdMatchCount = 0
	for _ in 0 ..< iterations {
		for tagId in tagIds {
			if tagId == testTagId { tagIdMatchCount += 1 }
		}
	}
	timer.stop()
	let tagIdCompareNs = Double(timer.elapsedNanoseconds) / Double(iterations * tagIds.count)

	// Test 7: Text node creation
	timer.begin()
	for _ in 0 ..< iterations {
		let node = Node(name: "#text", data: .text("Sample text content"))
		_ = node
	}
	timer.stop()
	let textNodeCreateNs = Double(timer.elapsedNanoseconds) / Double(iterations)

	print("\nOperation costs (nanoseconds per operation):")
	print(String(format: "  Node creation:           %6.1f ns", nodeCreateNs))
	print(String(format: "  Node with attrs:         %6.1f ns", nodeWithAttrsNs))
	print(String(format: "  Text node creation:      %6.1f ns", textNodeCreateNs))
	print(String(format: "  appendChild:             %6.1f ns", appendChildNs))
	print(String(format: "  Stack push/pop:          %6.1f ns", stackOpsNs))
	print(String(format: "  String comparison:       %6.1f ns", stringCompareNs))
	print(String(format: "  TagID comparison:        %6.1f ns", tagIdCompareNs))
	print()
	print(
		String(format: "TagID is %.1fx faster than string comparison", stringCompareNs / tagIdCompareNs)
	)
	print(
		String(format: "Attrs add %.1f ns overhead to node creation", nodeWithAttrsNs - nodeCreateNs))
}

/// Use @inline(never) to prevent optimizer from eliminating benchmark code
@inline(never)
func blackhole<T>(_ x: T) {
	// Prevent dead code elimination
}

@Test func profileScopeCheckingStrategies() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("SCOPE CHECKING STRATEGIES")
	print(String(repeating: "=", count: 70))

	// Simulate open elements stack with typical HTML structure
	let stackSizes = [5, 10, 20, 50]
	let iterations = 1_000_000
	var timer = PrecisionTimer()

	print("\n| Strategy | Stack=5 | Stack=10 | Stack=20 | Stack=50 |")
	print("|----------|---------|----------|----------|----------|")

	// Strategy 1: Linear search with string comparison (current approach)
	var linearStringResults: [Double] = []
	for stackSize in stackSizes {
		let stack: [String] = (0 ..< stackSize).map { i in
			["html", "body", "div", "p", "span", "a", "ul", "li", "table", "tr"][i % 10]
		}
		let target = "p"

		timer.begin()
		var found = 0
		for _ in 0 ..< iterations {
			for name in stack.reversed() {
				if name == target {
					found += 1
					break
				}
			}
		}
		timer.stop()
		blackhole(found)
		linearStringResults.append(Double(timer.elapsedNanoseconds) / Double(iterations))
	}

	// Strategy 2: Linear search with TagID comparison
	var linearTagIdResults: [Double] = []
	for stackSize in stackSizes {
		let stack: [TagID] = (0 ..< stackSize).map { i in
			[TagID.html, .body, .div, .p, .span, .a, .ul, .li, .table, .tr][i % 10]
		}
		let target = TagID.p

		timer.begin()
		var found = 0
		for _ in 0 ..< iterations {
			for tagId in stack.reversed() {
				if tagId == target {
					found += 1
					break
				}
			}
		}
		timer.stop()
		blackhole(found)
		linearTagIdResults.append(Double(timer.elapsedNanoseconds) / Double(iterations))
	}

	// Strategy 3: Set lookup for existence (O(1))
	var setLookupResults: [Double] = []
	for stackSize in stackSizes {
		var tagSet: Set<TagID> = []
		for i in 0 ..< stackSize {
			tagSet.insert([TagID.html, .body, .div, .p, .span, .a, .ul, .li, .table, .tr][i % 10])
		}
		let target = TagID.p

		timer.begin()
		var found = 0
		for _ in 0 ..< iterations {
			if tagSet.contains(target) {
				found += 1
			}
		}
		timer.stop()
		blackhole(found)
		setLookupResults.append(Double(timer.elapsedNanoseconds) / Double(iterations))
	}

	// Strategy 4: Bitmap for common tags (very fast)
	var bitmapResults: [Double] = []
	for stackSize in stackSizes {
		var bitmap: UInt64 = 0
		for i in 0 ..< stackSize {
			let tagId = [TagID.html, .body, .div, .p, .span, .a, .ul, .li, .table, .tr][i % 10]
			bitmap |= (1 << tagId.rawValue)
		}
		let target = TagID.p

		timer.begin()
		var found = 0
		for _ in 0 ..< iterations {
			if (bitmap & (1 << target.rawValue)) != 0 {
				found += 1
			}
		}
		timer.stop()
		blackhole(found)
		bitmapResults.append(Double(timer.elapsedNanoseconds) / Double(iterations))
	}

	// Print results
	print(
		String(
			format: "| Linear (String) | %5.1f ns | %6.1f ns | %6.1f ns | %6.1f ns |",
			linearStringResults[0], linearStringResults[1], linearStringResults[2], linearStringResults[3]
		))
	print(
		String(
			format: "| Linear (TagID)  | %5.1f ns | %6.1f ns | %6.1f ns | %6.1f ns |",
			linearTagIdResults[0], linearTagIdResults[1], linearTagIdResults[2], linearTagIdResults[3]))
	print(
		String(
			format: "| Set<TagID>      | %5.1f ns | %6.1f ns | %6.1f ns | %6.1f ns |",
			setLookupResults[0], setLookupResults[1], setLookupResults[2], setLookupResults[3]))
	print(
		String(
			format: "| Bitmap (UInt64) | %5.1f ns | %6.1f ns | %6.1f ns | %6.1f ns |",
			bitmapResults[0], bitmapResults[1], bitmapResults[2], bitmapResults[3]))

	print("\n=== Analysis ===")
	let tagIdSpeedup = linearStringResults[2] / max(linearTagIdResults[2], 0.1)
	let setSpeedup = linearStringResults[2] / max(setLookupResults[2], 0.1)
	let bitmapSpeedup = linearStringResults[2] / max(bitmapResults[2], 0.1)
	print(
		String(
			format: "At stack depth 20: TagID linear is %.1fx faster than String linear", tagIdSpeedup))
	print(
		String(format: "At stack depth 20: Set lookup is %.1fx faster than String linear", setSpeedup))
	print(
		String(format: "At stack depth 20: Bitmap is %.1fx faster than String linear", bitmapSpeedup))
}

@Test func profileTreeBuilderSimulation() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("TREE BUILDER SIMULATION")
	print(String(repeating: "=", count: 70))

	// Simulate processing a document with N tags
	let tagCounts = [1000, 5000, 10000, 30000]
	var timer = PrecisionTimer()

	print("\n| Tags | Node Creation | appendChild | Scope Checks | Total Overhead |")
	print("|------|---------------|-------------|--------------|----------------|")

	for tagCount in tagCounts {
		// Simulate node creation
		timer.begin()
		var nodes: [Node] = []
		nodes.reserveCapacity(tagCount)
		for i in 0 ..< tagCount {
			let name = ["div", "p", "span", "a", "li"][i % 5]
			nodes.append(Node(name: name, namespace: .html))
		}
		timer.stop()
		let createMs = timer.elapsedMilliseconds

		// Simulate appendChild (building tree)
		let root = Node(name: "html")
		var stack: [Node] = [root]
		timer.begin()
		for node in nodes {
			stack.last!.appendChild(node)
			// Simulate typical stack depth changes
			if node.name == "div" {
				stack.append(node)
			}
			else if stack.count > 3, node.name == "a" {
				_ = stack.popLast()
			}
		}
		timer.stop()
		let appendMs = timer.elapsedMilliseconds

		// Simulate scope checking (estimate based on typical call frequency)
		// Assume ~2 scope checks per tag on average
		let scopeCheckCount = tagCount * 2
		let avgStackDepth = 10
		timer.begin()
		var scopeFound = 0
		for _ in 0 ..< scopeCheckCount {
			// Simulate linear search through stack
			for j in (0 ..< min(avgStackDepth, stack.count)).reversed() {
				if stack[j].tagId == .p {
					scopeFound += 1
					break
				}
			}
		}
		timer.stop()
		_ = scopeFound
		let scopeMs = timer.elapsedMilliseconds

		let totalMs = createMs + appendMs + scopeMs

		print(
			String(
				format: "| %5d | %11.2f ms | %9.2f ms | %10.2f ms | %12.2f ms |",
				tagCount, createMs, appendMs, scopeMs, totalMs))
	}

	print("\nNote: Real tree builder has additional overhead from:")
	print("  - Mode switching (large switch statements)")
	print("  - Implied end tags generation")
	print("  - Active formatting elements")
	print("  - Foster parenting")
	print("  - String comparisons in tag matching")
}

@Test func profileTagDispatchCost() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("TAG DISPATCH COST ANALYSIS")
	print(String(repeating: "=", count: 70))

	// Simulate the tag names found in a typical document
	// Distribution based on actual Wikipedia pages
	let tagDistribution: [(String, Int)] = [
		("span", 3000),
		("a", 2000),
		("div", 1500),
		("li", 1000),
		("p", 500),
		("td", 400),
		("tr", 200),
		("table", 50),
		("img", 100),
		("br", 100),
		("b", 200),
		("i", 150),
		("script", 20),
		("style", 5),
		("html", 1),
		("head", 1),
		("body", 1),
	]

	var allTags: [String] = []
	for (tag, count) in tagDistribution {
		allTags.append(contentsOf: Array(repeating: tag, count: count))
	}
	allTags.shuffle() // Randomize order

	let iterations = 10
	var timer = PrecisionTimer()

	// Sets used in processStartTagInBody (simulating the actual checks)
	let headTags: Set<String> = [
		"base", "basefont", "bgsound", "link", "meta", "noframes", "script", "style", "template",
		"title",
	]
	let blockTags: Set<String> = [
		"address", "article", "aside", "blockquote", "center", "details", "dialog", "dir", "div",
		"dl", "fieldset", "figcaption", "figure", "footer", "header", "hgroup", "main", "menu", "nav",
		"ol", "p", "search", "section", "summary", "ul",
	]
	let headingTags: Set<String> = ["h1", "h2", "h3", "h4", "h5", "h6"]
	let formattingTags: Set<String> = [
		"b", "big", "code", "em", "font", "i", "s", "small", "strike", "strong", "tt", "u",
	]
	let voidTags: Set<String> = ["area", "br", "embed", "img", "keygen", "wbr"]
	let tableTags: Set<String> = [
		"caption", "col", "colgroup", "frame", "head", "tbody", "td", "tfoot", "th", "thead", "tr",
	]

	// Strategy 1: String-based if/else chain (current approach)
	var result1 = 0
	timer.begin()
	for _ in 0 ..< iterations {
		for name in allTags {
			// Simulate the processStartTagInBody dispatch
			if name == "html" {
				result1 += 1
			}
			else if headTags.contains(name) {
				result1 += 2
			}
			else if name == "body" {
				result1 += 3
			}
			else if name == "frameset" {
				result1 += 4
			}
			else if blockTags.contains(name) {
				result1 += 5
			}
			else if headingTags.contains(name) {
				result1 += 6
			}
			else if name == "form" {
				result1 += 7
			}
			else if name == "li" {
				result1 += 8
			}
			else if name == "button" {
				result1 += 9
			}
			else if name == "a" {
				result1 += 10
			}
			else if formattingTags.contains(name) {
				result1 += 11
			}
			else if name == "table" {
				result1 += 12
			}
			else if voidTags.contains(name) {
				result1 += 13
			}
			else if name == "input" {
				result1 += 14
			}
			else if tableTags.contains(name) {
				result1 += 15
			}
			else {
				result1 += 16
			}
		}
	}
	timer.stop()
	let stringDispatchMs = timer.elapsedMilliseconds / Double(iterations)
	blackhole(result1)

	// Strategy 2: TagID-based switch (proposed optimization)
	// Convert tags to TagIDs once
	let tagIDs = allTags.map { TagID.from($0) }

	let headTagIDs: Set<TagID> = [
		.base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title,
	]
	let blockTagIDs: Set<TagID> = [
		.address, .article, .aside, .blockquote, .center, .details, .dialog, .div,
		.dl, .fieldset, .figcaption, .figure, .footer, .header, .main, .menu, .nav,
		.ol, .p, .search, .section, .summary, .ul,
	]
	let headingTagIDs: Set<TagID> = [.h1, .h2, .h3, .h4, .h5, .h6]
	let formattingTagIDs: Set<TagID> = [
		.b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u,
	]
	let voidTagIDs: Set<TagID> = [.area, .br, .embed, .img, .keygen, .wbr]
	let tableTagIDs: Set<TagID> = [
		.caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr,
	]

	var result2 = 0
	timer.begin()
	for _ in 0 ..< iterations {
		for tagId in tagIDs {
			// Simulate TagID-based dispatch
			if tagId == .html {
				result2 += 1
			}
			else if headTagIDs.contains(tagId) {
				result2 += 2
			}
			else if tagId == .body {
				result2 += 3
			}
			else if tagId == .frameset {
				result2 += 4
			}
			else if blockTagIDs.contains(tagId) {
				result2 += 5
			}
			else if headingTagIDs.contains(tagId) {
				result2 += 6
			}
			else if tagId == .form {
				result2 += 7
			}
			else if tagId == .li {
				result2 += 8
			}
			else if tagId == .button {
				result2 += 9
			}
			else if tagId == .a {
				result2 += 10
			}
			else if formattingTagIDs.contains(tagId) {
				result2 += 11
			}
			else if tagId == .table {
				result2 += 12
			}
			else if voidTagIDs.contains(tagId) {
				result2 += 13
			}
			else if tagId == .input {
				result2 += 14
			}
			else if tableTagIDs.contains(tagId) {
				result2 += 15
			}
			else {
				result2 += 16
			}
		}
	}
	timer.stop()
	let tagIdDispatchMs = timer.elapsedMilliseconds / Double(iterations)
	blackhole(result2)

	// Strategy 3: TagID switch statement (potential for jump table)
	var result3 = 0
	timer.begin()
	for _ in 0 ..< iterations {
		for tagId in tagIDs {
			switch tagId {
				case .html:
					result3 += 1

				case .base, .basefont, .bgsound, .link, .meta, .noframes, .script, .style, .template, .title:
					result3 += 2

				case .body:
					result3 += 3

				case .frameset:
					result3 += 4

				case .address, .article, .aside, .blockquote, .center, .details, .dialog, .div,
				     .dl, .fieldset, .figcaption, .figure, .footer, .header, .main, .menu, .nav,
				     .ol, .p, .search, .section, .summary, .ul:
					result3 += 5

				case .h1, .h2, .h3, .h4, .h5, .h6:
					result3 += 6

				case .form:
					result3 += 7

				case .li:
					result3 += 8

				case .button:
					result3 += 9

				case .a:
					result3 += 10

				case .b, .big, .code, .em, .font, .i, .s, .small, .strike, .strong, .tt, .u:
					result3 += 11

				case .table:
					result3 += 12

				case .area, .br, .embed, .img, .keygen, .wbr:
					result3 += 13

				case .input:
					result3 += 14

				case .caption, .col, .colgroup, .frame, .head, .tbody, .td, .tfoot, .th, .thead, .tr:
					result3 += 15

				default:
					result3 += 16
			}
		}
	}
	timer.stop()
	let switchDispatchMs = timer.elapsedMilliseconds / Double(iterations)
	blackhole(result3)

	print("\nTag dispatch cost for \(allTags.count) tags:")
	print(String(format: "  String if/else chain:    %.3f ms", stringDispatchMs))
	print(String(format: "  TagID if/else chain:     %.3f ms", tagIdDispatchMs))
	print(String(format: "  TagID switch statement:  %.3f ms", switchDispatchMs))
	print()
	print(
		String(format: "Speedup (TagID if/else vs String): %.1fx", stringDispatchMs / tagIdDispatchMs))
	print(
		String(format: "Speedup (TagID switch vs String):  %.1fx", stringDispatchMs / switchDispatchMs))
	print()
	print("Per-tag costs:")
	print(
		String(
			format: "  String if/else:    %.1f ns/tag",
			stringDispatchMs * 1_000_000 / Double(allTags.count)))
	print(
		String(
			format: "  TagID if/else:     %.1f ns/tag",
			tagIdDispatchMs * 1_000_000 / Double(allTags.count)))
	print(
		String(
			format: "  TagID switch:      %.1f ns/tag",
			switchDispatchMs * 1_000_000 / Double(allTags.count)))
}

// MARK: - Detailed Component Profiling

@Test func profileDetailedComponentBreakdown() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("DETAILED COMPONENT BREAKDOWN")
	print(String(repeating: "=", count: 70))

	guard sampleFilesAvailable() else {
		print("Skipping: sample files not available")
		return
	}

	let html = try loadSampleFile("wikipedia_ww2.html")
	let sizeKB = Double(html.utf8.count) / 1024.0
	var timer = PrecisionTimer()

	// Measure full parse
	timer.begin()
	let doc = try JustHTML(html)
	timer.stop()
	let fullParseMs = timer.elapsedMilliseconds
	_ = doc

	// Measure tokenizer only (using HTMLStream which collects tokens)
	timer.begin()
	var tokenCount = 0
	for _ in HTMLStream(html) {
		tokenCount += 1
	}
	timer.stop()
	let tokenizerMs = timer.elapsedMilliseconds

	// Calculate tree builder time
	let treeBuilderMs = fullParseMs - tokenizerMs

	print("\n=== HIGH-LEVEL BREAKDOWN (wikipedia_ww2.html) ===")
	print(String(format: "File size: %.0f KB", sizeKB))
	print(String(format: "Total parse time: %.2f ms", fullParseMs))
	print(
		String(
			format: "  Tokenizer:     %.2f ms (%.1f%%)", tokenizerMs, tokenizerMs / fullParseMs * 100))
	print(
		String(
			format: "  Tree Builder:  %.2f ms (%.1f%%)", treeBuilderMs, treeBuilderMs / fullParseMs * 100)
	)

	// Count document statistics
	var elementCount = 0
	var textCount = 0
	var attrCount = 0
	var totalAttrBytes = 0

	func countNodes(_ node: Node) {
		switch node.name {
			case "#text":
				textCount += 1

			case "#comment", "#document", "#document-fragment", "!doctype":
				break

			default:
				// Element node
				elementCount += 1
				attrCount += node.attrs.count
				for (k, v) in node.attrs {
					totalAttrBytes += k.utf8.count + v.utf8.count
				}
		}
		for child in node.children {
			countNodes(child)
		}
	}
	countNodes(doc.root)

	// Count tokens by type
	var startTags = 0
	var endTags = 0
	var charTokens = 0
	var commentTokens = 0
	var entityRefs = 0

	for event in HTMLStream(html) {
		switch event {
			case .start: startTags += 1

			case .end: endTags += 1

			case let .text(t):
				charTokens += 1
				// Count & characters as potential entity refs
				entityRefs += t.filter { $0 == "&" }.count

			case .comment: commentTokens += 1

			case .doctype: break
		}
	}

	print("\n=== DOCUMENT STATISTICS ===")
	print("Elements: \(elementCount)")
	print("Text nodes: \(textCount)")
	print("Total attributes: \(attrCount)")
	print("Attribute bytes: \(totalAttrBytes)")
	print("Start tags: \(startTags)")
	print("End tags: \(endTags)")
	print("Text tokens: \(charTokens)")
	print("Entity references (approx): \(entityRefs)")

	// Estimate component costs based on micro-benchmarks
	let nodeCreateNs = 43.0 // from profileTreeBuilderOperations
	let appendChildNs = 40.0
	let tagDispatchNs = 75.0 // from profileTagDispatchCost

	let nodeCreateMs = Double(elementCount + textCount) * nodeCreateNs / 1_000_000
	let appendChildMs = Double(elementCount + textCount) * appendChildNs / 1_000_000
	let tagDispatchMs = Double(startTags + endTags) * tagDispatchNs / 1_000_000

	print("\n=== ESTIMATED TREE BUILDER BREAKDOWN ===")
	print(
		String(
			format: "Node creation:     %.2f ms (%.1f%%)", nodeCreateMs,
			nodeCreateMs / treeBuilderMs * 100))
	print(
		String(
			format: "appendChild:       %.2f ms (%.1f%%)", appendChildMs,
			appendChildMs / treeBuilderMs * 100))
	print(
		String(
			format: "Tag dispatch:      %.2f ms (%.1f%%)", tagDispatchMs,
			tagDispatchMs / treeBuilderMs * 100))
	let otherMs = treeBuilderMs - nodeCreateMs - appendChildMs - tagDispatchMs
	print(
		String(format: "Other overhead:    %.2f ms (%.1f%%)", otherMs, otherMs / treeBuilderMs * 100))
	print("  (mode switching, scope checking, implied tags, formatting elements)")

	// Tokenizer breakdown estimate
	// Based on throughput differences from micro-benchmarks
	let pureTextThroughput = 125.0 // MB/s from profileTokenizerMicroBenchmarks
	let tagHeavyThroughput = 9.5 // MB/s
	let entityThroughput = 13.0 // MB/s

	// Estimate time if it were all pure text
	let pureTextMs = sizeKB / 1024.0 / pureTextThroughput * 1000.0

	print("\n=== TOKENIZER ANALYSIS ===")
	print(String(format: "Theoretical pure text time: %.2f ms", pureTextMs))
	print(String(format: "Actual tokenizer time:      %.2f ms", tokenizerMs))
	print(
		String(
			format: "Tag/entity overhead:        %.2f ms (%.1fx)", tokenizerMs - pureTextMs,
			tokenizerMs / pureTextMs))

	// Per-operation costs
	print("\n=== PER-OPERATION COSTS ===")
	print(String(format: "Per start tag:    %.1f µs", fullParseMs * 1000 / Double(startTags)))
	print(String(format: "Per end tag:      %.1f µs", fullParseMs * 1000 / Double(endTags)))
	print(
		String(
			format: "Per node:         %.1f µs", fullParseMs * 1000 / Double(elementCount + textCount)))
	print(String(format: "Per KB:           %.2f ms", fullParseMs / sizeKB))
	print(String(format: "Throughput:       %.1f MB/s", sizeKB / 1024.0 / fullParseMs * 1000))

	// Identify hotspots
	print("\n=== HOT PATH ANALYSIS ===")

	let tagParsingPct = (tokenizerMs - pureTextMs) / fullParseMs * 100
	let modeAndScopePct = otherMs / fullParseMs * 100
	let allocationPct = (nodeCreateMs + appendChildMs) / fullParseMs * 100

	print(String(format: "1. Tag parsing overhead:      %.1f%% of total", tagParsingPct))
	print(String(format: "2. Mode/scope/implied tags:   %.1f%% of total", modeAndScopePct))
	print(String(format: "3. Node allocation + append:  %.1f%% of total", allocationPct))
	print(
		String(
			format: "4. Tag dispatch (if/else):    %.1f%% of total", tagDispatchMs / fullParseMs * 100))
}

@Test func profileTokenizerStateTransitions() async throws {
	print("\n" + String(repeating: "=", count: 70))
	print("TOKENIZER STATE TRANSITION ANALYSIS")
	print(String(repeating: "=", count: 70))

	var timer = PrecisionTimer()
	let iterations = 10

	// Test 1: Minimal state transitions (pure text)
	let pureText = String(repeating: "x", count: 100_000)
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for _ in HTMLStream(pureText) {
			count += 1
		}
		blackhole(count)
	}
	timer.stop()
	let pureTextMs = timer.elapsedMilliseconds / Double(iterations)
	let pureTextThroughput = Double(pureText.utf8.count) / 1024.0 / pureTextMs * 1000

	// Test 2: Maximum state transitions (alternating tags)
	var tagHeavy = ""
	for i in 0 ..< 5000 {
		tagHeavy += "<span id=\"x\(i)\">y</span>"
	}
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for _ in HTMLStream(tagHeavy) {
			count += 1
		}
		blackhole(count)
	}
	timer.stop()
	let tagHeavyMs = timer.elapsedMilliseconds / Double(iterations)
	let tagHeavyThroughput = Double(tagHeavy.utf8.count) / 1024.0 / tagHeavyMs * 1000

	// Test 3: Entity-heavy
	var entityHeavy = ""
	for _ in 0 ..< 5000 {
		entityHeavy += "&amp;&lt;&gt;&quot;&apos;"
	}
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for _ in HTMLStream(entityHeavy) {
			count += 1
		}
		blackhole(count)
	}
	timer.stop()
	let entityHeavyMs = timer.elapsedMilliseconds / Double(iterations)
	let entityHeavyThroughput = Double(entityHeavy.utf8.count) / 1024.0 / entityHeavyMs * 1000

	// Test 4: Comment-heavy
	var commentHeavy = ""
	for _ in 0 ..< 2000 {
		commentHeavy += "<!-- This is a comment with some text -->"
	}
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for _ in HTMLStream(commentHeavy) {
			count += 1
		}
		blackhole(count)
	}
	timer.stop()
	let commentHeavyMs = timer.elapsedMilliseconds / Double(iterations)
	let commentHeavyThroughput = Double(commentHeavy.utf8.count) / 1024.0 / commentHeavyMs * 1000

	// Test 5: Attribute-heavy
	var attrHeavy = ""
	for i in 0 ..< 2000 {
		attrHeavy +=
			"<div id=\"id\(i)\" class=\"class\(i)\" data-value=\"value\(i)\" style=\"color: red;\"></div>"
	}
	timer.begin()
	for _ in 0 ..< iterations {
		var count = 0
		for _ in HTMLStream(attrHeavy) {
			count += 1
		}
		blackhole(count)
	}
	timer.stop()
	let attrHeavyMs = timer.elapsedMilliseconds / Double(iterations)
	let attrHeavyThroughput = Double(attrHeavy.utf8.count) / 1024.0 / attrHeavyMs * 1000

	print("\n| Test Case | Size | Time | Throughput | vs Pure Text |")
	print("|-----------|------|------|------------|--------------|")
	print(
		String(
			format: "| Pure text | %d KB | %.2f ms | %.1f MB/s | 1.0x |",
			pureText.utf8.count / 1024, pureTextMs, pureTextThroughput / 1024))
	print(
		String(
			format: "| Tag-heavy | %d KB | %.2f ms | %.1f MB/s | %.1fx slower |",
			tagHeavy.utf8.count / 1024, tagHeavyMs, tagHeavyThroughput / 1024,
			pureTextThroughput / tagHeavyThroughput))
	print(
		String(
			format: "| Entity-heavy | %d KB | %.2f ms | %.1f MB/s | %.1fx slower |",
			entityHeavy.utf8.count / 1024, entityHeavyMs, entityHeavyThroughput / 1024,
			pureTextThroughput / entityHeavyThroughput))
	print(
		String(
			format: "| Comment-heavy | %d KB | %.2f ms | %.1f MB/s | %.1fx slower |",
			commentHeavy.utf8.count / 1024, commentHeavyMs, commentHeavyThroughput / 1024,
			pureTextThroughput / commentHeavyThroughput))
	print(
		String(
			format: "| Attribute-heavy | %d KB | %.2f ms | %.1f MB/s | %.1fx slower |",
			attrHeavy.utf8.count / 1024, attrHeavyMs, attrHeavyThroughput / 1024,
			pureTextThroughput / attrHeavyThroughput))

	print("\n=== CONCLUSIONS ===")
	let tagOverhead = pureTextThroughput / tagHeavyThroughput
	let entityOverhead = pureTextThroughput / entityHeavyThroughput
	let attrOverhead = pureTextThroughput / attrHeavyThroughput

	if tagOverhead > entityOverhead, tagOverhead > attrOverhead {
		print("TAG PARSING is the primary bottleneck (%.1fx overhead)", tagOverhead)
	}
	else if entityOverhead > tagOverhead, entityOverhead > attrOverhead {
		print("ENTITY DECODING is the primary bottleneck (%.1fx overhead)", entityOverhead)
	}
	else {
		print("ATTRIBUTE PARSING is the primary bottleneck (%.1fx overhead)", attrOverhead)
	}
}

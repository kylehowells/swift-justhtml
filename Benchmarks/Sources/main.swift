// Cross-implementation benchmark for swift-justhtml
// Outputs JSON to stdout for comparison with Python and JavaScript implementations

import Foundation
import swift_justhtml

// MARK: - BenchmarkResult

struct BenchmarkResult: Codable {
	let file: String
	let size_bytes: Int
	let iterations: Int
	let avg_ms: Double
	let min_ms: Double
	let max_ms: Double
	let throughput_mbs: Double
	let output: String
}

// MARK: - Helper Functions

func writeStderr(_ message: String) {
	FileHandle.standardError.write(Data((message).utf8))
}

func formatNumber(_ n: Int) -> String {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - Benchmark Functions

func benchmarkFile(_ filepath: String, iterations: Int) -> BenchmarkResult {
	let url = URL(fileURLWithPath: filepath)
	let html: String
	do {
		html = try String(contentsOf: url, encoding: .utf8)
	}
	catch {
		writeStderr("Error reading file \(filepath): \(error)\n")
		exit(1)
	}

	let fileSize = html.utf8.count

	// Warmup
	let warmupIterations = min(3, iterations / 10 + 1)
	for _ in 0 ..< warmupIterations {
		_ = try? JustHTML(html)
	}

	// Benchmark
	var times: [Double] = []
	var doc: JustHTML?

	for _ in 0 ..< iterations {
		let start = Date()
		doc = try? JustHTML(html)
		let end = Date()
		times.append(end.timeIntervalSince(start))
	}

	// Get output for comparison
	let output = doc?.root.toTestFormat() ?? ""

	let avgTime = times.reduce(0, +) / Double(times.count)
	let minTime = times.min() ?? 0
	let maxTime = times.max() ?? 0
	let throughput = Double(fileSize) / avgTime / 1_000_000 // MB/s

	return BenchmarkResult(
		file: url.lastPathComponent,
		size_bytes: fileSize,
		iterations: iterations,
		avg_ms: avgTime * 1000,
		min_ms: minTime * 1000,
		max_ms: maxTime * 1000,
		throughput_mbs: throughput,
		output: output
	)
}

// MARK: - Main

func main() {
	// Find samples directory relative to executable or current directory
	let fileManager = FileManager.default
	let currentDir = fileManager.currentDirectoryPath

	var samplesDir = "\(currentDir)/Benchmarks/samples"
	if !fileManager.fileExists(atPath: samplesDir) {
		// Try relative to executable
		let executablePath = CommandLine.arguments[0]
		let executableDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent().path
		samplesDir = "\(executableDir)/../Benchmarks/samples"
	}
	if !fileManager.fileExists(atPath: samplesDir) {
		samplesDir = "\(currentDir)/samples"
	}

	guard fileManager.fileExists(atPath: samplesDir) else {
		writeStderr("Error: samples directory not found. Tried:\n")
		writeStderr("  \(currentDir)/Benchmarks/samples\n")
		writeStderr("  \(currentDir)/samples\n")
		exit(1)
	}

	var results: [BenchmarkResult] = []

	do {
		let files = try fileManager.contentsOfDirectory(atPath: samplesDir)
			.filter { $0.hasSuffix(".html") }
			.sorted()

		for filename in files {
			let filepath = "\(samplesDir)/\(filename)"

			guard let attrs = try? fileManager.attributesOfItem(atPath: filepath),
			      let fileSize = attrs[.size] as? Int
			else {
				continue
			}

			// Adjust iterations based on file size
			let iterations: Int
			if fileSize > 500_000 {
				iterations = 10
			}
			else if fileSize > 100_000 {
				iterations = 25
			}
			else {
				iterations = 50
			}

			writeStderr("Benchmarking \(filename) (\(formatNumber(fileSize)) bytes, \(iterations) iterations)...\n")
			let result = benchmarkFile(filepath, iterations: iterations)
			results.append(result)
			writeStderr("  Average: \(String(format: "%.2f", result.avg_ms)) ms, Throughput: \(String(format: "%.2f", result.throughput_mbs)) MB/s\n")
		}
	}
	catch {
		writeStderr("Error reading samples directory: \(error)\n")
		exit(1)
	}

	// Output JSON to stdout
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	if let jsonData = try? encoder.encode(results),
	   let jsonString = String(data: jsonData, encoding: .utf8)
	{
		print(jsonString)
	}
}

main()

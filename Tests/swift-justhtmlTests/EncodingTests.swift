import Foundation
import Testing
@testable import justhtml

// MARK: - EncodingTest

struct EncodingTest {
	let data: Data
	let expectedEncoding: String
}

func parseEncodingDatFile(_ data: Data) -> [EncodingTest] {
	var tests: [EncodingTest] = []
	var mode: String? = nil
	var currentData: [Data] = []
	var currentEncoding: String? = nil

	// Split by lines, keeping line endings
	var lines: [Data] = []
	var start = 0
	for i in 0 ..< data.count {
		if data[i] == 0x0A { // newline
			lines.append(data.subdata(in: start ..< (i + 1)))
			start = i + 1
		}
	}
	if start < data.count {
		lines.append(data.subdata(in: start ..< data.count))
	}

	for line in lines {
		// Strip trailing CRLF for directive checking
		var end = line.count
		while end > 0, line[end - 1] == 0x0A || line[end - 1] == 0x0D {
			end -= 1
		}
		let stripped = line.subdata(in: 0 ..< end)

		// Check for #data directive
		if stripped == Data("#data".utf8) {
			// Flush previous test
			if !currentData.isEmpty, let enc = currentEncoding {
				let combined = currentData.reduce(Data()) { $0 + $1 }
				tests.append(EncodingTest(data: combined, expectedEncoding: enc))
			}
			currentData = []
			currentEncoding = nil
			mode = "data"
			continue
		}

		// Check for #encoding directive
		if stripped == Data("#encoding".utf8) {
			mode = "encoding"
			continue
		}

		if mode == "data" {
			currentData.append(line)
		}
		else if mode == "encoding", currentEncoding == nil, !stripped.isEmpty {
			currentEncoding = String(data: stripped, encoding: .ascii)
		}
	}

	// Flush last test
	if !currentData.isEmpty, let enc = currentEncoding {
		let combined = currentData.reduce(Data()) { $0 + $1 }
		tests.append(EncodingTest(data: combined, expectedEncoding: enc))
	}

	return tests
}

func getEncodingTestsDirectory() -> URL? {
	let fileManager = FileManager.default
	let cwd = fileManager.currentDirectoryPath
	let cwdUrl = URL(fileURLWithPath: cwd)

	let possiblePaths = [
		cwdUrl.appendingPathComponent("html5lib-tests/encoding"),
		cwdUrl.appendingPathComponent("../html5lib-tests/encoding"),
	]

	for path in possiblePaths {
		if fileManager.fileExists(atPath: path.path) {
			return path
		}
	}
	return nil
}

@Test func html5libEncodingTests() async throws {
	guard let testsDir = getEncodingTestsDirectory() else {
		print("Encoding tests directory not found")
		return
	}

	let fileManager = FileManager.default
	var testFiles: [URL] = []

	if let enumerator = fileManager.enumerator(at: testsDir, includingPropertiesForKeys: nil) {
		while let url = enumerator.nextObject() as? URL {
			if url.pathExtension == "dat" {
				// Skip scripted tests
				if !url.path.contains("/scripted/") {
					testFiles.append(url)
				}
			}
		}
	}

	testFiles.sort { $0.lastPathComponent < $1.lastPathComponent }

	var totalPassed = 0
	var totalFailed = 0

	for fileURL in testFiles {
		let filename = fileURL.lastPathComponent
		guard let content = try? Data(contentsOf: fileURL) else {
			continue
		}

		let tests = parseEncodingDatFile(content)
		var passed = 0
		var failed = 0

		for (idx, test) in tests.enumerated() {
			// Normalize expected encoding
			guard let expected = normalizeEncodingLabel(test.expectedEncoding) else {
				failed += 1
				print(
					"\nFAIL: \(filename):\(idx) - could not normalize encoding label: \(test.expectedEncoding)"
				)
				continue
			}

			let result = sniffHTMLEncoding(test.data)
			if result.encoding == expected {
				passed += 1
			}
			else {
				failed += 1
				print("\nFAIL: \(filename):\(idx)")
				print("EXPECTED: \(expected) (raw: \(test.expectedEncoding))")
				print("ACTUAL: \(result.encoding)")
			}
		}

		print("  \(filename): \(passed)/\(passed + failed) passed")
		totalPassed += passed
		totalFailed += failed
	}

	let passRate = Double(totalPassed) / Double(max(1, totalPassed + totalFailed)) * 100
	print(
		"\nENCODING TESTS: \(totalPassed)/\(totalPassed + totalFailed) passed, \(totalFailed) failed"
	)
	print("Pass rate: \(String(format: "%.1f", passRate))%")
	#expect(totalPassed + totalFailed > 0, "No encoding tests were run")
	#expect(totalFailed == 0, "Expected 0 encoding test failures but got \(totalFailed)")
}

@Test func debugFailures() async throws {
	// Debug failing encoding test from file
	let fileURL = URL(
		fileURLWithPath: "/home/kyle/Development/justhtml/html5lib-tests/encoding/tests1.dat")
	guard let content = try? Data(contentsOf: fileURL) else {
		print("Could not read file")
		return
	}

	let tests = parseEncodingDatFile(content)
	print("Total tests parsed: \(tests.count)")

	// Test the failing test (index 22)
	let testIdx = 22
	let test = tests[testIdx]
	print("\nTest \(testIdx):")
	print("Expected: \(test.expectedEncoding)")
	print("Data (\(test.data.count) bytes):")
	if let str = String(data: test.data, encoding: .utf8) {
		print(str)
	}

	let result = sniffHTMLEncoding(test.data)
	print("\nResult: \(result.encoding)")

	// Also test with normalized expectation
	if let normalized = normalizeEncodingLabel(test.expectedEncoding) {
		print("Normalized expected: \(normalized)")
		print("Match: \(result.encoding == normalized)")
	}
}

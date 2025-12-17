import Foundation
import Testing
@testable import swift_justhtml

// MARK: - TokenCollector

/// Token collector sink for testing
private final class TokenCollector: TokenSink {
	var tokens: [Token] = []
	var currentNamespace: Namespace? = .html

	func processToken(_ token: Token) {
		// Coalesce consecutive character tokens
		if case let .character(newChars) = token,
		   let lastIdx = tokens.indices.last,
		   case let .character(existingChars) = tokens[lastIdx]
		{
			self.tokens[lastIdx] = .character(existingChars + newChars)
		}
		else if case .eof = token {
			// Skip EOF tokens for comparison
		}
		else {
			self.tokens.append(token)
		}
	}
}

/// Convert a Token to the html5lib test format array
private func tokenToTestArray(_ token: Token) -> [Any] {
	switch token {
		case let .doctype(dt):
			return ["DOCTYPE", dt.name ?? "", dt.publicId as Any, dt.systemId as Any, !dt.forceQuirks]

		case let .startTag(name, attrs, selfClosing):
			if selfClosing {
				return ["StartTag", name, attrs.isEmpty ? [:] as [String: String] : attrs, true]
			}
			if attrs.isEmpty {
				return ["StartTag", name, [:] as [String: String]]
			}
			return ["StartTag", name, attrs]

		case let .endTag(name):
			return ["EndTag", name]

		case let .comment(text):
			return ["Comment", text]

		case let .character(text):
			return ["Character", text]

		case .eof:
			return []
	}
}

/// Compare two token arrays for equality
private func tokensEqual(_ actual: [Any], _ expected: [Any]) -> Bool {
	guard actual.count == expected.count else { return false }

	guard let actualType = actual.first as? String,
	      let expectedType = expected.first as? String
	else {
		return false
	}

	if actualType != expectedType { return false }

	switch actualType {
		case "DOCTYPE":
			guard actual.count >= 5, expected.count >= 5 else { return false }

			let aName = actual[1] as? String ?? ""
			let eName = expected[1] as? String ?? ""
			if aName != eName { return false }

			// Compare publicId (can be null/nil or string)
			let aPublic = actual[2]
			let ePublic = expected[2]
			if !compareNullableString(aPublic, ePublic) { return false }

			// Compare systemId
			let aSystem = actual[3]
			let eSystem = expected[3]
			if !compareNullableString(aSystem, eSystem) { return false }

			// Compare correctness flag
			let aCorrect = actual[4] as? Bool ?? false
			let eCorrect = expected[4] as? Bool ?? false
			return aCorrect == eCorrect

		case "StartTag":
			guard actual.count >= 3, expected.count >= 3 else { return false }

			let aName = actual[1] as? String ?? ""
			let eName = expected[1] as? String ?? ""
			if aName != eName { return false }

			let aAttrs = actual[2] as? [String: String] ?? [:]
			let eAttrs = expected[2] as? [String: String] ?? [:]
			if aAttrs != eAttrs { return false }

			// Compare self-closing flag if present in expected
			if expected.count >= 4 {
				let eSelfClosing = (expected[3] as? Bool) ?? (expected[3] as? Int == 1)
				let aSelfClosing = actual.count >= 4 ? ((actual[3] as? Bool) ?? false) : false
				return aSelfClosing == eSelfClosing
			}
			return true

		case "EndTag":
			guard actual.count >= 2, expected.count >= 2 else { return false }

			let aName = actual[1] as? String ?? ""
			let eName = expected[1] as? String ?? ""
			return aName == eName

		case "Comment", "Character":
			guard actual.count >= 2, expected.count >= 2 else { return false }

			let aText = actual[1] as? String ?? ""
			let eText = expected[1] as? String ?? ""
			return aText == eText

		default:
			return false
	}
}

private func compareNullableString(_ a: Any, _ b: Any) -> Bool {
	let aIsNull = (a is NSNull) || (a as? String == nil && !(a is String))
	let bIsNull = (b is NSNull) || (b as? String == nil && !(b is String))

	if aIsNull, bIsNull { return true }
	if aIsNull != bIsNull { return false }

	return (a as? String) == (b as? String)
}

func getTokenizerTestsDirectory() -> URL? {
	let fileManager = FileManager.default
	let cwd = fileManager.currentDirectoryPath
	let cwdUrl = URL(fileURLWithPath: cwd)

	let possiblePaths = [
		cwdUrl.appendingPathComponent("html5lib-tests/tokenizer"),
		cwdUrl.appendingPathComponent("../html5lib-tests/tokenizer"),
	]

	for path in possiblePaths {
		if fileManager.fileExists(atPath: path.path) {
			return path
		}
	}
	return nil
}

/// Unescape unicode sequences like \u0000
private func unescapeUnicode(_ text: String) -> String {
	var result = ""
	var i = text.startIndex

	while i < text.endIndex {
		if text[i] == "\\", text.index(after: i) < text.endIndex {
			let next = text.index(after: i)
			if text[next] == "u", text.distance(from: next, to: text.endIndex) >= 5 {
				let hexStart = text.index(next, offsetBy: 1)
				let hexEnd = text.index(next, offsetBy: 5)
				let hexStr = String(text[hexStart ..< hexEnd])
				if let codePoint = UInt32(hexStr, radix: 16),
				   let scalar = Unicode.Scalar(codePoint)
				{
					result.append(Character(scalar))
					i = hexEnd
					continue
				}
			}
		}
		result.append(text[i])
		i = text.index(after: i)
	}

	return result
}

/// Deep unescape unicode in JSON structure
private func deepUnescapeUnicode(_ value: Any) -> Any {
	if let str = value as? String {
		return unescapeUnicode(str)
	}
	if let arr = value as? [Any] {
		return arr.map { deepUnescapeUnicode($0) }
	}
	if let dict = value as? [String: Any] {
		var result: [String: Any] = [:]
		for (k, v) in dict {
			result[k] = deepUnescapeUnicode(v)
		}
		return result
	}
	return value
}

@Test func html5libTokenizerTests() async throws {
	guard let testsDir = getTokenizerTestsDirectory() else {
		print("Tokenizer tests directory not found")
		return
	}

	let fileManager = FileManager.default
	let testFiles = try fileManager.contentsOfDirectory(at: testsDir, includingPropertiesForKeys: nil)
		.filter { $0.pathExtension == "test" }
		.sorted { $0.lastPathComponent < $1.lastPathComponent }

	var totalPassed = 0
	var totalFailed = 0

	for fileURL in testFiles {
		let filename = fileURL.lastPathComponent

		guard let content = try? Data(contentsOf: fileURL),
		      let json = try? JSONSerialization.jsonObject(with: content) as? [String: Any]
		else {
			continue
		}

		// Check for standard tests or xmlViolationTests
		let tests: [[String: Any]]
		let isXmlCoercion: Bool
		if let standardTests = json["tests"] as? [[String: Any]] {
			tests = standardTests
			isXmlCoercion = false
		}
		else if let xmlTests = json["xmlViolationTests"] as? [[String: Any]] {
			tests = xmlTests
			isXmlCoercion = true
		}
		else {
			continue
		}

		var filePassed = 0
		var fileFailed = 0

		for (testIdx, test) in tests.enumerated() {
			guard let inputRaw = test["input"] as? String,
			      let expectedOutput = test["output"] as? [[Any]]
			else {
				fileFailed += 1
				totalFailed += 1
				let description = test["description"] as? String ?? "Test \(testIdx)"
				print("\nTOKENIZER FAIL: \(filename):\(testIdx) \(description) - could not parse test input/output")
				continue
			}

			let input = unescapeUnicode(inputRaw)
			let _ = test["description"] as? String ?? "Test \(testIdx)"

			// Get initial states if specified
			var initialStates: [Tokenizer.State] = [.data]
			if let states = test["initialStates"] as? [String] {
				initialStates = states.compactMap { stateStr -> Tokenizer.State? in
					switch stateStr {
						case "Data state": return .data

						case "RCDATA state": return .rcdata

						case "RAWTEXT state": return .rawtext

						case "Script data state": return .scriptData

						case "PLAINTEXT state": return .plaintext

						case "CDATA section state": return .cdataSection

						default: return nil
					}
				}
				if initialStates.isEmpty { initialStates = [.data] }
			}

			// Get last start tag if specified
			let lastStartTag = test["lastStartTag"] as? String

			var testPassed = false

			for initialState in initialStates {
				// Create token collector
				let collector = TokenCollector()

				// Set up tokenizer options
				var opts = TokenizerOpts(initialState: initialState)
				if let lst = lastStartTag {
					opts.initialRawtextTag = lst
				}
				opts.xmlCoercion = isXmlCoercion

				// Create and run tokenizer
				let tokenizer = Tokenizer(collector, opts: opts, collectErrors: false)
				tokenizer.run(input)

				// Convert collected tokens to test format
				let actualTokens = collector.tokens.map { tokenToTestArray($0) }

				// Deep unescape expected output for comparison
				let expectedTokens = (deepUnescapeUnicode(expectedOutput) as? [[Any]]) ?? expectedOutput

				// Compare
				if actualTokens.count == expectedTokens.count {
					var allMatch = true
					for (actual, expected) in zip(actualTokens, expectedTokens) {
						if !tokensEqual(actual, expected) {
							allMatch = false
							break
						}
					}
					if allMatch {
						testPassed = true
						break
					}
				}
			}

			if testPassed {
				filePassed += 1
				totalPassed += 1
			}
			else {
				fileFailed += 1
				totalFailed += 1
				// Print first 5 failures per file for debugging
				if fileFailed <= 5 {
					let description = test["description"] as? String ?? "Test \(testIdx)"
					let stateNames = test["initialStates"] as? [String] ?? ["Data state"]
					// Collect actual tokens for first state for debug
					let collector = TokenCollector()
					var debugOpts = TokenizerOpts(initialState: initialStates.first ?? .data)
					if let lst = lastStartTag {
						debugOpts.initialRawtextTag = lst
					}
					debugOpts.xmlCoercion = isXmlCoercion
					let tokenizer = Tokenizer(collector, opts: debugOpts, collectErrors: false)
					tokenizer.run(input)
					let actualTokens = collector.tokens.map { tokenToTestArray($0) }
					let expectedTokens = (deepUnescapeUnicode(expectedOutput) as? [[Any]]) ?? expectedOutput

					print("\nTOKENIZER FAIL: \(filename):\(testIdx) \(description)")
					print("  States: \(stateNames)")
					print("  Input: \(input.debugDescription)")
					print("  Expected: \(expectedTokens)")
					print("  Actual: \(actualTokens)")
				}
			}
		}

		print(
			"  \(filename): \(filePassed)/\(filePassed + fileFailed) passed"
		)
	}

	let passRate = Double(totalPassed) / Double(max(1, totalPassed + totalFailed)) * 100
	print(
		"\nTOKENIZER TESTS: \(totalPassed)/\(totalPassed + totalFailed) passed, \(totalFailed) failed"
	)
	print("Pass rate: \(String(format: "%.1f", passRate))%")
	#expect(totalPassed + totalFailed > 0, "No tokenizer tests were run")
	#expect(totalFailed == 0, "Expected 0 tokenizer test failures but got \(totalFailed)")
}

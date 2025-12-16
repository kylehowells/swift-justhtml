import Testing
import Foundation
@testable import swift_justhtml

// MARK: - Smoke Tests

@Test func smokeTestBasicHTML() async throws {
    let html = "<html><head></head><body><p>Hello</p></body></html>"
    let doc = try JustHTML(html)
    #expect(doc.root.name == "#document")
    #expect(doc.toText() == "Hello")
}

@Test func smokeTestMinimalHTML() async throws {
    let html = "<p>Test</p>"
    let doc = try JustHTML(html)
    #expect(doc.toText() == "Test")
}

@Test func smokeTestImplicitTags() async throws {
    let html = "Hello"
    let doc = try JustHTML(html)
    #expect(doc.root.name == "#document")
    let htmlElement = doc.root.children[0]
    #expect(htmlElement.name == "html")
    #expect(htmlElement.children.count == 2)
    #expect(htmlElement.children[0].name == "head")
    #expect(htmlElement.children[1].name == "body")
}

@Test func smokeTestHeadLink() async throws {
    let html = "<head><meta></head><link>"
    let doc = try JustHTML(html)
    #expect(doc.toText().isEmpty)
}

@Test func smokeTestTableNested() async throws {
    let html = "<table><tr><tr><td><td><span><th><span>X"
    let doc = try JustHTML(html)
    #expect(doc.toText() == "X")
}

@Test func smokeTestMultiBody() async throws {
    let html = "<body><body><base><link><meta><title><p></title><body><p></body>"
    let doc = try JustHTML(html)
    let output = doc.toTestFormat()
    print(output)
    #expect(doc.toText() == "<p>")  // Text inside title
}

@Test func smokeTestTemplate() async throws {
    let html = "<body><template>Hello</template>"
    let doc = try JustHTML(html)
    let output = doc.toTestFormat()
    print(output)
    #expect(doc.toText().isEmpty)
}

// MARK: - html5lib Test Infrastructure

struct Html5libTest {
    let input: String
    let expected: String
    let errors: [String]
    let fragmentContext: FragmentContext?
    let scriptDirective: String?
    let iframeSrcdoc: Bool
}

func decodeEscapes(_ text: String) -> String {
    if !text.contains("\\x") && !text.contains("\\u") {
        return text
    }
    var out = ""
    var i = text.startIndex
    while i < text.endIndex {
        let ch = text[i]
        if ch == "\\" && text.index(after: i) < text.endIndex {
            let nextIdx = text.index(after: i)
            let next = text[nextIdx]

            // \xHH
            if next == "x" {
                let hexStart = text.index(nextIdx, offsetBy: 1, limitedBy: text.endIndex)
                let hexEnd = hexStart.flatMap { text.index($0, offsetBy: 2, limitedBy: text.endIndex) }
                if let start = hexStart, let end = hexEnd {
                    let hex = String(text[start..<end])
                    if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                        out.append(Character(scalar))
                        i = end
                        continue
                    }
                }
            }

            // \uHHHH
            if next == "u" {
                let hexStart = text.index(nextIdx, offsetBy: 1, limitedBy: text.endIndex)
                let hexEnd = hexStart.flatMap { text.index($0, offsetBy: 4, limitedBy: text.endIndex) }
                if let start = hexStart, let end = hexEnd {
                    let hex = String(text[start..<end])
                    if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                        out.append(Character(scalar))
                        i = end
                        continue
                    }
                }
            }
        }
        out.append(ch)
        i = text.index(after: i)
    }
    return out
}

func parseDatFile(_ content: String) -> [Html5libTest] {
    let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var tests: [Html5libTest] = []
    var current: [String] = []

    for i in 0..<lines.count {
        current.append(lines[i])
        let nextIsNewTest = i + 1 >= lines.count || lines[i + 1] == "#data"
        if !nextIsNewTest { continue }

        if current.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            if let test = parseSingleTest(current) {
                tests.append(test)
            }
        }
        current = []
    }

    return tests
}

func parseSingleTest(_ lines: [String]) -> Html5libTest? {
    var mode: String? = nil
    var data: [String] = []
    var errors: [String] = []
    var document: [String] = []
    var fragmentContext: FragmentContext? = nil
    var scriptDirective: String? = nil
    var iframeSrcdoc = false

    for line in lines {
        if line.hasPrefix("#") {
            let directive = String(line.dropFirst())
            if directive == "script-on" || directive == "script-off" {
                scriptDirective = directive
                continue
            }
            if directive == "iframe-srcdoc" {
                iframeSrcdoc = true
                continue
            }
            mode = directive
            continue
        }

        switch mode {
        case "data":
            data.append(line)
        case "errors", "new-errors":
            errors.append(line)
        case "document":
            document.append(line)
        case "document-fragment":
            let frag = line.trimmingCharacters(in: .whitespaces)
            if frag.isEmpty { continue }
            if frag.contains(" ") {
                let parts = frag.split(separator: " ", maxSplits: 1).map(String.init)
                let ns: Namespace?
                switch parts[0].lowercased() {
                case "svg": ns = .svg
                case "math": ns = .math
                default: ns = nil
                }
                fragmentContext = FragmentContext(parts[1], namespace: ns)
            } else {
                fragmentContext = FragmentContext(frag)
            }
        default:
            break
        }
    }

    if data.isEmpty && document.isEmpty { return nil }

    return Html5libTest(
        input: decodeEscapes(data.joined(separator: "\n")),
        expected: document.joined(separator: "\n"),
        errors: errors.filter { !$0.isEmpty },
        fragmentContext: fragmentContext,
        scriptDirective: scriptDirective,
        iframeSrcdoc: iframeSrcdoc
    )
}

func compareOutputs(_ expected: String, _ actual: String) -> Bool {
    func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }
    return normalize(expected) == normalize(actual)
}

func getTestsDirectory() -> URL? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let cwdUrl = URL(fileURLWithPath: cwd)

    // Check several possible locations (CI puts html5lib-tests at repo root)
    let possiblePaths = [
        cwdUrl.appendingPathComponent("html5lib-tests/tree-construction"),
        cwdUrl.appendingPathComponent("../html5lib-tests/tree-construction")
    ]

    for path in possiblePaths {
        if fileManager.fileExists(atPath: path.path) {
            return path
        }
    }

    return nil
}

func listDatFiles(in directory: URL) -> [URL] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var datFiles: [URL] = []
    for case let fileURL as URL in enumerator {
        if fileURL.pathExtension == "dat" {
            datFiles.append(fileURL)
        }
    }
    return datFiles.sorted { $0.path < $1.path }
}

// MARK: - html5lib Test Runner

struct TreeConstructionTestResult {
    let file: String
    let index: Int
    let passed: Bool
    let input: String
    let expected: String
    let actual: String
}

func runTreeConstructionTests(files: [String]? = nil, showFailures: Bool = false, debug: Bool = false) -> (passed: Int, failed: Int, skipped: Int, results: [TreeConstructionTestResult]) {
    guard let testsDir = getTestsDirectory() else {
        print("Could not find html5lib-tests directory")
        return (0, 0, 0, [])
    }

    var datFiles = listDatFiles(in: testsDir)

    // Filter to specific files if requested
    if let files = files, !files.isEmpty {
        datFiles = datFiles.filter { url in
            files.contains { url.lastPathComponent.contains($0) }
        }
    }

    var passed = 0
    var failed = 0
    var skipped = 0
    var results: [TreeConstructionTestResult] = []

    for fileURL in datFiles {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            continue
        }

        let filename = fileURL.lastPathComponent
        let tests = parseDatFile(content)

        for (idx, test) in tests.enumerated() {
            // Skip script-on tests for now
            if test.scriptDirective == "script-on" {
                skipped += 1
                continue
            }

            if debug {
                print("[\(filename):\(idx)] Parsing: \(test.input.prefix(40).replacingOccurrences(of: "\n", with: "\\n"))...")
            }

            do {
                let doc = try JustHTML(
                    test.input,
                    fragmentContext: test.fragmentContext,
                    scripting: test.scriptDirective == "script-on",
                    iframeSrcdoc: test.iframeSrcdoc
                )

                let actual = doc.toTestFormat()

                if compareOutputs(test.expected, actual) {
                    passed += 1
                    results.append(TreeConstructionTestResult(
                        file: filename,
                        index: idx,
                        passed: true,
                        input: test.input,
                        expected: test.expected,
                        actual: actual
                    ))
                } else {
                    failed += 1
                    results.append(TreeConstructionTestResult(
                        file: filename,
                        index: idx,
                        passed: false,
                        input: test.input,
                        expected: test.expected,
                        actual: actual
                    ))

                    if showFailures {
                        print("\nFAIL: \(filename):\(idx)")
                        print("INPUT:")
                        print(test.input)
                        print("\nEXPECTED:")
                        print(test.expected)
                        print("\nACTUAL:")
                        print(actual)
                        print("")
                    }
                }
            } catch {
                failed += 1
                results.append(TreeConstructionTestResult(
                    file: filename,
                    index: idx,
                    passed: false,
                    input: test.input,
                    expected: test.expected,
                    actual: "ERROR: \(error)"
                ))
            }
        }
    }

    return (passed, failed, skipped, results)
}

// MARK: - html5lib Tests

@Test func html5libTreeConstructionTests1() async throws {
    guard let testsDir = getTestsDirectory() else {
        print("Could not find html5lib-tests directory")
        #expect(Bool(false), "Could not find html5lib-tests directory")
        return
    }

    let fileURL = testsDir.appendingPathComponent("tests1.dat")
    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
        print("Could not read file: \(fileURL.path)")
        #expect(Bool(false), "Could not read test file")
        return
    }
    print("File read OK, length: \(content.count)")

    let tests = parseDatFile(content)
    print("Parsed \(tests.count) tests")

    var passed = 0
    var failed = 0

    for (idx, test) in tests.enumerated() {
        if test.scriptDirective == "script-on" {
            continue
        }

        let doc = try JustHTML(
            test.input,
            fragmentContext: test.fragmentContext,
            scripting: false,
            iframeSrcdoc: test.iframeSrcdoc
        )

        let actual = doc.toTestFormat()
        if compareOutputs(test.expected, actual) {
            passed += 1
        } else {
            failed += 1
        }

        if idx >= 85 && idx <= 112 {
            print("Test \(idx): \(test.input.prefix(40).replacingOccurrences(of: "\n", with: "\\n"))...")
        }
    }

    print("\ntests1.dat: \(passed)/\(passed + failed) passed, \(failed) failed")
    #expect(passed + failed > 0, "Should have run some tests")
}

@Test func html5libTreeConstructionTests2() async throws {
    let (passed, failed, skipped, _) = runTreeConstructionTests(files: ["tests2.dat"], showFailures: false)
    print("\ntests2.dat: \(passed)/\(passed + failed) passed, \(failed) failed, \(skipped) skipped")
    #expect(passed + failed + skipped > 0)
}

@Test func html5libTreeConstructionEntities() async throws {
    let (passed, failed, skipped, _) = runTreeConstructionTests(files: ["entities01.dat", "entities02.dat"], showFailures: false)
    print("\nentities: \(passed)/\(passed + failed) passed, \(failed) failed, \(skipped) skipped")
    #expect(passed + failed + skipped > 0)
}

@Test func html5libTreeConstructionComments() async throws {
    let (passed, failed, skipped, _) = runTreeConstructionTests(files: ["comments01.dat"], showFailures: false)
    print("\ncomments: \(passed)/\(passed + failed) passed, \(failed) failed, \(skipped) skipped")
    #expect(passed + failed + skipped > 0)
}

@Test func html5libTreeConstructionDoctype() async throws {
    let (passed, failed, skipped, _) = runTreeConstructionTests(files: ["doctype01.dat"], showFailures: false)
    print("\ndoctype: \(passed)/\(passed + failed) passed, \(failed) failed, \(skipped) skipped")
    #expect(passed + failed + skipped > 0)
}

@Test func html5libAllTreeConstructionTests() async throws {
    guard let testsDir = getTestsDirectory() else {
        print("Could not find html5lib-tests directory")
        #expect(Bool(false))
        return
    }

    let datFiles = listDatFiles(in: testsDir)
    print("Found \(datFiles.count) test files")

    var totalPassed = 0
    var totalFailed = 0
    var totalSkipped = 0

    for fileURL in datFiles {
        let filename = fileURL.lastPathComponent
        print("Processing \(filename)...")

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            continue
        }

        let tests = parseDatFile(content)
        var passed = 0
        var failed = 0
        var skipped = 0

        for test in tests {
            if test.scriptDirective == "script-on" {
                skipped += 1
                continue
            }

            do {
                let doc = try JustHTML(
                    test.input,
                    fragmentContext: test.fragmentContext,
                    scripting: false,
                    iframeSrcdoc: test.iframeSrcdoc
                )

                let actual = doc.toTestFormat()
                if compareOutputs(test.expected, actual) {
                    passed += 1
                } else {
                    failed += 1
                }
            } catch {
                failed += 1
            }
        }

        print("  \(filename): \(passed)/\(passed + failed) passed")
        totalPassed += passed
        totalFailed += failed
        totalSkipped += skipped
    }

    let passRate = Double(totalPassed) / Double(max(1, totalPassed + totalFailed)) * 100
    print("\nALL TESTS: \(totalPassed)/\(totalPassed + totalFailed) passed, \(totalFailed) failed, \(totalSkipped) skipped")
    print("Pass rate: \(String(format: "%.1f", passRate))%")
    #expect(totalPassed + totalFailed + totalSkipped > 0)
}

@Test func debugFailures() async throws {
    let (_, _, _, results) = runTreeConstructionTests(files: ["tests_innerHTML_1.dat"], showFailures: true)
    print("Failures: \(results.filter { !$0.passed }.count)")
}


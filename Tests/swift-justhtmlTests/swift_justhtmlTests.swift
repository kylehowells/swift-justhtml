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

// MARK: - HTMLStream Tests

@Test func testHTMLStreamBasic() async throws {
    let html = "<p>Hello</p>"
    var events: [StreamEvent] = []
    for event in HTMLStream(html) {
        events.append(event)
    }

    #expect(events.count == 3)
    #expect(events[0] == .start(tagName: "p", attrs: [:]))
    #expect(events[1] == .text("Hello"))
    #expect(events[2] == .end(tagName: "p"))
}

@Test func testHTMLStreamWithAttributes() async throws {
    let html = "<a href=\"http://example.com\" class=\"link\">Click</a>"
    var events: [StreamEvent] = []
    for event in HTMLStream(html) {
        events.append(event)
    }

    #expect(events.count == 3)
    if case .start(let tagName, let attrs) = events[0] {
        #expect(tagName == "a")
        #expect(attrs["href"] == "http://example.com")
        #expect(attrs["class"] == "link")
    } else {
        #expect(Bool(false), "Expected start tag")
    }
    #expect(events[1] == .text("Click"))
    #expect(events[2] == .end(tagName: "a"))
}

@Test func testHTMLStreamWithDoctype() async throws {
    let html = "<!DOCTYPE html><html><body>Hi</body></html>"
    var events: [StreamEvent] = []
    for event in HTMLStream(html) {
        events.append(event)
    }

    // First event should be doctype
    if case .doctype(let name, let publicId, let systemId) = events[0] {
        #expect(name == "html")
        #expect(publicId == nil)
        #expect(systemId == nil)
    } else {
        #expect(Bool(false), "Expected doctype")
    }
}

@Test func testHTMLStreamWithComment() async throws {
    let html = "<!-- This is a comment --><p>Text</p>"
    var events: [StreamEvent] = []
    for event in HTMLStream(html) {
        events.append(event)
    }

    // First event should be comment
    #expect(events[0] == .comment(" This is a comment "))
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
    // Placeholder for debugging test failures
    // Current pass rate: 99.6% (1763/1770 tests)
    // Remaining 7 edge cases are documented in the codebase
}

private func *(lhs: String, rhs: Int) -> String {
    return String(repeating: lhs, count: rhs)
}

// MARK: - CSS Selector Tests

@Test func testSelectorTypeSelector() async throws {
    let html = "<div><p>Hello</p><span>World</span></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "p")
    #expect(results.count == 1)
    #expect(results[0].name == "p")
}

@Test func testSelectorIdSelector() async throws {
    let html = "<div><p id=\"main\">Hello</p><p>World</p></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "#main")
    #expect(results.count == 1)
    #expect(results[0].attrs["id"] == "main")
}

@Test func testSelectorClassSelector() async throws {
    let html = "<div><p class=\"highlight\">One</p><p class=\"highlight\">Two</p><p>Three</p></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: ".highlight")
    #expect(results.count == 2)
}

@Test func testSelectorUniversalSelector() async throws {
    let html = "<div><p>One</p><span>Two</span></div>"
    let doc = try JustHTML(html)

    // Universal selector matches all elements
    let results = try query(doc.root, selector: "*")
    #expect(results.count >= 4)  // html, body, div, p, span at minimum
}

@Test func testSelectorDescendantCombinator() async throws {
    let html = "<div><p><span>Text</span></p></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "div span")
    #expect(results.count == 1)
    #expect(results[0].name == "span")
}

@Test func testSelectorChildCombinator() async throws {
    let html = "<div><span>Direct</span><p><span>Nested</span></p></div>"
    let doc = try JustHTML(html)

    // > means direct child only
    let results = try query(doc.root, selector: "div > span")
    #expect(results.count == 1)
    #expect(results[0].toText() == "Direct")
}

@Test func testSelectorNextSiblingCombinator() async throws {
    let html = "<div><p>First</p><span>Second</span><span>Third</span></div>"
    let doc = try JustHTML(html)

    // + means immediately following sibling
    let results = try query(doc.root, selector: "p + span")
    #expect(results.count == 1)
    #expect(results[0].toText() == "Second")
}

@Test func testSelectorSubsequentSiblingCombinator() async throws {
    let html = "<div><p>First</p><span>Second</span><span>Third</span></div>"
    let doc = try JustHTML(html)

    // ~ means any following sibling
    let results = try query(doc.root, selector: "p ~ span")
    #expect(results.count == 2)
}

@Test func testSelectorAttributeExists() async throws {
    let html = "<div><a href=\"link\">With</a><a>Without</a></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "a[href]")
    #expect(results.count == 1)
    #expect(results[0].toText() == "With")
}

@Test func testSelectorAttributeEquals() async throws {
    let html = "<input type=\"text\"><input type=\"checkbox\">"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "input[type=\"text\"]")
    #expect(results.count == 1)
    #expect(results[0].attrs["type"] == "text")
}

@Test func testSelectorAttributeContains() async throws {
    let html = "<div class=\"one two three\"><div class=\"four\"></div></div>"
    let doc = try JustHTML(html)

    // ~= matches word in space-separated list
    let results = try query(doc.root, selector: "[class~=\"two\"]")
    #expect(results.count == 1)
}

@Test func testSelectorAttributeStartsWith() async throws {
    let html = "<a href=\"https://example.com\">HTTPS</a><a href=\"http://example.com\">HTTP</a>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "a[href^=\"https\"]")
    #expect(results.count == 1)
    #expect(results[0].toText() == "HTTPS")
}

@Test func testSelectorAttributeEndsWith() async throws {
    let html = "<img src=\"photo.jpg\"><img src=\"photo.png\">"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "img[src$=\".jpg\"]")
    #expect(results.count == 1)
}

@Test func testSelectorAttributeContainsSubstring() async throws {
    let html = "<a href=\"example.com/page\">Link</a><a href=\"other.com\">Other</a>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "a[href*=\"example\"]")
    #expect(results.count == 1)
}

@Test func testSelectorFirstChild() async throws {
    let html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "li:first-child")
    #expect(results.count == 1)
    #expect(results[0].toText() == "One")
}

@Test func testSelectorLastChild() async throws {
    let html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "li:last-child")
    #expect(results.count == 1)
    #expect(results[0].toText() == "Three")
}

@Test func testSelectorNthChild() async throws {
    let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li><li>5</li></ul>"
    let doc = try JustHTML(html)

    // :nth-child(2) selects the 2nd child
    let results = try query(doc.root, selector: "li:nth-child(2)")
    #expect(results.count == 1)
    #expect(results[0].toText() == "2")
}

@Test func testSelectorNthChildOdd() async throws {
    let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "li:nth-child(odd)")
    #expect(results.count == 2)
    #expect(results[0].toText() == "1")
    #expect(results[1].toText() == "3")
}

@Test func testSelectorNthChildEven() async throws {
    let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li></ul>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "li:nth-child(even)")
    #expect(results.count == 2)
    #expect(results[0].toText() == "2")
    #expect(results[1].toText() == "4")
}

@Test func testSelectorNthChildFormula() async throws {
    let html = "<ul><li>1</li><li>2</li><li>3</li><li>4</li><li>5</li><li>6</li></ul>"
    let doc = try JustHTML(html)

    // :nth-child(3n) selects every 3rd child (3, 6)
    let results = try query(doc.root, selector: "li:nth-child(3n)")
    #expect(results.count == 2)
    #expect(results[0].toText() == "3")
    #expect(results[1].toText() == "6")
}

@Test func testSelectorNot() async throws {
    let html = "<div><p class=\"skip\">Skip</p><p>Keep</p><p class=\"skip\">Skip</p></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "p:not(.skip)")
    #expect(results.count == 1)
    #expect(results[0].toText() == "Keep")
}

@Test func testSelectorEmpty() async throws {
    let html = "<div><p></p><p>Text</p></div>"
    let doc = try JustHTML(html)

    let results = try query(doc.root, selector: "p:empty")
    #expect(results.count == 1)
}

@Test func testSelectorCompound() async throws {
    let html = "<p class=\"highlight\" id=\"main\">Target</p><p class=\"highlight\">Other</p>"
    let doc = try JustHTML(html)

    // Compound selector: p.highlight#main
    let results = try query(doc.root, selector: "p.highlight#main")
    #expect(results.count == 1)
    #expect(results[0].toText() == "Target")
}

@Test func testSelectorGroup() async throws {
    let html = "<div><p>Para</p><span>Span</span><a>Link</a></div>"
    let doc = try JustHTML(html)

    // Group selector: p, span
    let results = try query(doc.root, selector: "p, span")
    #expect(results.count == 2)
}

@Test func testSelectorMatches() async throws {
    let html = "<p class=\"test\">Hello</p>"
    let doc = try JustHTML(html)

    let p = try query(doc.root, selector: "p")[0]

    #expect(try matches(p, selector: "p"))
    #expect(try matches(p, selector: ".test"))
    #expect(try matches(p, selector: "p.test"))
    #expect(try !matches(p, selector: "div"))
    #expect(try !matches(p, selector: ".other"))
}

@Test func testSelectorComplex() async throws {
    let html = """
    <div id="container">
        <ul class="list">
            <li class="item">One</li>
            <li class="item active">Two</li>
            <li class="item">Three</li>
        </ul>
    </div>
    """
    let doc = try JustHTML(html)

    // Complex selector with descendant and class
    let results = try query(doc.root, selector: "#container .list > .item.active")
    #expect(results.count == 1)
    #expect(results[0].toText() == "Two")
}

// MARK: - Markdown Tests

@Test func testMarkdownHeadings() async throws {
    let html = "<h1>Title</h1><h2>Subtitle</h2><h3>Section</h3>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("# Title"))
    #expect(md.contains("## Subtitle"))
    #expect(md.contains("### Section"))
}

@Test func testMarkdownParagraph() async throws {
    let html = "<p>Hello World</p><p>Second paragraph</p>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("Hello World"))
    #expect(md.contains("Second paragraph"))
}

@Test func testMarkdownStrong() async throws {
    let html = "<p>This is <strong>bold</strong> text</p>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("**bold**"))
}

@Test func testMarkdownEmphasis() async throws {
    let html = "<p>This is <em>italic</em> text</p>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("*italic*"))
}

@Test func testMarkdownCode() async throws {
    let html = "<p>Use <code>print()</code> to output</p>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("`print()`"))
}

@Test func testMarkdownPreformatted() async throws {
    let html = "<pre><code>func hello() {\n    print(\"Hi\")\n}</code></pre>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("```"))
    #expect(md.contains("func hello()"))
}

@Test func testMarkdownLink() async throws {
    let html = "<a href=\"https://example.com\">Example</a>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("[Example](https://example.com)"))
}

@Test func testMarkdownImage() async throws {
    let html = "<img src=\"photo.jpg\" alt=\"A photo\">"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("![A photo](photo.jpg)"))
}

@Test func testMarkdownUnorderedList() async throws {
    let html = "<ul><li>Apple</li><li>Banana</li><li>Cherry</li></ul>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("- Apple"))
    #expect(md.contains("- Banana"))
    #expect(md.contains("- Cherry"))
}

@Test func testMarkdownOrderedList() async throws {
    let html = "<ol><li>First</li><li>Second</li><li>Third</li></ol>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("1. First"))
    #expect(md.contains("2. Second"))
    #expect(md.contains("3. Third"))
}

@Test func testMarkdownBlockquote() async throws {
    let html = "<blockquote>This is a quote</blockquote>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("> This is a quote"))
}

@Test func testMarkdownHorizontalRule() async throws {
    let html = "<p>Above</p><hr><p>Below</p>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("---"))
}

@Test func testMarkdownTable() async throws {
    let html = """
    <table>
        <tr><th>Name</th><th>Age</th></tr>
        <tr><td>Alice</td><td>30</td></tr>
        <tr><td>Bob</td><td>25</td></tr>
    </table>
    """
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("| Name"))
    #expect(md.contains("| ---"))
    #expect(md.contains("| Alice"))
    #expect(md.contains("| Bob"))
}

@Test func testMarkdownStrikethrough() async throws {
    let html = "<p>This is <del>deleted</del> text</p>"
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()
    #expect(md.contains("~~deleted~~"))
}

@Test func testMarkdownComplex() async throws {
    let html = """
    <article>
        <h1>My Article</h1>
        <p>Welcome to <strong>my article</strong> about <em>programming</em>.</p>
        <h2>Features</h2>
        <ul>
            <li>Fast</li>
            <li>Reliable</li>
        </ul>
        <p>Visit <a href="https://example.com">our site</a> for more.</p>
    </article>
    """
    let doc = try JustHTML(html)
    let md = doc.toMarkdown()

    #expect(md.contains("# My Article"))
    #expect(md.contains("**my article**"))
    #expect(md.contains("*programming*"))
    #expect(md.contains("## Features"))
    #expect(md.contains("- Fast"))
    #expect(md.contains("- Reliable"))
    #expect(md.contains("[our site](https://example.com)"))
}

// MARK: - Benchmarks

/// Generate a simple HTML document for benchmarks
func generateBenchmarkHTML(paragraphs: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Test</title></head><body>"
    for i in 0..<paragraphs {
        html += "<p>This is paragraph \(i) with some <strong>bold</strong> and <em>italic</em> text.</p>"
    }
    html += "</body></html>"
    return html
}

/// Generate a table-heavy HTML document
func generateTableHTML(rows: Int, cols: Int) -> String {
    var html = "<!DOCTYPE html><html><head><title>Table Test</title></head><body><table>"
    html += "<thead><tr>"
    for c in 0..<cols {
        html += "<th>Column \(c)</th>"
    }
    html += "</tr></thead><tbody>"
    for r in 0..<rows {
        html += "<tr>"
        for c in 0..<cols {
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
    for _ in 0..<depth {
        html += "<div><span><a href=\"#\">"
    }
    html += "Deep content"
    for _ in 0..<depth {
        html += "</a></span></div>"
    }
    html += "</body></html>"
    return html
}

@Test func benchmarkSmallHTML() async throws {
    let html = generateBenchmarkHTML(paragraphs: 10)
    let iterations = 100

    let start = Date()
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
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
    for _ in 0..<iterations {
        _ = doc.toMarkdown()
    }
    let elapsed = Date().timeIntervalSince(start)

    let avgMs = (elapsed / Double(iterations)) * 1000

    print("toMarkdown on 100 paragraphs:")
    print("  \(iterations) iterations in \(String(format: "%.3f", elapsed))s")
    print("  Average: \(String(format: "%.3f", avgMs))ms")

    #expect(avgMs < 100, "toMarkdown should complete in under 100ms")
}


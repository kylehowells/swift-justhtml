import Foundation
import Testing
@testable import justhtml

// MARK: - HTMLStream Tests

@Test func hTMLStreamBasic() async throws {
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

@Test func hTMLStreamWithAttributes() async throws {
	let html = "<a href=\"http://example.com\" class=\"link\">Click</a>"
	var events: [StreamEvent] = []
	for event in HTMLStream(html) {
		events.append(event)
	}

	#expect(events.count == 3)
	if case let .start(tagName, attrs) = events[0] {
		#expect(tagName == "a")
		#expect(attrs["href"] == "http://example.com")
		#expect(attrs["class"] == "link")
	}
	else {
		#expect(Bool(false), "Expected start tag")
	}
	#expect(events[1] == .text("Click"))
	#expect(events[2] == .end(tagName: "a"))
}

@Test func hTMLStreamWithDoctype() async throws {
	let html = "<!DOCTYPE html><html><body>Hi</body></html>"
	var events: [StreamEvent] = []
	for event in HTMLStream(html) {
		events.append(event)
	}

	// First event should be doctype
	if case let .doctype(name, publicId, systemId) = events[0] {
		#expect(name == "html")
		#expect(publicId == nil)
		#expect(systemId == nil)
	}
	else {
		#expect(Bool(false), "Expected doctype")
	}
}

@Test func hTMLStreamWithComment() async throws {
	let html = "<!-- This is a comment --><p>Text</p>"
	var events: [StreamEvent] = []
	for event in HTMLStream(html) {
		events.append(event)
	}

	// First event should be comment
	#expect(events[0] == .comment(" This is a comment "))
}

// HTMLStream.swift - Event-based HTML parsing interface

import Foundation

// MARK: - StreamEvent

/// Events emitted during HTML parsing
public enum StreamEvent: Equatable {
	case start(tagName: String, attrs: [String: String])
	case end(tagName: String)
	case text(String)
	case comment(String)
	case doctype(name: String?, publicId: String?, systemId: String?)
}

// MARK: - HTMLStream

/// A sequence that yields HTML parsing events without building a DOM tree.
///
/// This provides a simple event-based interface for processing HTML. Iteration
/// advances the tokenizer incrementally and does not build a DOM or store the
/// complete token stream. The input string is still held in memory; this is not
/// a chunked network/file streaming parser.
public struct HTMLStream: Sequence {
	private let html: String

	/// Initialize with an HTML string
	public init(_ html: String) {
		self.html = html
	}

	/// Initialize with raw bytes (auto-detects encoding)
	public init(data: Data, encoding: String? = nil) {
		let (decoded, _) = decodeHTML(data, transportEncoding: encoding)
		self.html = decoded
	}

	public func makeIterator() -> HTMLStreamIterator {
		return HTMLStreamIterator(html: self.html)
	}
}

// MARK: - HTMLStreamIterator

/// Iterator that yields StreamEvent values
public struct HTMLStreamIterator: IteratorProtocol {
	private let sink: StreamEventSink
	private let tokenizer: Tokenizer
	private var finished: Bool = false

	init(html: String) {
		let sink = StreamEventSink()
		let tokenizer = Tokenizer(sink, opts: TokenizerOpts(), collectErrors: false)
		tokenizer.startIncrementalRun(html)
		self.sink = sink
		self.tokenizer = tokenizer
	}

	public mutating func next() -> StreamEvent? {
		while true {
			if let event = self.sink.popEvent() {
				return event
			}

			if self.finished {
				return nil
			}

			if !self.tokenizer.pumpIncrementalRun() {
				self.finished = true
			}
		}
	}
}

// MARK: - StreamEventSink

/// Converts tokenizer tokens into stream events without storing the full token stream.
private final class StreamEventSink: TokenSink {
	private var firstEvent: StreamEvent?
	private var secondEvent: StreamEvent?
	private var overflowEvents: [StreamEvent] = []
	private var overflowHead: Int = 0
	private var textBuffer: String = ""

	func processToken(_ token: Token) {
		switch token {
			case let .startTag(name, attrs, _):
				self.flushText()
				self.enqueue(.start(tagName: name, attrs: attrs))

			case let .endTag(name):
				self.flushText()
				self.enqueue(.end(tagName: name))

			case let .character(text):
				self.textBuffer.append(text)

			case let .comment(data):
				self.flushText()
				self.enqueue(.comment(data))

			case let .doctype(doctype):
				self.flushText()
				self.enqueue(.doctype(name: doctype.name, publicId: doctype.publicId, systemId: doctype.systemId))

			case .eof:
				self.flushText()
		}
	}

	var currentNamespace: Namespace? {
		return nil
	}

	func popEvent() -> StreamEvent? {
		guard let event = self.firstEvent else {
			return nil
		}

		self.firstEvent = self.secondEvent
		self.secondEvent = self.popOverflowEvent()
		return event
	}

	private func enqueue(_ event: StreamEvent) {
		if self.firstEvent == nil {
			self.firstEvent = event
			return
		}
		if self.secondEvent == nil {
			self.secondEvent = event
			return
		}

		self.overflowEvents.append(event)
	}

	private func popOverflowEvent() -> StreamEvent? {
		guard self.overflowHead < self.overflowEvents.count else {
			if self.overflowHead > 0 {
				self.overflowEvents.removeAll(keepingCapacity: true)
				self.overflowHead = 0
			}
			return nil
		}

		let event = self.overflowEvents[self.overflowHead]
		self.overflowHead += 1
		if self.overflowHead == self.overflowEvents.count {
			self.overflowEvents.removeAll(keepingCapacity: true)
			self.overflowHead = 0
		}
		return event
	}

	private func flushText() {
		guard !self.textBuffer.isEmpty else { return }

		self.enqueue(.text(self.textBuffer))
		self.textBuffer = ""
	}
}

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
/// This provides a simple event-based interface for processing HTML. Note that
/// the HTML is fully tokenized on initialization; this class provides an iterator
/// interface over the tokens but does not implement true incremental streaming.
/// For large documents, memory usage will be proportional to document size.
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
  private var tokenQueue: [Token]
  private var index: Int = 0
  private var textBuffer: String = ""

  init(html: String) {
    // Create a token collector and run tokenizer
    let collector = TokenCollector()
    let tokenizer = Tokenizer(collector, opts: TokenizerOpts(), collectErrors: false)
    tokenizer.run(html)
    self.tokenQueue = collector.tokens
  }

  public mutating func next() -> StreamEvent? {
    while self.index < self.tokenQueue.count {
      let token = self.tokenQueue[self.index]
      self.index += 1

      switch token {
      case .startTag(let name, let attrs, _):
        // Flush text buffer before tag
        if !self.textBuffer.isEmpty {
          let text = self.textBuffer
          self.textBuffer = ""
          // Back up to reprocess this token
          self.index -= 1
          return .text(text)
        }
        return .start(tagName: name, attrs: attrs)

      case .endTag(let name):
        // Flush text buffer before tag
        if !self.textBuffer.isEmpty {
          let text = self.textBuffer
          self.textBuffer = ""
          self.index -= 1
          return .text(text)
        }
        return .end(tagName: name)

      case .character(let ch):
        self.textBuffer.append(ch)

      case .comment(let data):
        // Flush text buffer before comment
        if !self.textBuffer.isEmpty {
          let text = self.textBuffer
          self.textBuffer = ""
          self.index -= 1
          return .text(text)
        }
        return .comment(data)

      case .doctype(let doctype):
        // Flush text buffer before doctype
        if !self.textBuffer.isEmpty {
          let text = self.textBuffer
          self.textBuffer = ""
          self.index -= 1
          return .text(text)
        }
        return .doctype(name: doctype.name, publicId: doctype.publicId, systemId: doctype.systemId)

      case .eof:
        // Flush any remaining text
        if !self.textBuffer.isEmpty {
          let text = self.textBuffer
          self.textBuffer = ""
          return .text(text)
        }
        return nil
      }
    }

    // End of tokens - flush any remaining text
    if !self.textBuffer.isEmpty {
      let text = self.textBuffer
      self.textBuffer = ""
      return .text(text)
    }
    return nil
  }
}

// MARK: - TokenCollector

/// A token collector that stores tokens for streaming
private class TokenCollector: TokenSink {
  var tokens: [Token] = []

  func processToken(_ token: Token) {
    self.tokens.append(token)
  }

  var currentNamespace: Namespace? {
    return nil
  }
}

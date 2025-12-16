// swift-justhtml - A dependency-free HTML5 parser for Swift
//
// This module provides a standards-compliant HTML5 parser that passes
// the html5lib-tests test suite.
//
// Usage:
//     import swift_justhtml
//
//     let doc = try JustHTML("<p>Hello, World!</p>")
//     print(doc.toText())  // "Hello, World!"

// Re-export all public types for convenience
@_exported import Foundation

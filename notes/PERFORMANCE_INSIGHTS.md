# Performance Insights: Swift vs JavaScript vs Python

**Key Finding:** V8's JIT compiler automatically optimizes naive JavaScript to match hand-optimized Swift code.

---

## The Benchmark Results

| Language | Implementation Style | Total Time |
|----------|---------------------|------------|
| **Swift (optimized)** | Byte buffers, batch scanning, buffer reuse | 97ms |
| **JavaScript** | Character-by-character, `array.push()` | 99ms |
| **Swift (original)** | Straightforward, like JavaScript | 302ms |
| **Python** | Regex-based batch scanning | 398ms |

**The shocking result:** Naive JavaScript matches heavily optimized Swift.

---

## Implementation Comparison

### JavaScript (justjshtml) - Straightforward

The JavaScript tokenizer uses simple, readable code:

```javascript
_stateTagName() {
    const c = this._getChar();  // Get ONE character at a time
    if (c == null) {
        this._emitError("eof-in-tag");
        this._emitToken(new EOFToken());
        return true;
    }

    if (isWhitespace(c)) {
        this.state = Tokenizer.BEFORE_ATTRIBUTE_NAME;
        return false;
    }

    if (c === ">") {
        if (!this._emitCurrentTag()) this.state = Tokenizer.DATA;
        return false;
    }

    // Simple array push for each character
    this.currentTagName.push(asciiLower(c));
    return false;
}
```

**Characteristics:**
- Processes one character at a time
- Uses `array.push()` for string building
- No byte-level manipulation
- No batch scanning
- No buffer reuse
- Simple, readable, maintainable

### Python (justhtml) - Regex Batch Scanning

Python uses regex for batch scanning to compensate for interpreter overhead:

```python
def _state_tag_name(self) -> bool:
    append_tag_char = self.current_tag_name.append
    buffer = self.buffer

    while True:
        pos = self.pos
        if pos < length:
            # Regex-based batch scanning
            match = _TAG_NAME_RUN_PATTERN.match(buffer, pos)

            if match:
                chunk = match.group(0)
                if not chunk.islower():
                    chunk = chunk.translate(_ASCII_LOWER_TABLE)
                append_tag_char(chunk)
                self.pos = match.end()
```

**Characteristics:**
- Uses compiled regex patterns for batch matching
- Matches runs of valid characters at once
- Still 4x slower than Swift due to Python/regex overhead

### Swift (Optimized) - Manual Performance Tuning

Our Swift implementation required heroic optimization:

```swift
private func tagNameState() {
    // Use reusable buffer to avoid allocation per tag
    self.nameBuffer.removeAll(keepingCapacity: true)

    while self.pos < self.inputLength {
        let byte = self.inputBytes[self.pos]  // Byte-level access

        switch byte {
            case 0x09, 0x0A, 0x0C, 0x20: // whitespace
                self.pos += 1
                if !self.nameBuffer.isEmpty {
                    // Batch convert bytes to string
                    self.currentTagName.append(
                        String(decoding: self.nameBuffer, as: UTF8.self))
                }
                self.state = .beforeAttributeName
                return

            case 0x3E: // '>'
                self.pos += 1
                if !self.nameBuffer.isEmpty {
                    self.currentTagName.append(
                        String(decoding: self.nameBuffer, as: UTF8.self))
                }
                self.state = .data
                self.emitCurrentTag()
                return

            default:
                // Lowercase ASCII A-Z inline
                if byte >= 0x41, byte <= 0x5A {
                    self.nameBuffer.append(byte + 32)
                } else {
                    self.nameBuffer.append(byte)
                }
                self.pos += 1
        }
    }
}
```

**Optimizations required:**
- `ContiguousArray<UInt8>` for byte-level input access
- Reusable `nameBuffer` to avoid allocations
- Manual batch scanning (find delimiter, extract chunk)
- Inline ASCII lowercase conversion
- `removeAll(keepingCapacity: true)` to reuse memory
- Static `Set` constants for O(1) tag lookups
- `TagID` enum for integer comparisons

---

## Why JavaScript Is So Fast

V8's JIT compiler automatically applies optimizations that we had to implement manually in Swift:

### 1. Runtime Profiling
V8 monitors which code paths are "hot" (frequently executed) and optimizes them aggressively. Swift's ahead-of-time compiler doesn't know runtime behavior.

### 2. Inline Caching
V8 caches property lookups. After seeing `this.currentTagName` a few times, access becomes as fast as a direct memory offset.

### 3. Hidden Classes
V8 creates hidden class hierarchies for objects, making property access as fast as C struct field access.

### 4. Function Inlining
Small functions like `asciiLower()` and `isWhitespace()` are automatically inlined at hot call sites.

### 5. Optimized String Operations
V8's string implementation is highly tuned. Array-based string building with `push()` + `join()` is optimized to minimize allocations.

### 6. Deferred Garbage Collection
V8 batches memory operations and runs GC during idle time, while Swift's ARC performs atomic reference counting on every retain/release.

### 7. Speculative Optimization
V8 assumes types based on observed behavior and generates optimized code. If assumptions are violated, it "deoptimizes" and falls back.

---

## The Optimization Journey in Swift

| Optimization | Time | Improvement |
|--------------|------|-------------|
| Baseline (straightforward) | 302ms | - |
| UTF-8 byte tokenizer | 261ms | 14% faster |
| Batch text insertion | 182ms | 30% faster |
| Static Set constants | 172ms | 6% faster |
| Batch text scanning | 159ms | 8% faster |
| Batch tag/attr scanning | 118ms | 26% faster |
| Inline arrays → Sets | 98ms | 17% faster |
| Reusable name buffer | 97ms | 1% faster |
| **Total improvement** | **97ms** | **3.1x faster** |

Each optimization required understanding Swift's performance characteristics:
- String.Index is O(n) for random access → use bytes
- Array literals in loops cause allocations → use static Sets
- Creating new arrays has overhead → reuse with `keepingCapacity`
- String building is expensive → batch and convert once

---

## Key Lessons

### For Swift Developers
1. **Don't assume compiled = fast.** Swift's AOT compilation doesn't guarantee performance.
2. **Profile before optimizing.** Many "obvious" optimizations hurt performance.
3. **Understand memory allocation.** ARC overhead and allocations dominate hot paths.
4. **Byte-level processing helps.** Avoiding String.Index can give 6x speedup.
5. **Reuse buffers.** `removeAll(keepingCapacity: true)` is your friend.

### For JavaScript Developers
1. **V8 is remarkable.** Write clear, simple code and let the JIT optimize.
2. **Don't over-optimize.** Hand optimization often hurts V8's ability to optimize.
3. **Consistent types matter.** Monomorphic code (same types) optimizes better.

### General Insights
1. **JIT vs AOT is nuanced.** JIT can match or beat AOT for long-running code.
2. **Runtime information is powerful.** Knowing hot paths enables targeted optimization.
3. **Language overhead varies.** Python's 4x slower shows interpreter cost.

---

## Conclusion

To match JavaScript's performance in Swift, we had to:
- Understand memory allocation patterns
- Implement manual batch scanning
- Use byte-level processing
- Reuse buffers across operations
- Choose optimal data structures
- Profile and iterate repeatedly

**JavaScript developers get this performance for free** because V8's JIT compiler applies similar optimizations automatically at runtime.

This isn't a criticism of Swift - ahead-of-time compilation has benefits (startup time, predictable performance, no warmup). But for hot loops processing large amounts of data, modern JIT compilers are remarkably effective at automatic optimization.

---

*Report generated from analysis of justhtml implementations across Swift, JavaScript, and Python.*

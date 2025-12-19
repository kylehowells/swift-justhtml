# html5ever Architecture

This document explains how the Rust html5ever parser works and why it's ~4x faster than typical implementations.

## Table of Contents

1. [Overview](#overview)
2. [Public API](#public-api)
3. [Parsing Pipeline](#parsing-pipeline)
4. [Performance Optimizations](#performance-optimizations)
5. [Comparison with Swift](#comparison-with-swift)

---

## Overview

html5ever is the HTML5 parser used by Mozilla's Servo browser engine. It achieves exceptional performance through:

- **Tendril**: Custom 16-byte string type with 8-byte inline storage
- **SIMD scanning**: Processes 16 bytes at a time in the tokenizer hot path
- **Zero-copy operations**: Slicing and sharing without data duplication
- **Compile-time code generation**: Macros eliminate function call overhead

### Benchmark Results

| Implementation | Total Time | Relative Speed |
|----------------|------------|----------------|
| **Rust (html5ever)** | 303 ms | 1.0x (baseline) |
| JavaScript | 1,035 ms | 3.4x slower |
| Swift | 1,313 ms | 4.3x slower |
| Python | 4,189 ms | 13.8x slower |

---

## Public API

### Entry Points

```rust
use html5ever::{parse_document, parse_fragment};
use html5ever::tendril::TendrilSink;
use markup5ever_rcdom::RcDom;

// Parse a complete document
let dom = parse_document(RcDom::default(), Default::default())
    .from_utf8()
    .read_from(&mut html_bytes)
    .unwrap();

// Parse a fragment
let dom = parse_fragment(
    RcDom::default(),
    Default::default(),
    context_name,      // QualName of context element
    context_attrs,     // Vec<Attribute>
)
.one(html_string);
```

### Key Types

```rust
// Parser options
pub struct ParseOpts {
    pub tokenizer: TokenizerOpts,
    pub tree_builder: TreeBuilderOpts,
}

// DOM node
pub struct Node {
    pub parent: Cell<Option<WeakHandle>>,
    pub children: RefCell<Vec<Handle>>,
    pub data: NodeData,
}

pub enum NodeData {
    Document,
    Doctype { name, public_id, system_id },
    Text { contents: RefCell<StrTendril> },
    Comment { contents: StrTendril },
    Element { name, attrs, template_contents, ... },
    ProcessingInstruction { target, contents },
}

pub type Handle = Rc<Node>;
```

---

## Parsing Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    Input (String or Bytes)                      │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      BufferQueue                                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  VecDeque<StrTendril> - Zero-copy input chunks          │    │
│  │  pop_except_from() - Extract blocks between specials    │    │
│  └─────────────────────────────────────────────────────────┘    │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Tokenizer                                │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  48 states, SIMD scanning in Data state                 │    │
│  │  Emits: StartTag, EndTag, Character, Comment, Doctype   │    │
│  └─────────────────────────────────────────────────────────┘    │
└───────────────────────────────┬─────────────────────────────────┘
                                │ TokenSink trait
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       TreeBuilder                               │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  19 insertion modes, HTML5 spec rules                   │    │
│  │  Maintains open elements stack                          │    │
│  └─────────────────────────────────────────────────────────┘    │
└───────────────────────────────┬─────────────────────────────────┘
                                │ TreeSink trait
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                          RcDom                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Reference-counted DOM nodes                            │    │
│  │  Text node merging optimization                         │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | File | Lines | Purpose |
|-----------|------|-------|---------|
| Driver | `driver.rs` | ~150 | Connects tokenizer to tree builder |
| Tokenizer | `tokenizer/mod.rs` | ~2,300 | State machine + SIMD |
| TreeBuilder | `tree_builder/*.rs` | ~70,000 | HTML5 spec rules |
| RcDom | `rcdom/lib.rs` | ~450 | DOM implementation |
| Tendril | `tendril/src/*.rs` | ~2,500 | Custom string type |

---

## Performance Optimizations

### 1. Tendril String Type

The most significant optimization is the custom `Tendril` string type.

**Standard String (24 bytes):**
```
┌──────────────────────────────────────────┐
│ ptr (8 bytes) │ len (8 bytes) │ cap (8)  │
└──────────────────────────────────────────┘
         ↓
┌─────────────────┐
│ heap allocation │
└─────────────────┘
```

**Tendril (16 bytes with 8-byte inline storage):**
```
Small string (≤ 8 bytes):
┌────────────────────────────────────────┐
│ tag+len (8 bytes) │ inline data (8 B)  │  ← NO HEAP ALLOCATION
└────────────────────────────────────────┘

Large string:
┌────────────────────────────────────────┐
│ ptr + tag (8 bytes) │ len + aux (8 B)  │
└────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────┐
│ shared heap buffer (refcounted)     │
└─────────────────────────────────────┘
```

**Why this matters:**
- Most HTML tokens are ≤ 8 bytes: `<div>`, `<span>`, `<a>`, `id`, `class`, `href`
- ~80% of strings require **zero heap allocation**
- Cloning creates shared reference (not copy)
- Slicing creates zero-copy view into existing buffer

### 2. SIMD Scanning

The tokenizer's hot path (Data state) uses SIMD to scan 16 bytes at once:

```rust
#[target_feature(enable = "sse2")]
unsafe fn data_state_sse2_fast_path(&self, input: &mut StrTendril) -> (usize, u64) {
    use std::arch::x86_64::*;

    const STRIDE: usize = 16;

    // Create masks for special characters
    let lt_mask = _mm_set1_epi8(b'<' as i8);    // Tag start
    let amp_mask = _mm_set1_epi8(b'&' as i8);   // Entity start
    let cr_mask = _mm_set1_epi8(b'\r' as i8);   // Carriage return
    let null_mask = _mm_set1_epi8(0);           // Null byte

    while i + STRIDE <= raw_bytes.len() {
        // Load 16 bytes
        let data = _mm_loadu_si128(ptr as *const __m128i);

        // Compare against all 4 masks simultaneously
        let test = _mm_or_si128(
            _mm_or_si128(
                _mm_cmpeq_epi8(data, lt_mask),
                _mm_cmpeq_epi8(data, amp_mask)
            ),
            _mm_or_si128(
                _mm_cmpeq_epi8(data, cr_mask),
                _mm_cmpeq_epi8(data, null_mask)
            )
        );

        // Check if any matched
        let bitmask = _mm_movemask_epi8(test);
        if bitmask != 0 {
            // Found special char at position
            let pos = bitmask.trailing_zeros();
            return (i + pos, newlines);
        }

        i += STRIDE;
    }
}
```

**Performance impact:**
- Processes 16 characters per CPU instruction
- Scans for 4 special characters simultaneously
- Can skip thousands of characters between tags in one pass
- Falls back to byte-by-byte only near special characters

**Platform support:**
- x86/x86_64: SSE2 (available on all modern CPUs)
- ARM64: NEON equivalent implementation

### 3. SmallCharSet Bitmap

Fast character classification using a 64-bit bitmap:

```rust
pub struct SmallCharSet {
    pub bits: u64  // Bitmap for ASCII chars 0-63
}

impl SmallCharSet {
    #[inline]
    fn contains(&self, c: u8) -> bool {
        c < 64 && (self.bits & (1 << c)) != 0
    }

    // Find length of prefix not containing any set members
    pub fn nonmember_prefix_len(&self, buf: &str) -> u32 {
        buf.bytes()
            .take_while(|&b| b >= 64 || !self.contains(b))
            .count() as u32
    }
}

// Created at compile time
small_char_set!(b'<' b'&' b'\r' b'\0')
```

**Why it's fast:**
- All HTML special characters are ASCII (< 64)
- Single bitwise AND + shift per character
- Used by BufferQueue to extract chunks between specials

### 4. BufferQueue Zero-Copy Chunking

```rust
pub struct BufferQueue {
    buffers: RefCell<VecDeque<StrTendril>>
}

impl BufferQueue {
    // Extract everything up to the next special character
    pub fn pop_except_from(&self, set: SmallCharSet) -> Option<SetResult> {
        let n = set.nonmember_prefix_len(buf);
        if n > 0 {
            // Zero-copy slice of existing buffer
            unsafe {
                out = buf.unsafe_subtendril(0, n);
                buf.unsafe_pop_front(n);  // Just moves pointer
            }
        }
        // ...
    }
}

pub enum SetResult {
    FromSet(char),              // Single special character
    NotFromSet(StrTendril),     // Block of normal text (zero-copy!)
}
```

**How it works:**
1. Scan to find first special character
2. Extract everything before it as a zero-copy tendril slice
3. Tokenizer processes the whole block at once
4. No per-character allocation

### 5. State Machine Macros

The tokenizer uses macros for state transitions:

```rust
// DSL for state machine actions
macro_rules! go {
    ( $me:ident : emit $c:expr ; $($rest:tt)* ) => ({
        $me.emit_char($c);
        go!($me: $($rest)*);
    });
    ( $me:ident : to $s:ident ) => ({
        $me.state.set(states::$s);
    });
    // ... more patterns
}

// Usage in tokenizer
go!(self: emit '<'; to TagOpen);
go!(self: create_tag StartTag c; to TagName);
```

**Why macros help:**
- Expands to inline code at compile time
- Zero function call overhead in hot loop
- State transitions become direct assignments
- Better instruction cache locality

### 6. Text Node Merging

RcDom coalesces adjacent text nodes:

```rust
fn append(&self, parent: &Handle, child: NodeOrText<Handle>) {
    // Try to merge with last text node
    if let NodeOrText::AppendText(text) = &child {
        if let Some(last) = parent.children.borrow().last() {
            if let NodeData::Text { contents } = &last.data {
                // Append to existing instead of creating new node
                contents.borrow_mut().push_slice(&text);
                return;
            }
        }
    }
    // Create new node only if can't merge
}
```

**Impact:**
- Reduces node count significantly
- Fewer allocations
- Faster tree traversal

### 7. Cheap Reference Counting

```rust
// Local (non-atomic) reference counting
pub type Handle = Rc<Node>;        // Single-threaded
pub type WeakHandle = Weak<Node>;  // For parent pointers

// Interior mutability without locks
pub struct Node {
    pub parent: Cell<Option<WeakHandle>>,    // Cell, not Mutex
    pub children: RefCell<Vec<Handle>>,      // RefCell, not RwLock
}
```

**Why it's fast:**
- `Cell` and `RefCell` have zero runtime overhead vs raw values
- No atomic operations (unlike Swift's ARC)
- No locking (single-threaded assumption)

---

## Comparison with Swift

| Aspect | html5ever (Rust) | swift-justhtml |
|--------|------------------|----------------|
| **String type** | Tendril (16B, 8B inline) | Swift String (24B, heap) |
| **Small strings** | Zero allocation | Always heap |
| **SIMD** | SSE2/NEON, 16 bytes/op | None |
| **Character scanning** | SmallCharSet bitmap | Set<Character> lookup |
| **State machine** | Macro-generated inline | Method calls |
| **Reference counting** | Rc (local, non-atomic) | ARC (atomic) |
| **Buffer handling** | Zero-copy tendril slices | String copies |
| **Text merging** | Yes | No |

### Why the 4x Difference?

1. **String Allocations (~2x)**
   - Tendril: 8-byte inline storage handles ~80% of tokens
   - Swift String: Every token requires heap allocation

2. **SIMD Scanning (~1.5-2x on large files)**
   - html5ever: 16 bytes per instruction in Data state
   - Swift: Character-by-character scanning

3. **Reference Counting (~1.2x)**
   - Rc: Simple increment/decrement
   - ARC: Atomic operations with memory barriers

4. **State Machine (~1.1x)**
   - Macros: Inline code, no function calls
   - Methods: Call overhead, less cache-friendly

5. **Zero-Copy Operations (~1.2x)**
   - Tendril slicing shares underlying buffer
   - Swift substring creates new allocation

### Potential Swift Optimizations

To approach html5ever's performance, Swift would need:

1. **Custom string type** with small-string optimization
2. **SIMD scanning** using Swift's SIMD types
3. **Unsafe buffer operations** for zero-copy slicing
4. **Code generation** for state machine (Swift macros are limited)
5. **Non-atomic reference counting** (not possible with ARC)

Some of these are impractical in Swift's safety model, which is why html5ever will likely always be faster.

---

## File Summary

| File | Lines | Purpose |
|------|-------|---------|
| `tendril/src/tendril.rs` | ~1,800 | Core string type |
| `tokenizer/mod.rs` | ~2,300 | Tokenizer + SIMD |
| `tree_builder/rules.rs` | ~70,000 | HTML5 spec rules |
| `tree_builder/mod.rs` | ~500 | TreeBuilder struct |
| `rcdom/lib.rs` | ~450 | DOM implementation |
| `markup5ever/util/buffer_queue.rs` | ~200 | Input buffering |
| `markup5ever/util/smallcharset.rs` | ~50 | Bitmap character set |
| `driver.rs` | ~150 | Parser entry points |

---

## References

- [html5ever GitHub](https://github.com/servo/html5ever)
- [Tendril documentation](https://docs.rs/tendril)
- [WHATWG HTML Parsing Spec](https://html.spec.whatwg.org/multipage/parsing.html)
- [Servo Browser Engine](https://servo.org/)

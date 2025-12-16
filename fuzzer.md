# Fuzzer Notes for swift-justhtml

Reference material for Milestone 10 (Fuzz Testing & Hardening).

## Source Material

The Python justhtml repository (`../justhtml`) contains:

1. **Fuzzer**: `benchmarks/fuzz.py` - comprehensive HTML5 fuzzer
2. **Regression tests**: `tests/justhtml-tests/` - tests added from fuzzing/coverage work

## Regression Tests from justhtml

These tests were added after running the fuzzer and coverage analysis. They should be ported to Swift and used as a starting point for our fuzzing efforts.

### Tree Construction Tests (.dat format)

| File | Tests | Coverage |
|------|-------|----------|
| `empty_stack_edge_cases.dat` | 3 | SVG/MathML integration points with empty stacks |
| `treebuilder_coverage.dat` | 17 | DOCTYPE, form feed in MathML, template end tags, dd/dt, caption, frameset, noscript |
| `branch_coverage.dat` | 33 | Null in MathML, hidden inputs, annotation-xml encoding, selectedcontent, SVG breakout |
| `iframe_srcdoc.dat` | 1 | `#iframe-srcdoc` parsing mode |
| `xml_coercion.dat` | 4 | `#xml-coercion` mode |

### Tokenizer Tests (.test JSON format)

| File | Tests | Coverage |
|------|-------|----------|
| `tokenizer_edge_cases.test` | 34 | BOM, CR/LF, bogus comments, null chars, EOF states, script escaping, attributes |
| `coverage_gaps.test` | 9 | Null in attribute names/values, missing values, RCDATA switching |
| `xml_coercion_coverage.test` | 2 | Form feed → space, non-characters |

## Fuzzer Strategies (~60 total)

The Python fuzzer uses weighted random selection from these strategies:

### Basic Element Fuzzing
- `fuzz_open_tag` - Malformed opening tags
- `fuzz_close_tag` - Malformed closing tags
- `fuzz_comment` - Malformed comments
- `fuzz_doctype` - Malformed doctypes
- `fuzz_text` - Text with edge cases
- `fuzz_nested_structure` - Nested (possibly invalid) structures

### Raw Text & RCDATA
- `fuzz_script` - Malformed script content
- `fuzz_style` - Malformed style content
- `fuzz_raw_text` - Raw text elements (script, style, xmp, iframe, noembed, noframes, noscript)
- `fuzz_rcdata` - RCDATA elements (title, textarea)

### Tree Builder Algorithms
- `fuzz_adoption_agency` - Classic misnested formatting triggers
- `fuzz_adoption_agency_complex` - Complex AAA scenarios (8+ iterations, table cells, links)
- `fuzz_foster_parenting` - Content in invalid table positions
- `fuzz_formatting_boundary` - Active formatting with markers (applet, object, marquee, button)

### Foreign Content (SVG/MathML)
- `fuzz_svg_math` - SVG and MathML parsing
- `fuzz_integration_points` - HTML/MathML integration points (annotation-xml, foreignObject, desc, title, mi, mtext)
- `fuzz_cdata_foreign` - CDATA in SVG/MathML
- `fuzz_math_annotation` - MathML annotation elements
- `fuzz_foreign_self_closing` - Self-closing in foreign content

### Table Parsing
- `fuzz_table_scoping` - Table element scoping rules
- `fuzz_template_in_table` - Template inside table structures
- `fuzz_colgroup_handling` - Colgroup edge cases

### Special Elements
- `fuzz_template` - Template elements
- `fuzz_template_nesting` - Deeply nested templates
- `fuzz_select_element` - Select parsing mode
- `fuzz_frameset_mode` - Frameset parsing mode
- `fuzz_noscript_handling` - Noscript (scripting-dependent)

### Implicit Tag Handling
- `fuzz_implicit_tags` - Implicit tag opening/closing
- `fuzz_li_dd_dt_nesting` - li/dd/dt implicit closing
- `fuzz_heading_nesting` - h1-h6 nesting
- `fuzz_form_nesting` - Form element nesting
- `fuzz_ruby_elements` - Ruby elements (rb, rt, rp, rtc)

### Document Structure
- `fuzz_document_structure` - Malformed document structure
- `fuzz_body_start_variations` - Body start tag variations
- `fuzz_html_start_variations` - Html start tag variations
- `fuzz_scope_terminators` - Elements that terminate scopes
- `fuzz_mode_switching` - Parser mode transitions

### Tokenizer Edge Cases
- `fuzz_entity_edge_cases` - Entity decoding edge cases
- `fuzz_attribute_states` - Attribute tokenizer states
- `fuzz_null_handling` - NULL byte handling
- `fuzz_whitespace_handling` - Whitespace in various contexts
- `fuzz_eof_handling` - EOF in various parsing states

### Script Parsing
- `fuzz_script_escaping` - Script double-escape states

### Stress Testing
- `fuzz_deeply_nested` - Very deep nesting (100-500 levels)
- `fuzz_many_attributes` - Many/large attributes (100-500)
- `fuzz_unclosed_formatting` - Many unclosed formatting elements

### Deprecated/Legacy Elements
- `fuzz_isindex_handling` - isindex element
- `fuzz_image_element` - image → img conversion
- `fuzz_menuitem_handling` - menuitem element
- `fuzz_object_embed` - object and embed elements
- `fuzz_plaintext_mode` - plaintext element
- `fuzz_xmp_listing_pre` - xmp, listing, pre elements
- `fuzz_empty_elements` - Void elements in wrong contexts

### DOCTYPE & Quirks
- `fuzz_doctype_variations` - Quirks-triggering doctypes
- `fuzz_quirks_doctype` - Specific quirks mode triggers
- `fuzz_after_after_modes` - After body/frameset modes

### Encoding
- `fuzz_encoding_edge_cases` - BOM, null bytes, high bytes, line endings
- `fuzz_processing_instruction` - XML processing instructions

## Key Edge Cases to Test

Based on the fuzzer and regression tests, these are critical areas:

### Null Character Handling
- Null in tag names → replacement character
- Null in attribute names → replacement character
- Null in attribute values → replacement character
- Null in text → depends on context (data state emits error, some contexts replace)
- Null in comments → replacement character
- Null in script/style → replacement character
- Null in RCDATA → replacement character

### CR/LF Normalization
- CR → LF
- CR LF → LF
- CR in attributes, comments, text content

### Integration Points (Foreign Content)
- `annotation-xml` with `encoding="text/html"` or `encoding="application/xhtml+xml"` IS an integration point
- `annotation-xml` without encoding or with other values is NOT
- SVG `foreignObject`, `desc`, `title` are always integration points
- MathML `mi`, `mo`, `mn`, `ms`, `mtext` are text integration points

### Adoption Agency Algorithm
- Limit of 8 iterations
- Formatting across block elements
- Multiple nested formatting tags
- Formatting across table cells

### Foster Parenting
- Text directly in table
- Elements in wrong table positions
- Nested tables with foster parenting

### Template Element
- Template content is in a separate document fragment
- Template in table has special handling
- Template mode stack

## Running the Python Fuzzer

```bash
cd ../justhtml
python benchmarks/fuzz.py --parser justhtml --num-tests 10000 --verbose
```

Options:
- `--parser`: justhtml, html5lib, lxml, bs4
- `--num-tests`: Number of test cases (default 1000)
- `--seed`: Random seed for reproducibility
- `--verbose`: Show progress
- `--save-failures`: Save failures to file
- `--sample N`: Print N sample fuzzed documents without parsing

## Swift Fuzzer Implementation Plan

1. Port the fuzzing strategies from Python to Swift
2. Create a `Benchmarks/` directory with the fuzzer
3. Use Swift's random number generation with seedable RNG
4. Output failures in a format that can be added as regression tests
5. Target: Pass 3+ million generated documents without crashes

## References

- Original author's experience: "I asked the agent to write a html5 fuzzer that tried really hard to generate HTML that broke the parser. It did break the parser, and for each breaking case I asked it to fix it, and write a new test for the test suite. Passed 3 million generated webpages without any crashes, and hardened the codebase again."
- Python fuzzer: `../justhtml/benchmarks/fuzz.py`
- Regression tests: `../justhtml/tests/justhtml-tests/`

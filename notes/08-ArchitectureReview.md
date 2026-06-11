# Architecture Review Notes

Date: 2026-06-10

## 2026-06-10 cleanup pass

Implemented after this review:

- Fixed public tokenizer EOF behavior so a tokenizer run emits exactly one EOF token.
- Added a focused EOF regression test across data, RCDATA, RAWTEXT, script data, plaintext, and malformed EOF cases.
- Reworked tokenizer fixed-keyword matching to iterate UTF-8 views directly instead of allocating an expected-byte array per match.
- Reworked `HTMLStream` so iteration advances the tokenizer incrementally instead of pre-tokenizing the whole input into a token array.
- Updated stream docs to clarify that `HTMLStream` avoids a DOM and full token list, while still holding the input string in memory.
- Added selectedcontent regression coverage and skipped selectedcontent post-processing unless both `select` and `selectedcontent` elements were seen during parsing.
- Introduced internal cached start/end tag wrappers for `TreeBuilder` dispatch so hot parser paths reuse `TagID` instead of repeatedly mapping names.
- Converted `TreeBuilder` `inBody` start and end tag dispatch from string/predicate ladders to cached `TagID` switches with narrow fallbacks for unmapped legacy names.
- Converted select and table-family start/end tag dispatch (`inSelect`, `inSelectInTable`, `inTable`, `inTableBody`, `inRow`, `inCell`, `inColumnGroup`, and `inCaption`) to cached `TagID` switches.
- Converted template insertion-mode start/end tag dispatch to cached `TagID` switches and reused cached start tags when replacing template insertion mode.
- Converted head-family start/end tag dispatch (`inHead`, `inHeadNoscript`, `afterHead`, `beforeHtml`, and `beforeHead`) to cached `TagID` switches.
- Reworked table/select reprocess helpers to carry cached start/end tag wrappers through implied `colgroup`/`tbody`/`tr`, table-row/body/caption, column-group, cell, and foster-parenting recovery paths.
- Removed obsolete single-use table/select/in-body tag-classification helpers made dead by the cached dispatch switches.
- Removed obsolete single-use head tag-classification helpers made dead by the cached head dispatch switches.
- Converted reset-insertion-mode decisions and table-context stack clearing from name switches to cached `TagID` switches while preserving the existing namespace exceptions.
- Converted foster-parenting target classification and select fallback classification to cached `TagID` predicates.
- Threaded cached end-tag wrappers through in-body scoped close helpers so known block, definition-list, heading, and formatting-scope end tags avoid remapping names.
- Reused cached `TagID` for known formatting-tag adoption-agency lookups and scope checks while keeping the name fallback for legacy/direct paths.
- Removed obsolete dead string helpers left behind by the cached dispatch cleanup.
- Removed stale token-wrapper migration helpers after direct cached-token call sites replaced them.
- Excluded example README files from executable targets to remove SwiftPM unhandled-file warnings.
- Made clean-checkout `swift test` deterministic when external `html5lib-tests` fixtures are absent by skipping only the external-only shards instead of reporting false parser failures.
- Removed stale absolute local paths from encoding/profiling tests and made sample-file discovery repository-relative.
- Made benchmark fixture preparation explicit with `Benchmarks/compare.py --prepare-only`, plus `--skip-synthetic` for checking sample downloads without generating synthetic input.
- Added benchmark run metadata capture for command, Python version, Swift version, platform, machine, and fixture file hashes.
- Protected the canonical benchmark report from incomplete or mismatched comparison runs; those now write `.incomplete` outputs unless explicitly overridden.
- Removed wall-clock assertions from profiling diagnostics so downloaded benchmark samples do not make normal `swift test` dependent on machine/load-specific timing.
- Corrected README and DocC performance/compliance claims to match the current checked-in benchmark report and observed compatibility counts.
- Extracted a small select-fragment helper in `TreeBuilder` to reduce duplicated context-only select handling without changing parser behavior.
- Extracted temporary insertion-mode and foster-parenting helpers in `TreeBuilder` so `inHead`, `inTable`, `inSelect`, and foster-parent delegation sites share one restoration path.
- Extracted `TreeBuilder` template insertion-mode start/end tag handling into dedicated helpers and removed stale tokenizer-state TODO comments.
- Extracted `TreeBuilder` select insertion-mode start/end tag handling into dedicated helpers, including shared option/optgroup cleanup and select-boundary end-tag popping.
- Extracted base `TreeBuilder` table insertion-mode start/end tag handling into dedicated helpers, including shared current-table close/reprocess and fostered table-token paths.
- Split the remaining table-family start/end tag modes out of the top-level dispatcher: `inTableBody`, `inRow`, `inCell`, `inColumnGroup`, and `inCaption`.
- Reused shared helpers for closing table rows, table bodies, captions, and column groups, replacing duplicated close/reprocess sequences and ad hoc caption tag arrays.
- Split head, after-body, frameset, and select-in-table start/end tag handling out of the top-level `TreeBuilder` dispatcher.
- Added shared helpers for merging attributes onto the existing `html` element and for after-body/frameset recovery paths.
- Split repeated character-token handling in `TreeBuilder` into helpers for HTML body-like text, integration points, foreign content, table text buffering, select text, after-body recovery, and frameset text.
- Split several `inBody` start-tag clusters into named helpers for html/body/frameset handling, `p` auto-closing, and list-item/definition-list-item closure.
- Split `inBody` formatting-element start-tag handling into named helpers for `button`, `a`, `nobr`, generic formatting elements, and formatting-scope marker insertion.
- Reworked `TreeBuilder` EOF processing from recursive self-calls into an explicit loop over insertion-mode transitions.
- Split additional `inBody` start-tag handling into named helpers for table entry, void/input/media elements, textarea/rawtext, select, option/optgroup, ruby, and MathML/SVG entry.
- Extracted `TreeBuilder` reset-insertion-mode decisions into named helpers for fragment context mapping, select/table ancestry, HTML namespace checks, and html/head state selection.
- Split `inBody` end-tag handling into named helpers for body/html, block/list/heading/form/p, formatting-scope, br, template, and HTML-template stack cleanup.
- Extracted adoption-agency support helpers for active-formatting-element lookup, furthest-block search, namespace-aware special-element classification, and stack popping.
- Extracted shared `inBody` scoped-end-tag closure logic for block, definition-list, and formatting-scope end tags.
- Extracted `TreeBuilder` EOF template-close handling into a named helper while preserving the existing open-stack template check.
- Consolidated open-stack template detection into one helper with explicit namespace behavior for end-tag versus EOF handling.
- Extracted shared template-close finalization for active-formatting cleanup, template insertion-mode popping, and insertion-mode reset.
- Split `TreeBuilder` reset-insertion-mode per-node decisions into a typed helper that preserves use, continue, skip, and stop outcomes.
- Split more `inBody` start-tag handling into named helpers for block, heading, pre/listing, form, and plaintext start tags, removing a stale plaintext tokenizer-state comment from the dispatcher.
- Extracted generic end-tag stack closure and adoption-agency reparent/replacement helpers, keeping the formatting-element algorithm easier to audit without changing stack/list behavior.
- Split the remaining inline `inBody` start-tag terminal paths into named helpers for select-fragment rejection, legacy `image` remapping, ignored table tags, and generic element insertion.
- Extracted shared `inBody` insert-and-disable-frameset handling for exact insert-then-clear cases.
- Collapsed duplicate text-mode end-tag handling into a named helper.
- Extracted shared table-scope end-tag guard helpers for table-family end-tag handlers.
- Extracted select-mode end-tag helpers for current `option`/`optgroup` closure and select-boundary lookup.
- Extracted shared text-node append/merge helpers used by normal and foster-parented character insertion.
- Centralized `TreeBuilder` HTML-namespace checks used by scope, reset-mode, adoption-agency, and foreign-content helpers.
- Extracted shared foster-parenting location lookup and table/template insertion helpers used by node and text insertion.
- Extracted shared open-element identity helpers used by active-formatting reconstruction and adoption-agency replacement.
- Reused shared open-element membership helpers for select-stack checks and active-formatting cleanup.
- Extracted shared open-element stack pop-through-index handling used by generic HTML, adoption-agency, and foreign-content end-tag cleanup.
- Extracted shared first-open-element removal and named template-stack helpers so form and template end-tag paths express their stack semantics directly.
- Extracted shared table-context stack clearing while keeping the row-context HTML-namespace requirement explicit.
- Extracted shared foreign-element insertion for SVG/MathML paths while keeping active-formatting reconstruction scoped to the body insertion path.
- Extracted shared table-context element insertion for caption, colgroup, and table-section start tags.
- Reused table row/body close helpers in table-family start-tag recovery paths instead of restating stack cleanup.
- Extracted shared column-group close mechanics used by start-tag, end-tag, and reprocess paths.
- Extracted shared table row/body/caption close-and-reprocess end-tag helpers.
- Extracted shared table body/row/cell/caption close-and-reprocess start-tag helpers.
- Extracted shared implied table-context insertion helpers for `colgroup`, `tbody`, and `tr` recovery paths.
- Extracted shared table row and cell element insertion helpers for table-body and row start-tag handling.
- Extracted select fallback insertion helpers for formatting, void-like, and form-like start tags.
- Extracted body-mode list-item and heading close helpers for end-tag handling.
- Extracted body-mode form close mechanics from form end-tag handling.
- Extracted body-mode HTML template close mechanics from template end-tag handling.
- Extracted shared ruby scoped start-tag handling for body-mode `rb`/`rtc` and `rt`/`rp` paths.
- Extracted shared text-mode element insertion for rawtext, RCDATA, and textarea paths.
- Reused body-mode void start-tag insertion for synthetic `br` insertion from `</br>` recovery.
- Extracted shared body-mode insert-after-closing-`p` helper for block, form, and plaintext start tags.
- Extracted shared body-mode insert-after-reconstructing-formatting helper for formatting, option, and generic start tags.
- Extracted shared body-mode insert-and-pop helper for void-like start tags.
- Reused body-mode insert-after-reconstructing-formatting helper for `select` start-tag handling.
- Extracted EOF helpers for text-mode closure, table-context recovery, and template-mode reprocessing.
- Extracted explicit any-namespace stack pop helper for select-mode fallback end-tag closure.
- Reused explicit any-namespace stack pop helper for body-mode heading end-tag closure.
- Consolidated any-namespace pop-through-target stack mechanics behind one predicate helper.
- Reused predicate stack pop mechanics for HTML table-cell closure.
- Consolidated table-context clear-stack mechanics behind one stop-before-pop predicate helper.
- Extracted shared foreign-content breakout stack-pop helpers with explicit integration-point stop rules.
- Reused shared pop-while-current stack mechanics for implied-end-tag generation.
- Consolidated backward active-formatting lookup behind one helper with explicit marker-stop policy.
- Simplified active-formatting Noah's Ark scan by removing redundant earliest-match branching.
- Replaced manual forward active-formatting identity lookup with the standard first-index helper form.
- Added a `Node` child-reparenting helper and reused it for adoption-agency child moves.
- Reworked `Node.toText` to append directly into a result string instead of collecting all text parts in an intermediate array.
- Compact consumed `HTMLStream` events during iteration to avoid retaining long consumed prefixes.
- Replaced `HTMLStream`'s general event array queue with two inline event slots plus an indexed overflow fallback to reduce steady-state memory churn.
- Removed selector word-matching array allocations for class selectors and `[attr~=value]`, and normalized type selector names once during parsing.
- Replaced selector sibling/type pseudo-class filtered arrays with direct sibling scans and added focused of-type pseudo-class regression coverage.
- Replaced repeated previous-sibling index lookups for selector sibling combinators with single-pass sibling scans.
- Removed the now-unused selector `elementChildren` array helper and made selector-only sibling/index helpers file-local.
- Reworked case-insensitive attribute selector matching to avoid allocating lowercased operand copies.
- Reworked selector keyword parsing for `odd`/`even` to avoid allocating and lowercasing the remaining selector suffix.
- Reworked selector type and attribute-name fallback matching to avoid per-node lowercase allocations.
- Reworked entity text decoding to append directly into one result string instead of collecting string fragments in an intermediate array.
- Reworked HTML serialization to append document, element, and start-tag output directly instead of collecting intermediate string arrays.
- Reworked html5lib test-format serialization to append output directly instead of collecting intermediate line arrays.
- Reworked Markdown blockquote rendering to prefix lines in one direct append pass instead of splitting, mapping, and joining.
- Reworked Markdown table rendering to avoid normalized-row and per-row map/join allocations while preserving ragged-row padding.
- Replaced short ASCII-only `TreeBuilder` lowercase comparisons with direct ASCII case-insensitive checks.
- Reused lowercase-only-when-needed normalization in `TreeBuilder` fallback and foreign-content dispatch paths.
- Reworked selectedcontent post-processing to keep the common single-target path allocation-light while preserving collect-before-clone traversal semantics.
- Reused indexed child insertion for foster-parented nodes and text so table insertion paths avoid rescanning the same parent child list.
- Extracted named last-open-element lookup/removal helpers for temporary head-element stack cleanup.
- Replaced doctype quirks lowercase allocations with ASCII case-insensitive name and prefix checks.
- Replaced fragment-context tokenizer-state lowercase allocation with direct ASCII case-insensitive checks.
- Routed the remaining open-element membership predicates through typed index helpers so stack searches share one implementation path.
- Replaced selectedcontent post-processing name checks with cached TagID comparisons during the end-of-parse traversal.
- Reworked select fallback boundary checks to answer directly in one stack pass and return early once the target is after the select boundary.
- Replaced select-mode option/optgroup current-element checks with cached TagID comparisons.
- Reused cached TagID stack popping for table/caption closure and cached TagID checks for foster-parenting table/template stack lookup.
- Reused cached TagID checks for HTML-template open-stack detection and EOF template popping while preserving explicit HTML-only versus EOF any-namespace behavior.
- Replaced remaining hot template/table-cell/select-reset stack name checks with cached TagID comparisons while preserving existing namespace requirements.
- Routed string table-scope checks for known table-context names through the cached TagID stack scan while keeping the string fallback for unknown names.
- Reused the cached `select` TagID when scanning select fallback boundaries while keeping arbitrary target end-tag matching name-based.
- Replaced repeated `FORMATTING_ELEMENTS` set membership checks in `TreeBuilder` dispatch with a local switch predicate that preserves the legacy formatting-element list.
- Replaced implied-end-tag set membership in the hot stack-pop loop with a cached TagID switch predicate while keeping the exception comparison name-based.
- Replaced the fixed table-scope terminator `Set<TagID>` lookup with a small cached TagID switch predicate.
- Replaced tiny tokenizer RCDATA/RAWTEXT element sets with switch predicates used by start-tag state dispatch.
- Removed parser constants that became dead after the switch-predicate and TagID dispatch cleanups.
- Replaced encoding-sniffer ASCII whitespace byte set membership with a switch predicate.
- Reused cached TagID for serializer void-element detection while keeping the legacy name-set fallback for unmapped nodes.
- Replaced general/list/button scope-boundary set membership with a shared switch predicate and removed the now-dead scope constants.
- Introduced an internal start-tag wrapper with cached `TagID` and converted `inBody` start-tag dispatch from a name/predicate chain to a `TagID` switch, removing the obsolete single-use predicates.
- Extracted typed stack-search helpers for generic and foreign-content end-tag handling.
- Extracted the foreign-content breakout start-tag predicate from inline start-tag handling.
- Consolidated MathML `annotation-xml` HTML integration-point detection behind one helper.
- Extracted the hidden-input attribute predicate shared by body and table input handling.
- Reworked selectedcontent option selection to avoid allocating a full option list per select.
- Short-circuited selectedcontent option traversal once a selected option is found.
- Extracted shared missing-attribute merge handling for recovered `html` and `body` start tags.
- Centralized temporary foster-parenting delegation so table recovery paths restore the previous flag state.
- Consolidated temporary insertion-mode delegation used by table/select recovery paths.
- Routed table-text foster parenting through the shared scoped foster-parenting helper.
- Avoided rebuilding foreign-content attribute dictionaries when no SVG/MathML attribute name adjustments are needed.
- Reserved capacity when rebuilding adjusted foreign-content attribute dictionaries.
- Tracked whether pending table text is all whitespace while buffering to avoid a second flush-time scan.
- Reworked selectedcontent post-processing to collect clone targets in one pre-clone traversal instead of first allocating all `select` nodes and then scanning each select subtree again.
- Collapsed repeated table-cell, table-section, and heading scope checks into single stack scans that preserve existing namespace and fragment-context rules.
- Centralized TagID scope-boundary detection so general scope checks and heading scope checks share the same MathML/SVG integration-point rules.
- Extracted the shared in-body list-item close scan used by `li` and `dd`/`dt` start-tag recovery while preserving their distinct boundary rules.
- Centralized string-based scope-boundary detection so string and TagID scope checks no longer carry duplicate MathML/SVG boundary branches.
- Extracted shared in-body end-tag close mechanics for implied end tags, early-close diagnostics, and target popping.
- Centralized close-then-reprocess sequencing for table row, table body, caption, and cell recovery helpers.
- Reused the shared start-tag reprocess helper for implied `colgroup`, `tbody`, and `tr` recovery.
- Extracted shared select close/reset handling for select and select-in-table recovery paths.
- Extracted shared current-table close/reset handling for table end-tag and table start-tag recovery paths.
- Extracted explicit table-cell end-tag closure into a named helper while preserving synthetic cell-close behavior.
- Hoisted legacy doctype quirks public-id prefixes out of per-doctype processing to avoid rebuilding the prefix list.
- Replaced per-start-tag table-mode array membership with a switch-based helper for integration-point recovery.
- Reduced foreign-content font breakout attribute checks to one lowercase conversion per attribute.
- Short-circuited foreign-content end-tag stack matching when element names are already lowercase.
- Added an exact-key fast path for MathML `annotation-xml` encoding attribute lookup while preserving case-insensitive fallback.
- Added an exact-value fast path for MathML HTML integration-point encoding values while preserving case-insensitive fallback.
- Reused shared case-insensitive attribute lookup for hidden input detection and added an exact-value fast path for `type="hidden"`.
- Collapsed foreign-content attribute adjustment into a single pass with a lazy copy only when a rename is needed.
- Centralized HTML-namespace open-element name checks for fragment-context stack popping.
- Reused centralized open-element membership helpers for template stack detection.
- Avoided computing unused open-element indices for identity membership checks.
- Simplified in-body current-node validation after implied end-tag generation.
- Replaced identity-based open-element `removeAll` calls with first-match stack removal.
- Avoided lowercasing already-normalized select fallback start/end tag names.
- Avoided lowercasing already-normalized foreign attribute names during SVG/MathML adjustment.
- Avoided lowercasing already-normalized hidden-input `type` attribute values.
- Avoided lowercasing already-normalized MathML annotation encoding values.
- Avoided lowercasing already-normalized foreign-content `font` breakout attribute names.
- Centralized select fallback tag normalization and avoided lowercasing already-normalized unknown fallback tag names.
- Reused TagID scope checks for known in-body block-structure end tags while preserving string fallback for legacy names.
- Reused TagID stack popping for known in-body block-structure end tags while preserving string fallback for legacy names.
- Reused TagID scoped-close mechanics for known definition-list and formatting-scope end tags.
- Reused TagID stack popping for hot `p` and `li` close helpers.
- Reused TagID stack popping for list-item start-tag recovery and button start-tag recovery.
- Reused the existing TagID heading predicate for in-body heading start-tag recovery.
- Centralized special-element classification behind a TagID fast path while preserving the string fallback for unmapped legacy names.
- Reused TagID predicates for SVG/MathML integration-point checks in scope, adoption-agency, and foreign-content paths.
- Reused TagID table-scope terminator checks in the string table-scope helper while preserving name-only `td`/`th`/`tr` matching.
- Centralized table-scope terminator and table-section TagID predicates across table-scope stack scans.
- Reused TagID select-scope checks and stack popping for select-mode select closure, then removed the obsolete name-based select-scope helper.
- Replaced tiny in-body dispatch sets for input, media, option/optgroup, and ruby tags with direct checks or switch helpers.
- Replaced tiny table cell and table section dispatch sets with switch helpers shared by table start/end tag paths.
- Replaced tiny body-mode definition-list and pre/listing dispatch sets with switch helpers shared by start and end tag paths.
- Replaced tiny early-mode `head`/`noscript` and `body`/`html`/`br` dispatch sets with switch helpers.
- Replaced tiny table/template dispatch sets for row-or-cell and template table-group start tags with switch helpers.
- Replaced tiny table-family end-tag ignore sets with state-specific switch helpers.
- Replaced remaining tiny table/caption recovery dispatch sets with state-specific switch helpers.
- Replaced tiny head-mode dispatch sets with named switch helpers for metadata, rawtext, and noscript delegation.
- Replaced tiny early-end-tag and script/template dispatch sets with named switch helpers.
- Replaced the shared head-processing dispatch set with a named switch helper used by after-head, template, and body states.
- Replaced the body-mode void start-tag dispatch set with a named switch helper.
- Replaced single-use ignored table start/end tag dispatch sets with named switch helpers.
- Replaced in-body heading start/end dispatch checks with a named switch helper while retaining the stack-pop collection.
- Replaced the body-mode formatting-scope dispatch set with a named switch helper.
- Replaced the shared table-related tag predicate set with a named switch helper used by table-cell recovery and foster-parenting paths.
- Replaced select-in-table boundary and select fallback form-element dispatch sets with named switch helpers.
- Replaced body-mode block-structure start/end dispatch sets with named switch helpers.
- Replaced table-context stack-clearing sets with explicit context predicates for table, table-body, and row stack recovery.
- Replaced the remaining one-off heading and namespace integration tag sets in `TreeBuilder` with existing/named predicate helpers.

Verification from this pass:

- `swift test` passed with external `html5lib-tests` checked out.
- `swift test` also passed without external `html5lib-tests` checked out.
- `swift test` passed with benchmark samples present, after profiling tests were made diagnostic-only for wall-clock timing.
- `python3 Benchmarks/compare.py --prepare-only --skip-synthetic` successfully prepared benchmark sample fixtures.
- `python3 -m py_compile Benchmarks/compare.py Benchmarks/generate_synthetic.py Benchmarks/benchmark_python.py Benchmarks/memory_compare.py` passed.
- `node --check Benchmarks/benchmark_js.mjs` passed.
- A diagnostic `python3 Benchmarks/compare.py --skip-synthetic` run confirmed that cached `synthetic.html` is excluded from the run and that missing JavaScript/Rust sibling checkouts write `.incomplete` artifacts instead of replacing `BENCHMARK_RESULTS.md`.
- Benchmark metadata report smoke test passed: generated reports include `Run Metadata` and `Fixture Metadata` sections.
- Template-mode focused parser tests passed after extraction.
- Select-mode focused parser, selectedcontent, and regression fuzzer tests passed after extraction.
- Table-mode focused parser, template, select-fragment, SVG/table crash, and regression fuzzer tests passed after extraction.
- Full external compatibility and release fuzzer passed after the broader table-family split.
- Full external compatibility and release fuzzer passed after the head/frameset/after-body dispatcher split.
- Full external compatibility and release fuzzer passed after the character-token helper split.
- Full external compatibility and release fuzzer passed after the first `inBody` start-tag helper split.
- Full external compatibility and release fuzzer passed after the `inBody` formatting-element helper split.
- Full external compatibility and release fuzzer passed after the iterative EOF-processing refactor.
- Full external compatibility and release fuzzer passed after the second `inBody` start-tag helper split.
- Full external compatibility and release fuzzer passed after the reset-insertion-mode helper extraction.
- Full external compatibility and release fuzzer passed after the first `inBody` end-tag helper split.
- Full external compatibility and release fuzzer passed after the adoption-agency helper extraction.
- Full external compatibility and release fuzzer passed after the shared `inBody` scoped-end-tag closure extraction.
- Full external compatibility and release fuzzer passed after the EOF template-close helper extraction.
- Full external compatibility and release fuzzer passed after consolidating open-stack template detection.
- Full external compatibility and release fuzzer passed after extracting shared template-close finalization.
- Full external compatibility and release fuzzer passed after the reset-insertion-mode decision extraction.
- Full external compatibility and release fuzzer passed after the additional `inBody` start-tag helper split.
- Full external compatibility and release fuzzer passed after extracting adoption-agency and generic end-tag helper mechanics.
- Full external compatibility and release fuzzer passed after extracting the remaining `inBody` terminal start-tag paths.
- Full external compatibility and release fuzzer passed after extracting shared insert-and-disable-frameset handling.
- Full external compatibility and release fuzzer passed after collapsing duplicate text-mode end-tag handling.
- Full external compatibility and release fuzzer passed after extracting shared table-scope end-tag guard helpers.
- Full external compatibility and release fuzzer passed after extracting select-mode end-tag helpers and text-node append/merge helpers.
- Full external compatibility and release fuzzer passed after centralizing `TreeBuilder` HTML-namespace checks.
- Full external compatibility and release fuzzer passed after extracting shared foster-parenting location and insertion helpers.
- Full external compatibility and release fuzzer passed after extracting shared open-element identity helpers for active-formatting code.
- Full external compatibility and release fuzzer passed after reusing shared open-element membership helpers for select and formatting cleanup paths.
- Full external compatibility and release fuzzer passed after extracting shared open-element stack pop-through-index handling.
- Full external compatibility and release fuzzer passed after extracting first-open-element removal and named template-stack helpers.
- Full external compatibility and release fuzzer passed after extracting shared table-context stack clearing.
- Full external compatibility and release fuzzer passed after extracting shared foreign-element insertion.
- Full external compatibility and release fuzzer passed after extracting shared table-context element insertion.
- Full external compatibility and release fuzzer passed after reusing table row/body close helpers in start-tag recovery paths.
- Full external compatibility and release fuzzer passed after extracting shared column-group close mechanics.
- Full external compatibility and release fuzzer passed after extracting table row/body/caption close-and-reprocess end-tag helpers.
- Full external compatibility and release fuzzer passed after extracting table body/row/cell/caption close-and-reprocess start-tag helpers.
- Full external compatibility and release fuzzer passed after extracting implied table-context insertion helpers.
- Full external compatibility and release fuzzer passed after extracting table row/cell insertion helpers.
- Full external compatibility and release fuzzer passed after extracting select fallback insertion helpers.
- Full external compatibility and release fuzzer passed after extracting body-mode list-item and heading close helpers.
- Full external compatibility and release fuzzer passed after extracting body-mode form close mechanics.
- Full external compatibility and release fuzzer passed after extracting body-mode HTML template close mechanics.
- Full external compatibility and release fuzzer passed after extracting shared ruby scoped start-tag handling.
- Full external compatibility and release fuzzer passed after extracting shared text-mode element insertion.
- Full external compatibility and release fuzzer passed after reusing void insertion for `</br>` recovery.
- Full external compatibility and release fuzzer passed after extracting shared insert-after-closing-`p` handling.
- Full external compatibility and release fuzzer passed after extracting shared insert-after-reconstructing-formatting handling.
- Full external compatibility and release fuzzer passed after extracting shared body-mode insert-and-pop handling.
- Full external compatibility and release fuzzer passed after reusing insert-after-reconstructing-formatting for `select` start-tag handling.
- Full external compatibility and release fuzzer passed after extracting EOF helpers for text, table, and template handling.
- Full external compatibility and release fuzzer passed after extracting the any-namespace select fallback stack pop helper.
- Full external compatibility and release fuzzer passed after reusing any-namespace stack pop handling for heading end tags.
- Full external compatibility and release fuzzer passed after consolidating any-namespace pop-through-target stack mechanics.
- Full external compatibility and release fuzzer passed after reusing predicate stack pop mechanics for HTML table-cell closure.
- Full external compatibility and release fuzzer passed after consolidating table-context clear-stack mechanics.
- Full external compatibility and release fuzzer passed after extracting foreign-content breakout stack-pop helpers.
- Full external compatibility and release fuzzer passed after reusing pop-while-current mechanics for implied-end-tag generation.
- Full external compatibility and release fuzzer passed after consolidating backward active-formatting lookup.
- Full external compatibility and release fuzzer passed after simplifying the active-formatting Noah's Ark scan.
- Full external compatibility and release fuzzer passed after replacing manual forward active-formatting identity lookup.
- Full external compatibility and release fuzzer passed after adding the `Node` child-reparenting helper.
- Full external compatibility and release fuzzer passed after removing `Node.toText`'s intermediate text-part array.
- Full external compatibility and release fuzzer passed after compacting consumed `HTMLStream` events.
- Full external compatibility and release fuzzer passed after replacing `HTMLStream`'s steady-state event array queue with inline event slots.
- Full external compatibility and release fuzzer passed after removing selector word-matching array allocations.
- Full external compatibility and release fuzzer passed after replacing selector sibling/type pseudo-class filtered arrays with direct scans.
- Full external compatibility and release fuzzer passed after extracting typed end-tag stack-search helpers.
- Full external compatibility and release fuzzer passed after extracting the foreign-content breakout start-tag predicate.
- Full external compatibility and release fuzzer passed after consolidating MathML `annotation-xml` integration-point detection.
- Full external compatibility and release fuzzer passed after extracting the hidden-input attribute predicate.
- Full external compatibility and release fuzzer passed after making selectedcontent option selection allocation-free.
- Full external compatibility and release fuzzer passed after short-circuiting selectedcontent option traversal.
- Full external compatibility and release fuzzer passed after extracting shared missing-attribute merge handling.
- Full external compatibility and release fuzzer passed after centralizing temporary foster-parenting delegation.
- Full external compatibility and release fuzzer passed after consolidating temporary insertion-mode delegation.
- Full external compatibility and release fuzzer passed after routing table-text foster parenting through the shared helper.
- Full external compatibility and release fuzzer passed after making foreign-content attribute adjustment lazy.
- Full external compatibility and release fuzzer passed after reserving adjusted foreign-attribute dictionary capacity.
- Full external compatibility and release fuzzer passed after caching pending table-text whitespace state.
- Full external compatibility and release fuzzer passed after collapsing selectedcontent clone-target collection into one traversal.
- Full external compatibility and release fuzzer passed after collapsing repeated table-cell, table-section, and heading scope checks into single scans.
- Full external compatibility and release fuzzer passed after centralizing TagID scope-boundary detection.
- Full external compatibility and release fuzzer passed after extracting shared in-body list-item close mechanics.
- Full external compatibility and release fuzzer passed after centralizing string-based scope-boundary detection.
- Full external compatibility and release fuzzer passed after extracting shared in-body end-tag close mechanics.
- Full external compatibility and release fuzzer passed after centralizing close-then-reprocess sequencing.
- Full external compatibility and release fuzzer passed after routing implied table-context recovery through shared start-tag reprocessing.
- Full external compatibility and release fuzzer passed after extracting shared select close/reset handling.
- Full external compatibility and release fuzzer passed after extracting shared current-table close/reset handling.
- Full external compatibility and release fuzzer passed after extracting explicit table-cell end-tag closure.
- Full external compatibility and release fuzzer passed after hoisting legacy doctype quirks public-id prefixes.
- Full external compatibility and release fuzzer passed after replacing table-mode array membership with a switch helper.
- Full external compatibility and release fuzzer passed after reducing foreign-content font breakout attribute lowercasing.
- Full external compatibility and release fuzzer passed after short-circuiting foreign-content end-tag stack name matching.
- Full external compatibility and release fuzzer passed after adding the MathML annotation encoding attribute fast path.
- Full external compatibility and release fuzzer passed after adding the MathML annotation encoding value fast path.
- Full external compatibility and release fuzzer passed after reusing shared hidden-input attribute lookup.
- Full external compatibility and release fuzzer passed after collapsing foreign-content attribute adjustment into one lazy-copy pass.
- Full external compatibility and release fuzzer passed after centralizing fragment-context open-element HTML-name checks.
- Full external compatibility and release fuzzer passed after reusing centralized template stack membership checks.
- Full external compatibility and release fuzzer passed after avoiding unused open-element index lookup for identity membership checks.
- Full external compatibility and release fuzzer passed after simplifying in-body current-node validation after implied end-tag generation.
- Full external compatibility and release fuzzer passed after replacing identity-based open-element `removeAll` calls with first-match stack removal.
- Full external compatibility and release fuzzer passed after avoiding lowercase allocation for already-normalized select fallback start/end tag names.
- Full external compatibility and release fuzzer passed after avoiding lowercase allocation for already-normalized foreign attribute names during SVG/MathML adjustment.
- Full external compatibility and release fuzzer passed after avoiding lowercase allocation for already-normalized hidden-input `type` attribute values.
- Full external compatibility and release fuzzer passed after avoiding lowercase allocation for already-normalized MathML annotation encoding values.
- Full external compatibility and release fuzzer passed after avoiding lowercase allocation for already-normalized foreign-content `font` breakout attribute names.
- Full external compatibility and release fuzzer passed after centralizing select fallback tag normalization.
- Full external compatibility and release fuzzer passed after reusing TagID scope checks for known block-structure end tags.
- Full external compatibility and release fuzzer passed after reusing TagID stack popping for known block-structure end tags.
- Full external compatibility and release fuzzer passed after reusing TagID scoped-close mechanics for known definition-list and formatting-scope end tags.
- Full external compatibility and release fuzzer passed after reusing TagID stack popping for hot `p` and `li` close helpers.
- Full external compatibility and release fuzzer passed after reusing TagID stack popping for list-item and button start-tag recovery.
- Full external compatibility and release fuzzer passed after reusing the TagID heading predicate for heading start-tag recovery.
- Full external compatibility and release fuzzer passed after centralizing special-element classification behind a TagID fast path.
- Full external compatibility and release fuzzer passed after reusing TagID predicates for SVG/MathML integration-point checks.
- Full external compatibility and release fuzzer passed after reusing TagID table-scope terminator checks.
- Full external compatibility and release fuzzer passed after centralizing table-scope terminator and table-section predicates.
- Full external compatibility and release fuzzer passed after reusing TagID select-scope checks, select stack popping, and removing the obsolete name-based select-scope helper.
- Full external compatibility and release fuzzer passed after replacing tiny in-body dispatch sets with direct checks or switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny table cell and table section dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny body-mode definition-list and pre/listing dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny early-mode dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny table/template dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny table-family end-tag ignore sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing the remaining tiny table/caption recovery dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny head-mode dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing tiny early-end-tag and script/template dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing the shared head-processing dispatch set with a switch helper.
- Full external compatibility and release fuzzer passed after replacing the body-mode void start-tag dispatch set with a switch helper.
- Full external compatibility and release fuzzer passed after replacing single-use ignored table start/end tag dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing in-body heading start/end dispatch checks with a switch helper.
- Full external compatibility and release fuzzer passed after replacing the body-mode formatting-scope dispatch set with a switch helper.
- Full external compatibility and release fuzzer passed after replacing the shared table-related tag predicate set with a switch helper.
- Full external compatibility and release fuzzer passed after replacing select-in-table boundary and select fallback form-element dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing body-mode block-structure start/end dispatch sets with switch helpers.
- Full external compatibility and release fuzzer passed after replacing table-context stack-clearing sets with explicit context predicates.
- Full external compatibility and release fuzzer passed after replacing the remaining heading and namespace integration tag sets with predicate helpers.
- Focused selector and regression fuzzer tests passed after replacing repeated previous-sibling index lookups with single-pass sibling scans.
- Full external compatibility and release fuzzer passed after replacing repeated previous-sibling index lookups with single-pass sibling scans.
- Focused selector and regression fuzzer tests passed after removing the dead selector `elementChildren` helper and tightening selector helper visibility.
- Full external compatibility and release fuzzer passed after removing the dead selector `elementChildren` helper and tightening selector helper visibility.
- Focused selector and regression fuzzer tests passed after replacing lowercased operand copies in case-insensitive attribute selector matching.
- Full external compatibility and release fuzzer passed after replacing lowercased operand copies in case-insensitive attribute selector matching.
- Focused selector and regression fuzzer tests passed after replacing selector `odd`/`even` keyword suffix allocation with direct matching.
- Full external compatibility and release fuzzer passed after replacing selector `odd`/`even` keyword suffix allocation with direct matching.
- Focused selector and regression fuzzer tests passed after normalizing uppercase attribute selector fallback names once during parsing and avoiding type-selector match lowercasing.
- Full external compatibility and release fuzzer passed after normalizing uppercase attribute selector fallback names once during parsing and avoiding type-selector match lowercasing.
- Focused public API, tree-construction, selectedcontent, and regression fuzzer tests passed after making selectedcontent clone-target collection allocate overflow storage only for multiple targets.
- Full external compatibility and release fuzzer passed after making selectedcontent clone-target collection allocate overflow storage only for multiple targets.
- Focused smoke, tree-construction, DOM child operation, and regression fuzzer tests passed after routing foster-parented table insertions through indexed child insertion.
- Full external compatibility and release fuzzer passed after routing foster-parented table insertions through indexed child insertion.
- Focused smoke, tree-construction, and regression fuzzer tests passed after extracting named last-open-element removal for temporary head-element stack cleanup.
- Full external compatibility and release fuzzer passed after extracting named last-open-element removal for temporary head-element stack cleanup.
- Focused doctype, tokenizer, tree-construction, and regression fuzzer tests passed after replacing doctype quirks lowercase allocations with ASCII case-insensitive checks.
- Full external compatibility and release fuzzer passed after replacing doctype quirks lowercase allocations with ASCII case-insensitive checks.
- Focused fragment-context, tokenizer, tree-construction, and regression fuzzer tests passed after replacing fragment-context tokenizer-state lowercase allocation with direct ASCII case-insensitive checks.
- Full external compatibility and release fuzzer passed after replacing fragment-context tokenizer-state lowercase allocation with direct ASCII case-insensitive checks.
- Focused tree-construction, smoke, and regression fuzzer tests passed after routing open-element membership predicates through typed index helpers.
- Full external compatibility and release fuzzer passed after routing open-element membership predicates through typed index helpers.
- Focused selectedcontent, tree-construction, and regression fuzzer tests passed after replacing selectedcontent post-processing name checks with TagID comparisons.
- Full external compatibility and release fuzzer passed after replacing selectedcontent post-processing name checks with TagID comparisons.
- Focused select, tree-construction, and regression fuzzer tests passed after reworking select fallback boundary checks into a direct stack scan.
- Full external compatibility and release fuzzer passed after reworking select fallback boundary checks into a direct stack scan.
- Focused select, tree-construction, and regression fuzzer tests passed after replacing select-mode option/optgroup current-element checks with TagID comparisons.
- Full external compatibility and release fuzzer passed after replacing select-mode option/optgroup current-element checks with TagID comparisons.
- Focused table/caption/foster-parenting, tree-construction, and regression fuzzer tests passed after reusing TagID table/caption stack mechanics.
- Full external compatibility and release fuzzer passed after reusing TagID table/caption stack mechanics.
- Focused template, tree-construction, and regression fuzzer tests passed after replacing template stack name checks with TagID checks.
- Full external compatibility and release fuzzer passed after replacing template stack name checks with TagID checks.
- Focused template, table, select, tree-construction, and regression fuzzer tests passed after replacing remaining template/table-cell/select-reset stack name checks with TagID comparisons.
- Full external compatibility and release fuzzer passed after replacing remaining template/table-cell/select-reset stack name checks with TagID comparisons.
- Focused table, tree-construction, and regression fuzzer tests passed after routing known string table-scope checks through the cached TagID stack scan.
- Full external compatibility and release fuzzer passed after routing known string table-scope checks through the cached TagID stack scan.
- Focused select, table, tree-construction, and regression fuzzer tests passed after reusing cached TagID for select fallback boundary detection.
- Full external compatibility and release fuzzer passed after reusing cached TagID for select fallback boundary detection.
- Focused formatting, select, tree-construction, and regression fuzzer tests passed after replacing formatting-element set lookups with a switch predicate.
- Full external compatibility and release fuzzer passed after replacing formatting-element set lookups with a switch predicate.
- Focused tree-construction, select, formatting, and regression fuzzer tests passed after replacing implied-end-tag set membership with a cached TagID predicate.
- Full external compatibility and release fuzzer passed after replacing implied-end-tag set membership with a cached TagID predicate.
- Focused table, tree-construction, and regression fuzzer tests passed after replacing the table-scope terminator set lookup with a cached TagID predicate.
- Full external compatibility and release fuzzer passed after replacing the table-scope terminator set lookup with a cached TagID predicate.
- Focused tokenizer, tree-construction, and regression fuzzer tests passed after replacing tokenizer RCDATA/RAWTEXT set lookups with switch predicates.
- Full external compatibility and release fuzzer passed after replacing tokenizer RCDATA/RAWTEXT set lookups with switch predicates.
- Focused tokenizer, tree-construction, select/table, and regression fuzzer tests passed after removing dead parser constants.
- Full external compatibility and release fuzzer passed after removing dead parser constants.
- Focused encoding, tokenizer, tree-construction, and regression fuzzer tests passed after replacing encoding whitespace-byte set membership with a switch predicate.
- Full external compatibility and release fuzzer passed after replacing encoding whitespace-byte set membership with a switch predicate.
- Focused serializer, Markdown, public API, smoke, tree-construction, and regression fuzzer tests passed after reusing cached TagID for serializer void-element detection.
- Full external compatibility and release fuzzer passed after reusing cached TagID for serializer void-element detection.
- Focused tree-construction, scope, smoke, public API, and regression fuzzer tests passed after replacing scope-boundary set membership with a switch predicate.
- Full external compatibility and release fuzzer passed after replacing scope-boundary set membership with a switch predicate.
- Focused tree-construction, smoke, public API, and regression fuzzer tests passed after converting `inBody` start-tag dispatch to a cached TagID switch.
- Full external compatibility and release fuzzer passed after converting `inBody` start-tag dispatch to a cached TagID switch.
- Focused tree-construction, select/table, smoke, public API, and selectedcontent tests passed after converting cached end-tag and table/select start-tag dispatch.
- Full external compatibility and release fuzzer passed after converting cached end-tag and table/select start-tag dispatch: tokenizer 6810/6810, tree construction 1798/1798, serializer 230/230, encoding 82/82, in-test fuzzers without crashes, and release fuzzer 1000/1000 with zero failures/hangs.
- Focused tree-construction, template, select/table, smoke, public API, and selectedcontent tests passed after converting template insertion-mode dispatch to cached `TagID`.
- Full external compatibility and release fuzzer passed after converting template insertion-mode dispatch to cached `TagID`: tokenizer 6810/6810, tree construction 1798/1798, serializer 230/230, encoding 82/82, in-test fuzzers without crashes, and release fuzzer 1000/1000 with zero failures/hangs.
- Focused tree-construction, head/template, tokenizer, smoke, public API, and regression fuzzer tests passed after converting head-family dispatch to cached `TagID`.
- Full external compatibility and release fuzzer passed after converting head-family dispatch to cached `TagID`: tokenizer 6810/6810, tree construction 1798/1798, serializer 230/230, encoding 82/82, in-test fuzzers without crashes, and release fuzzer 1000/1000 with zero failures/hangs.
- Focused tree-construction, table/select/reset, formatting, smoke, public API, and regression fuzzer tests passed after converting reset-mode, table-context, foster-parenting, select fallback, and scoped end-tag helpers to cached `TagID`.
- Full external compatibility and release fuzzer passed after that cached `TagID` cleanup: tokenizer 6810/6810, tree construction 1798/1798, serializer 230/230, encoding 82/82, in-test fuzzers without crashes, and release fuzzer 1000/1000 with zero failures/hangs.
- Focused tree-construction, adoption/formatting, table/select/reset, smoke, public API, and regression fuzzer tests passed after reusing cached `TagID` in known adoption-agency paths and removing stale token-wrapper helpers.
- Full external compatibility and release fuzzer passed on the final cleanup state: tokenizer 6810/6810, tree construction 1798/1798 including adoption fixtures, serializer 230/230, encoding 82/82, in-test fuzzers without crashes, and release fuzzer 1000/1000 with zero failures/hangs.
- Full external compatibility and release fuzzer passed after replacing implied-end-tag set membership with a cached TagID predicate.
- Focused tokenizer, tree-construction, entity, Unicode, and regression fuzzer tests passed after removing the expected-byte array allocation from tokenizer fixed-keyword matching.
- Full external compatibility and release fuzzer passed after removing the expected-byte array allocation from tokenizer fixed-keyword matching.
- Focused entity, tokenizer, serializer, Unicode, and regression fuzzer tests passed after removing `decodeEntitiesInText`'s intermediate string-fragment array.
- Full external compatibility and release fuzzer passed after removing `decodeEntitiesInText`'s intermediate string-fragment array.
- Focused serializer, Markdown, public API, selectedcontent, and regression fuzzer tests passed after removing intermediate string arrays from HTML serialization.
- Full external compatibility and release fuzzer passed after removing intermediate string arrays from HTML serialization.
- Focused serializer, tree-construction output, Markdown, and regression fuzzer tests passed after removing intermediate line arrays from html5lib test-format serialization.
- Full external compatibility and release fuzzer passed after removing intermediate line arrays from html5lib test-format serialization.
- Focused Markdown, serializer, HTML output, and regression fuzzer tests passed after replacing blockquote split/map/join rendering with direct appending.
- Full external compatibility and release fuzzer passed after replacing blockquote split/map/join rendering with direct appending.
- Focused Markdown, serializer, tree-construction, HTML output, and regression fuzzer tests passed after removing normalized-row and map/join allocations from Markdown table rendering.
- Full external compatibility and release fuzzer passed after removing normalized-row and map/join allocations from Markdown table rendering.
- Focused tree-construction, select/SVG crash, and regression fuzzer tests passed after replacing short ASCII-only `TreeBuilder` lowercase comparisons.
- Full external compatibility and release fuzzer passed after replacing short ASCII-only `TreeBuilder` lowercase comparisons.
- Focused tree-construction, foreign-content crash, Unicode, and regression fuzzer tests passed after reusing lowercase-only-when-needed normalization in `TreeBuilder` fallback and foreign-content dispatch.
- Full external compatibility and release fuzzer passed after reusing lowercase-only-when-needed normalization in `TreeBuilder` fallback and foreign-content dispatch.
- Tokenizer compatibility: `6810/6810`.
- Tree construction compatibility: `1798/1798`.
- Serializer compatibility: `230/230`.
- Encoding compatibility: `82/82`.
- Release fuzzer command passed: `.build/release/swift-justhtml-fuzz --num-tests 1000 --seed 42 --hang-threshold 1.0`.
- Fuzzer result: `1000` successes, `0` failures, `0` diagnostic failures, `0` hangs over `1.84s`.

## Scope

This review looked at the whole `swift-justhtml` package after the parser crash and diagnostics work. The goal was to identify architecture, test, fuzzing, performance, and maintenance risks without proposing changes that would break the existing compatibility suite.

The guiding constraint for future cleanup remains: compatibility must stay at 100%, and parser crash/fuzz regressions should be checked before and after any major refactor.

## Executive summary

The project design is viable. The current parser has strong compatibility when the full external `html5lib-tests` suite is present, and the recent fuzzing pass did not find new crashes. The codebase should not be rewritten from scratch.

The main cleanup target is `TreeBuilder`. It is responsible for too many concerns in one very large class, but it also encodes a lot of spec-sensitive behavior and compatibility quirks. Any cleanup should be staged, covered by the full compatibility suite, and checked against fuzz and benchmark runs.

The biggest process issue is not CI correctness, because CI can and should run the full external `html5lib-tests` suite. The issue is local developer ergonomics: a clean checkout can produce confusing `swift test` failures unless the external fixture repository has also been checked out.

The biggest documentation issue is that the README and DocC performance claims contradict benchmark results and the current understanding that Swift is still slower than the Node.js implementation.

## Verification performed

### Local tests without external fixtures

Command:

```sh
swift test
```

Result:

- Failed when `html5lib-tests/` was not present.
- The bundled `Tests/swift-justhtmlTests/html5lib-tests` directory only contains the two local regression files.
- The sharded tree-construction tests still expect fixture files such as `tests1.dat`, `tests2.dat`, `entities*.dat`, `comments01.dat`, and doctype files.
- The all-in-one tree-construction pass only exercised the bundled regression files, not the full external suite.

Affected tests included:

- `html5libTreeConstructionTests1`
- `html5libTreeConstructionTests2`
- `html5libTreeConstructionEntities`
- `html5libTreeConstructionComments`
- `html5libTreeConstructionDoctype`

### Local tests with external fixtures

After checking out `https://github.com/html5lib/html5lib-tests.git` into `html5lib-tests/`, `swift test` passed.

Observed compatibility counts:

- Tokenizer: `6810/6810`
- Tree construction: `1798/1798`
- Serializer: `230/230`
- Encoding: `82/82`
- Overall Swift test run: `130` tests passed

Note: existing docs mention different tree-construction totals in places. The observed local run found 59 `.dat` files and `1798` non-scripted tree-construction cases.

### Fuzzer

Command:

```sh
.build/release/swift-justhtml-fuzz --num-tests 1000 --seed 42 --hang-threshold 1.0
```

Result:

- Total tests: `1000`
- Successes: `1000`
- Failures: `0`
- Diagnostic failures: `0`
- Hangs over `1.00s`: `0`
- Throughput: about `497` tests/sec

No new parser crashes were found in that run.

## Findings

### P2: Clean local test runs are confusing without external fixtures

Status: fixed in the 2026-06-10 cleanup pass. Clean local `swift test` now passes without external fixtures; external-only shards skip when their files are absent while bundled regression fixtures still run.

`Package.swift` copies the bundled `html5lib-tests` folder into the test bundle, but that folder only contains two local regression files. Some tests skip when external data is missing, while the sharded tree-construction tests fail because they expect fixture files that are not bundled.

This is not a release-blocking correctness issue if CI remains the authoritative compatibility gate and always checks out the full external suite. It is still worth fixing because a new contributor, a future local refactor, or an automated local preflight can see failures that look like parser regressions when the real problem is missing test data.

Relevant files:

- `Package.swift`
- `Tests/swift-justhtmlTests/TreeConstructionTests.swift`
- `Tests/swift-justhtmlTests/TokenizerTests.swift`
- `Tests/swift-justhtmlTests/SerializerTests.swift`

Recommended cleanup:

- Make all html5lib-dependent tests behave consistently when fixtures are missing.
- Prefer an explicit setup script or documented command for fetching `html5lib-tests`.
- Consider a clear precondition failure message that says exactly which fixture directory or file is missing.
- Keep CI running the full external fixture suite.

### P1: Public tokenizer likely emits duplicate EOF tokens

Status: fixed in the 2026-06-10 cleanup pass.

`Tokenizer.run(_:)` emits `.eof` after the state loop finishes, while several EOF branches inside state handlers also emit `.eof`.

This is likely tolerated by the tree builder, but it is surprising public API behavior. The tokenizer tests currently discard EOF tokens before comparing output, so this behavior is not covered.

Relevant files:

- `Sources/swift-justhtml/Tokenizer.swift`
- `Tests/swift-justhtmlTests/TokenizerTests.swift`

Recommended cleanup:

- Add a focused public tokenizer API test that checks EOF behavior.
- Decide whether duplicate EOF is intentional compatibility behavior.
- If it is not intentional, make EOF emission single-source and rerun the full suite plus fuzzing.

### API note: Swift exposes more parser internals than Python JustHTML's intended public API

Several low-level parser implementation types are public, including tokenizer and tree-builder internals. This is not itself a code review issue that needs action. It only matters if another cleanup, such as a `TreeBuilder` redesign or a real streaming implementation, would benefit from changing or removing those public types.

Compared with Python JustHTML, this is a real difference in intended stability surface. Python still has importable implementation packages such as `justhtml.tokenizer` and `justhtml.treebuilder`, but its top-level `justhtml.__all__` does not export `Tokenizer`, `TokenizerOpts`, `TreeBuilder`, token classes, or `InsertionMode`. Its v2.0.0 changelog also explicitly removed public `tokenizer_opts` and `tree_builder` constructor hooks and says direct module-path imports are internal implementation details, not a supported compatibility surface.

Swift has a stricter public/private boundary than Python. If a symbol is declared `public` in the `justhtml` module, Swift Package Manager clients can depend on it directly. That means Swift's public `Tokenizer`, `TokenSink`, `TokenizerOpts`, `Token`, `TreeBuilder`, and `InsertionMode` are more strongly exposed than the Python library's current intended API.

This should be treated as a secondary or tertiary design constraint, not as a cleanup task by itself. There is no reason to reduce the public API unless a higher-priority parser, streaming, performance, or memory cleanup genuinely requires it.

Relevant files:

- `Sources/swift-justhtml/Tokens.swift`
- `Sources/swift-justhtml/Tokenizer.swift`
- `Sources/swift-justhtml/TreeBuilder.swift`
- `Sources/swift-justhtml/Serialize.swift`

Recommended approach:

- Do not reduce public API just for parity with Python.
- If a future `TreeBuilder`, tokenizer, or streaming redesign needs API changes, evaluate those changes explicitly.
- Prefer compatibility-preserving internal refactors first.
- If a breaking API change becomes useful, document the reason and stage it deliberately.

### P2: `TreeBuilder` is the main architectural cleanup target

`TreeBuilder` is still about 4,900 lines after the cleanup pass and combines many responsibilities:

- insertion mode dispatch
- open element stack management
- active formatting elements
- foster parenting
- foreign content handling
- template handling
- parser depth limits
- compatibility quirks
- selectedcontent post-processing

The riskiest areas are the in-body mode, active formatting reconstruction, adoption agency algorithm, scope checks, table behavior, and foreign content.

Relevant file:

- `Sources/swift-justhtml/TreeBuilder.swift`

Recommended cleanup:

- Do not rewrite it wholesale.
- First split behavior by insertion-mode families and helper responsibilities.
- Keep state ownership in one place until compatibility remains stable after the split.
- Refactor under strict gates: full html5lib suite, fuzzer, and benchmark comparison.

### P2: `HTMLStream` is not true streaming

Status: partially addressed in the 2026-06-10 cleanup pass. `HTMLStream` now advances the tokenizer incrementally, no longer stores the full token stream, and uses a small event handoff queue for tokenizer bursts. It still retains the input string, so it is not a chunked file/network streaming parser.

The current source and README docs now describe this as incremental tokenization over an in-memory string rather than true chunked streaming.

Relevant files:

- `Sources/swift-justhtml/HTMLStream.swift`
- `README.md`

Recommended cleanup:

- Either implement true incremental streaming, or soften README claims so users understand the current behavior.
- If true streaming is implemented, add memory and behavior tests for large inputs.

### P2: Performance documentation and benchmark baselines contradict each other

Status: addressed in the 2026-06-11 benchmark refresh. README, DocC, and checked-in benchmark reports now match a full benchmark run with the Python, JavaScript, html5ever, and rust-justhtml sibling repositories available.

The README and DocC performance page had drifted away from the generated benchmark reports.

The refreshed benchmark report documents the remaining `wikipedia_ww2.html` output mismatch as Python-specific. Swift matches JavaScript, and manual comparison with html5ever shows html5ever also matches Swift/JavaScript at the differing `<hr>` void-element node. Python nests the following `<link>` and `<div>` under `<hr>`, which is not the expected tree shape for a void element.

Relevant files:

- `README.md`
- `Sources/swift-justhtml/Documentation.docc/Performance.md`
- `Benchmarks/BENCHMARK_RESULTS.md`
- `notes/current_state.md`

Recommended cleanup:

- Keep `Benchmarks/BENCHMARK_RESULTS.md` and `Benchmarks/MEMORY_RESULTS.md` as the source of truth.
- Regenerate benchmark docs from current benchmark output when possible.
- Update README and DocC to match the current measured state.
- Keep historical performance notes, but label stale data clearly.

### P2: Benchmark and profiling setup is not fully reproducible

Status: addressed in the 2026-06-11 benchmark refresh. Tests no longer contain stale absolute local paths; profiling sample discovery is repository-relative; `Benchmarks/compare.py --prepare-only` can prepare benchmark fixtures before a timing run; `--skip-synthetic` excludes cached synthetic fixtures from benchmark runs; generated benchmark reports and JSON capture command, Swift/Python versions, platform, machine, fixture source, fixture size, and fixture hashes. A full benchmark regeneration was run with the Python, JavaScript, html5ever, and rust-justhtml sibling repositories available.

Benchmark sample files and generated test files are not checked in. `Benchmarks/compare.py` can download samples and generate reports, but a fresh checkout does not obviously have everything needed to reproduce numbers.

There is also a profiling test path that references an old absolute Linux path, so it skips on this machine.

Relevant files:

- `Benchmarks/`
- `Tests/swift-justhtmlTests/ProfilingTests.swift`

Recommended cleanup:

- Document one benchmark setup path that works on a clean checkout.
- Remove or parameterize absolute local paths.
- Store benchmark metadata with each result: commit, Swift version, machine, fixture source, and command.

### P3: `selectedcontent` post-processing may do avoidable end-of-parse work

Status: fixed in the 2026-06-10 cleanup pass.

`TreeBuilder.finish()` always calls selectedcontent post-processing and traverses the tree, even for documents that likely do not contain relevant elements.

Relevant file:

- `Sources/swift-justhtml/TreeBuilder.swift`

Recommended cleanup:

- Track whether relevant select/selectedcontent nodes were seen during parsing.
- Skip the post-processing traversal when it cannot affect output.
- Benchmark before and after because this sits on the parser completion path.

### P3: Example README files produce SwiftPM warnings

Status: fixed in the 2026-06-10 cleanup pass.

`swift test` and release fuzzer builds emit warnings about unhandled README files in example targets.

Relevant files:

- `Examples/htmltool/README.md`
- `Examples/html2md/README.md`
- `Examples/fetchpage/README.md`
- `Examples/extractlinks/README.md`
- `Package.swift`

Recommended cleanup:

- Exclude these README files from target resources, or declare them intentionally.
- This is low risk but reduces CI and local build noise.

## Cleanup status

Completed in the 2026-06-10 cleanup pass:

1. Add a tokenizer EOF behavior test and fix duplicate EOF.
2. Update stream docs so `HTMLStream` no longer overclaims chunked streaming.
3. Make `HTMLStream` avoid storing the full token stream.
4. Optimize selectedcontent post-processing with a parse-time fast path.
5. Clean up SwiftPM example target warnings.
6. Make benchmark fixture preparation explicit and remove machine-dependent profiling assertions from normal test gates.
7. Capture benchmark run and fixture metadata in generated benchmark reports.
8. Keep incomplete or mismatched benchmark runs from replacing the canonical benchmark report, and make `--skip-synthetic` exclude cached synthetic fixtures.
9. Extract repeated `TreeBuilder` temporary-mode and foster-parenting mechanics into helpers.
10. Split `TreeBuilder` template insertion-mode start/end tag handling out of the top-level dispatch.
11. Split `TreeBuilder` select insertion-mode start/end tag handling out of the top-level dispatch.
12. Split base `TreeBuilder` table insertion-mode start/end tag handling out of the top-level dispatch.
13. Split `TreeBuilder` table body, row, cell, column group, and caption start/end tag handling out of the top-level dispatch.
14. Split `TreeBuilder` head, after-body, frameset, and select-in-table start/end tag handling out of the top-level dispatch.
15. Split repeated `TreeBuilder` character-token handling into named helpers.
16. Split initial `TreeBuilder` `inBody` start-tag clusters into named helpers for html/body/frameset handling and list item closure.
17. Split `TreeBuilder` `inBody` formatting-element start-tag handling into named helpers.
18. Rework `TreeBuilder` EOF processing from recursive self-calls to an explicit insertion-mode loop.
19. Split additional `TreeBuilder` `inBody` start-tag clusters into named helpers for table, void/input/media, textarea/rawtext, select, option/optgroup, ruby, and MathML/SVG entry.
20. Extract `TreeBuilder` reset-insertion-mode decisions into named helpers while preserving compatibility-specific namespace behavior.
21. Split initial `TreeBuilder` `inBody` end-tag clusters into named helpers for body/html, block/list/heading/form/p, formatting-scope, br, and template cleanup.
22. Extract adoption-agency support helpers for active formatting lookup, furthest-block search, namespace-aware special-element checks, and stack popping.
23. Extract shared `inBody` scoped-end-tag closure logic for block, definition-list, and formatting-scope end tags.
24. Extract EOF template-close handling into a named helper while preserving the existing open-stack template check.
25. Consolidate open-stack template detection into one helper with explicit namespace behavior for end-tag versus EOF handling.
26. Extract shared template-close finalization for active-formatting cleanup, template insertion-mode popping, and insertion-mode reset.
27. Split `TreeBuilder` reset-insertion-mode per-node decisions into a typed helper that preserves use, continue, skip, and stop outcomes.
28. Split additional `TreeBuilder` `inBody` start-tag helpers for block, heading, pre/listing, form, plaintext, select-fragment rejection, legacy `image`, ignored table tags, and generic insertion.
29. Extract generic end-tag stack closure and adoption-agency reparent/replacement mechanics into named helpers.
30. Extract shared `inBody` insert-and-disable-frameset handling for exact insert-then-clear cases.
31. Collapse duplicate `TreeBuilder` text-mode end-tag handling into a named helper.
32. Extract shared table-scope end-tag guard helpers for table-family end-tag handlers.
33. Extract select-mode end-tag helpers for current `option`/`optgroup` closure and select-boundary lookup.
34. Extract shared text-node append/merge helpers for normal and foster-parented character insertion.
35. Centralize `TreeBuilder` HTML-namespace checks used by scope, reset-mode, adoption-agency, and foreign-content helpers.
36. Extract shared foster-parenting location lookup and table/template insertion helpers used by node and text insertion.
37. Extract shared open-element identity helpers used by active-formatting reconstruction and adoption-agency replacement.
38. Reuse shared open-element membership helpers for select-stack checks and active-formatting cleanup.
39. Extract shared open-element stack pop-through-index handling for generic HTML, adoption-agency, and foreign-content end-tag cleanup.
40. Extract shared first-open-element removal and named template-stack helpers for form and template end-tag paths.
41. Extract shared table-context stack clearing while preserving row-context HTML-namespace behavior.
42. Extract shared foreign-element insertion for SVG/MathML paths without changing active-formatting reconstruction behavior.
43. Extract shared table-context element insertion for caption, colgroup, and table-section start tags.
44. Reuse table row/body close helpers in table-family start-tag recovery paths.
45. Extract shared column-group close mechanics used by start-tag, end-tag, and reprocess paths.
46. Extract shared table row/body/caption close-and-reprocess end-tag helpers.
47. Extract shared table body/row/cell/caption close-and-reprocess start-tag helpers.
48. Extract shared implied table-context insertion helpers for `colgroup`, `tbody`, and `tr` recovery paths.
49. Extract shared table row and cell element insertion helpers for table-body and row start-tag handling.
50. Extract select fallback insertion helpers for formatting, void-like, and form-like start tags.
51. Extract body-mode list-item and heading close helpers for end-tag handling.
52. Extract body-mode form close mechanics from form end-tag handling.
53. Extract body-mode HTML template close mechanics from template end-tag handling.
54. Extract shared ruby scoped start-tag handling for body-mode `rb`/`rtc` and `rt`/`rp` paths.
55. Extract shared text-mode element insertion for rawtext, RCDATA, and textarea paths.
56. Reuse body-mode void start-tag insertion for synthetic `br` insertion from `</br>` recovery.
57. Extract shared body-mode insert-after-closing-`p` helper for block, form, and plaintext start tags.
58. Extract shared body-mode insert-after-reconstructing-formatting helper for formatting, option, and generic start tags.
59. Extract shared body-mode insert-and-pop helper for void-like start tags.
60. Reuse body-mode insert-after-reconstructing-formatting helper for `select` start-tag handling.
61. Extract EOF helpers for text-mode closure, table-context recovery, and template-mode reprocessing.
62. Extract explicit any-namespace stack pop helper for select-mode fallback end-tag closure.
63. Reuse explicit any-namespace stack pop helper for body-mode heading end-tag closure.
64. Consolidate any-namespace pop-through-target stack mechanics behind one predicate helper.
65. Reuse predicate stack pop mechanics for HTML table-cell closure.
66. Consolidate table-context clear-stack mechanics behind one stop-before-pop predicate helper.
67. Extract shared foreign-content breakout stack-pop helpers with explicit integration-point stop rules.
68. Reuse shared pop-while-current stack mechanics for implied-end-tag generation.
69. Consolidate backward active-formatting lookup behind one helper with explicit marker-stop policy.
70. Simplify active-formatting Noah's Ark scan by removing redundant earliest-match branching.
71. Replace manual forward active-formatting identity lookup with the standard first-index helper form.
72. Add a `Node` child-reparenting helper and reuse it for adoption-agency child moves.
73. Compact consumed `HTMLStream` events during iteration to avoid retaining long consumed prefixes.
74. Extract typed stack-search helpers for generic and foreign-content end-tag handling.
75. Extract the foreign-content breakout start-tag predicate from inline start-tag handling.
76. Consolidate MathML `annotation-xml` HTML integration-point detection behind one helper.
77. Extract the hidden-input attribute predicate shared by body and table input handling.
78. Rework selectedcontent option selection to avoid allocating a full option list per select.
79. Short-circuit selectedcontent option traversal once a selected option is found.
80. Extract shared missing-attribute merge handling for recovered `html` and `body` start tags.
81. Centralize temporary foster-parenting delegation so table recovery paths restore the previous flag state.
82. Consolidate temporary insertion-mode delegation used by table/select recovery paths.
83. Route table-text foster parenting through the shared scoped foster-parenting helper.
84. Avoid rebuilding foreign-content attribute dictionaries when no SVG/MathML attribute name adjustments are needed.
85. Reserve capacity when rebuilding adjusted foreign-content attribute dictionaries.
86. Track whether pending table text is all whitespace while buffering to avoid a second flush-time scan.
87. Collect selectedcontent clone targets in one pre-clone traversal to avoid allocating every `select` and rescanning select subtrees.
88. Collapse repeated table-cell, table-section, and heading scope checks into single stack scans.
89. Centralize TagID scope-boundary detection for general and heading scope checks.
90. Extract shared in-body list-item close mechanics for `li` and `dd`/`dt` recovery.
91. Centralize string-based scope-boundary detection for general scope checks.
92. Extract shared in-body end-tag close mechanics for `li`, headings, and scoped body end tags.
93. Centralize close-then-reprocess sequencing for table row, table body, caption, and cell recovery helpers.
94. Reuse shared start-tag reprocess sequencing for implied `colgroup`, `tbody`, and `tr` recovery.
95. Extract shared select close/reset handling for select and select-in-table recovery paths.
96. Extract shared current-table close/reset handling for table end-tag and table start-tag recovery paths.
97. Extract explicit table-cell end-tag closure while preserving synthetic cell-close behavior.
98. Hoist legacy doctype quirks public-id prefixes out of per-doctype processing.
99. Replace per-start-tag table-mode array membership with switch-based integration-point recovery helper.
100. Reduce foreign-content font breakout attribute checks to one lowercase conversion per attribute.
101. Short-circuit foreign-content end-tag stack matching when element names are already lowercase.
102. Add an exact-key fast path for MathML `annotation-xml` encoding attribute lookup.
103. Add an exact-value fast path for MathML `annotation-xml` HTML integration-point encoding values.
104. Reuse shared case-insensitive attribute lookup for hidden input detection.
105. Collapse foreign-content attribute adjustment into a single lazy-copy pass.
106. Centralize HTML-namespace open-element name checks for fragment-context stack popping.
107. Reuse centralized open-element membership helpers for template stack detection.
108. Avoid computing unused open-element indices for identity membership checks.
109. Simplify in-body current-node validation after implied end-tag generation.
110. Replace identity-based open-element `removeAll` calls with first-match stack removal.
111. Avoid lowercasing already-normalized select fallback start/end tag names.
112. Avoid lowercasing already-normalized foreign attribute names during SVG/MathML adjustment.
113. Avoid lowercasing already-normalized hidden-input `type` attribute values.
114. Avoid lowercasing already-normalized MathML annotation encoding values.
115. Avoid lowercasing already-normalized foreign-content `font` breakout attribute names.
116. Centralize select fallback tag normalization and avoid lowercasing already-normalized unknown fallback tag names.
117. Reuse TagID scope checks for known in-body block-structure end tags while preserving string fallback for legacy names.
118. Reuse TagID stack popping for known in-body block-structure end tags while preserving string fallback for legacy names.
119. Reuse TagID scoped-close mechanics for known definition-list and formatting-scope end tags.
120. Reuse TagID stack popping for hot `p` and `li` close helpers.
121. Reuse TagID stack popping for list-item start-tag recovery and button start-tag recovery.
122. Reuse the existing TagID heading predicate for in-body heading start-tag recovery.
123. Centralize special-element classification behind a TagID fast path while preserving the string fallback for unmapped legacy names.
124. Reuse TagID predicates for SVG/MathML integration-point checks in scope, adoption-agency, and foreign-content paths.
125. Reuse TagID table-scope terminator checks in the string table-scope helper while preserving name-only `td`/`th`/`tr` matching.
126. Centralize table-scope terminator and table-section TagID predicates across table-scope stack scans.
127. Reuse TagID select-scope checks and stack popping for select-mode select closure, then remove the obsolete name-based select-scope helper.
128. Replace tiny in-body dispatch sets for input, media, option/optgroup, and ruby tags with direct checks or switch helpers.
129. Replace tiny table cell and table section dispatch sets with switch helpers shared by table start/end tag paths.
130. Replace tiny body-mode definition-list and pre/listing dispatch sets with switch helpers shared by start and end tag paths.
131. Replace tiny early-mode `head`/`noscript` and `body`/`html`/`br` dispatch sets with switch helpers.
132. Replace tiny table/template dispatch sets for row-or-cell and template table-group start tags with switch helpers.
133. Replace tiny table-family end-tag ignore sets with state-specific switch helpers.
134. Replace remaining tiny table/caption recovery dispatch sets with state-specific switch helpers.
135. Replace tiny head-mode dispatch sets with named switch helpers for metadata, rawtext, and noscript delegation.
136. Replace tiny early-end-tag and script/template dispatch sets with named switch helpers.
137. Replace the shared head-processing dispatch set with a named switch helper used by after-head, template, and body states.
138. Replace the body-mode void start-tag dispatch set with a named switch helper.
139. Replace single-use ignored table start/end tag dispatch sets with named switch helpers.
140. Replace in-body heading start/end dispatch checks with a named switch helper while retaining the stack-pop collection.
141. Replace the body-mode formatting-scope dispatch set with a named switch helper.
142. Replace the shared table-related tag predicate set with a named switch helper used by table-cell recovery and foster-parenting paths.
143. Replace select-in-table boundary and select fallback form-element dispatch sets with named switch helpers.
144. Replace body-mode block-structure start/end dispatch sets with named switch helpers.
145. Replace table-context stack-clearing sets with explicit context predicates for table, table-body, and row stack recovery.
146. Replace the remaining one-off heading and namespace integration tag sets in `TreeBuilder` with existing/named predicate helpers.
147. Replace `HTMLStream`'s general event array queue with two inline event slots plus an indexed overflow fallback.
148. Rework `Node.toText` to append directly into a result string instead of collecting all text parts in an intermediate array.
149. Remove selector word-matching array allocations for class selectors and `[attr~=value]`, and normalize type selector names once during parsing.
150. Replace selector sibling/type pseudo-class filtered arrays with direct sibling scans and add focused of-type pseudo-class regression coverage.
151. Replace repeated previous-sibling index lookups for selector sibling combinators with single-pass sibling scans.
152. Remove the dead selector `elementChildren` array helper and make selector-only sibling/index helpers file-local.
153. Rework entity text decoding to append directly into one result string instead of collecting string fragments in an intermediate array.
154. Rework HTML serialization to append document, element, and start-tag output directly instead of collecting intermediate string arrays.
155. Rework html5lib test-format serialization to append output directly instead of collecting intermediate line arrays.
156. Rework Markdown blockquote rendering to prefix lines in one direct append pass instead of splitting, mapping, and joining.
157. Rework Markdown table rendering to avoid normalized-row and per-row map/join allocations while preserving ragged-row padding.
158. Replace short ASCII-only `TreeBuilder` lowercase comparisons with direct ASCII case-insensitive checks.
159. Reuse lowercase-only-when-needed normalization in `TreeBuilder` fallback and foreign-content dispatch paths.
160. Rework case-insensitive attribute selector matching to avoid allocating lowercased operand copies.
161. Rework tokenizer fixed-keyword matching to iterate UTF-8 views directly instead of allocating an expected-byte array per match.
162. Rework selector `odd`/`even` keyword parsing to avoid allocating and lowercasing the remaining selector suffix.
163. Normalize uppercase attribute selector fallback names once during parsing and avoid type-selector match lowercasing.
164. Rework selectedcontent clone-target collection to avoid allocating an array for the common single-target case.
165. Reuse indexed child insertion for foster-parented nodes and text to avoid duplicate parent child-list scans.
166. Extract named last-open-element lookup/removal helpers for temporary head-element stack cleanup.
167. Replace doctype quirks lowercase allocations with ASCII case-insensitive name and prefix checks.
168. Replace fragment-context tokenizer-state lowercase allocation with direct ASCII case-insensitive checks.
169. Route remaining open-element membership predicates through typed index helpers.
170. Replace selectedcontent post-processing name checks with cached TagID comparisons.
171. Rework select fallback boundary checks into a direct stack scan with early return.
172. Replace select-mode option/optgroup current-element checks with cached TagID comparisons.
173. Reuse cached TagID stack mechanics for table/caption closure and foster-parenting table/template lookup.
174. Reuse cached TagID checks for template open-stack detection and EOF template popping.
175. Replace remaining template/table-cell/select-reset stack name checks with cached TagID comparisons.
176. Route known string table-scope checks through the cached TagID stack scan.
177. Reuse cached TagID for select fallback boundary detection.
178. Replace formatting-element set membership in TreeBuilder dispatch with a switch predicate.
179. Replace implied-end-tag set membership with a cached TagID switch predicate.
180. Replace table-scope terminator set membership with a cached TagID switch predicate.
181. Replace tokenizer RCDATA/RAWTEXT set membership with switch predicates.
182. Remove parser constants made dead by earlier switch-predicate and TagID cleanup.
183. Replace encoding-sniffer ASCII whitespace byte set membership with a switch predicate.
184. Reuse cached TagID for serializer void-element detection while keeping the legacy name-set fallback.
185. Replace general/list/button scope-boundary set membership with a shared switch predicate and remove the dead scope constants.
186. Introduce an internal cached-TagID start-tag wrapper and convert `inBody` start-tag dispatch from a name/predicate chain to a TagID switch.
187. Introduce an internal cached-TagID end-tag wrapper and convert `inBody` end-tag dispatch from a name/predicate chain to a TagID switch.
188. Convert select and table-family start/end tag dispatch to cached TagID switches and carry cached token wrappers through table/select reprocess helpers.
189. Remove obsolete table/select/in-body tag-classification helpers and no-caller string reprocess wrappers made dead by the cached dispatch conversion.
190. Convert template insertion-mode start/end tag dispatch to cached TagID switches and remove the obsolete template table-group predicate.
191. Convert head-family start/end tag dispatch to cached TagID switches and remove obsolete head tag-classification predicates.
192. Convert reset-insertion-mode decisions and table-context stack clearing to cached TagID switches while preserving namespace-specific compatibility behavior.
193. Convert foster-parenting target and select fallback classification to cached TagID predicates.
194. Thread cached end-tag wrappers through in-body scoped close helpers for known block, definition-list, heading, and formatting-scope end tags.
195. Remove dead string helpers left behind by the cached dispatch and stack-scan cleanup.
196. Reuse cached TagID for known formatting-tag adoption-agency active-formatting lookup and scope checks while preserving the string fallback.
197. Remove stale token-wrapper migration helpers after cached-token call sites replaced them.

Remaining cleanup order:

1. Use benchmark runs to check whether future helper cleanup remains neutral under release timing.
2. Treat further `TreeBuilder` work as optional, evidence-driven micro-refactoring rather than an active required cleanup item. Remaining arbitrary-name stack scans are intentional fallbacks for unknown/custom tag names unless profiling or a concrete bug shows otherwise.

Public API reduction is not listed as a cleanup item. It should only be reconsidered if a higher-priority parser, streaming, performance, or memory change cannot be done cleanly while preserving the existing API.

## Refactor gates

Any non-trivial parser cleanup should pass these gates before merge:

```sh
swift test
swift build -c release --product swift-justhtml-fuzz
.build/release/swift-justhtml-fuzz --num-tests 1000 --seed 42 --hang-threshold 1.0
```

For performance-sensitive changes, also run the benchmark comparison and record the result with commit hash, Swift version, machine, and fixture setup.

## Non-goals

- Do not replace the tokenizer or tree builder wholesale.
- Do not chase style-only changes in the parser before fixture handling and performance docs are fixed.
- Do not reduce the public API just to match Python JustHTML's top-level exports.
- Do not make API-breaking changes unless they are justified by a higher-priority parser, streaming, performance, or memory improvement.
- Do not trade compatibility for a cleaner internal design unless the breakage is temporary, deliberate, and resolved before merge.
- Do not treat README performance claims as authoritative until they are regenerated from a reproducible benchmark run.

# Changelog

本文件采用简化的 Keep a Changelog 风格。重要功能完成后更新 `Unreleased`，不要记录尚未实现的功能。

## [Unreleased]

### Added

- Expanded the flat lexical-family production layer to 197 families, 2145 unique terms and 316 composition rules covering 95 semantics; retained the original family/rule layer and archived the untrusted candidate pool with normalized review decisions.
- Added family distribution, ownership/conflict and coverage gates before runtime generation, immutable initial-report protection, four-asset knowledge fingerprints and per-semantic evaluation metrics.
- Preserved family generalization v4 initial/final reports (category 59.33%/62.00%); the single limited repair removed high-confidence wrong predictions (1 → 0), with P2 safe rejection 100%. Phase 3 classification is not frozen because accuracy remains below 90%.

- Initial Flutter project.
- Initial development documentation.
- Added the Material 3 and Riverpod application shell with a responsive ledger.
- Added Drift schema version 1 for transactions, two-level categories, and accounts, including idempotent default seeds.
- Added manual expense/income creation and editing with integer minor-unit amounts and database-backed category/account selection.
- Added soft delete with Snackbar undo and unit, isolated database, repository, and widget tests.
- Added deterministic text bookkeeping for amount, relative/basic time, content, transaction type, and database-backed keyword category recognition.
- Added reviewable `RecognitionCandidate` evidence and confidence, with mandatory user confirmation through the existing transaction editor and repository.
- Added 141 default income/expense categories (23 parent and 118 child categories), each backed by a distinct compact 24×24 SVG.
- Added a lightweight monthly income, expense, balance, and unset-budget overview above the ledger.
- Added a maintained recognition algorithm working document covering the implemented pipeline, limitations, and local future directions.
- Added five lightweight database-backed SVGs for the default payment methods and automated SVG uniqueness/shape checks.
- Added the first four layers of the offline hybrid recognizer: safe normalization, personal history, a packaged Merchant Knowledge Base, and a data-driven Category Lexicon.
- Added priority-based explainable evidence fusion and stable semantic category resolution.
- Added natural Chinese time parsing for relative days, weekdays, month boundaries, dayparts, 24-hour clocks, and spoken Chinese clock expressions.
- Added reproducible knowledge generation/validation and a 10,000-parse performance benchmark.
- Added field-aware amount/status extraction, absolute transaction-time parsing, numeric-role classification, multiple-transaction detection, and refund safety blocking.
- Added exact, longest-substring and bounded fuzzy entity matching plus role-aware lexicon evidence.
- Added an independent 190-case evaluation runner and immutable archived baseline reports.
- Added a pure Dart production `LocalRecognizer`, structured field/span candidates, independent type evidence, confidence calibration, failure analysis, and a standalone benchmark shared by App and tools.
- Added reviewed knowledge roles/kinds/breadth, per-alias match policies, deterministic review samples, scene coverage gates, and runtime distribution reports.
- Added 447 reviewed mainland consumer entities, 1307 normalized aliases, 2411 real-language positive terms, 355 negative/conflict terms, 106 production-path review samples, and 50-entity/100-term audit gates.
- Added the restored 190-case regression corpus plus immutable initial and final usability reports and failure summaries.
- Added deterministic candidate-lexicon preparation/merge tooling, per-term review reports, and 5072 selectively reviewed positive terms covering all 118 candidate semantic keys.
- Added an immutable first-run and final report for the 190-case Phase 3 stress holdout, including per-group field metrics.
- Added data-driven lexical families, proximity-aware composition rules, and explainable composition evidence without rebuilding the production semantic lexicon.
- Added span conflict resolution for contained/overlapping knowledge matches, including misleading internal substrings such as rail terms inside vehicle words.
- Added immutable initial and final reports for the 200-case Phase 3 compositional holdout; final category accuracy is 98.5% with zero high-confidence wrong predictions.

### Changed

- Unified lexical-family matching, standalone priors and composition in one indexed FamilyMatcher; removed the two old matchers, unused Recognizer interface and destructive concept-only suppression. Existing 197 families/2145 terms/316 rules remain unchanged; 117 families emit bounded priors, 80 remain contextual-only.
- Reworked EvidenceFusion to select parent before ranking children, and TypeInference to reconcile semantic direction after preliminary evidence. Removed duplicated meal/source routing and merged generator validators; added prior/schema gates and synthetic mechanism tests.
- Preserved semantic-routing v5 initial/final reports: category 75.50%/75.50%, type 94.50%/96.50%, high-confidence wrong 0 and P2 safe 100%. The single generic repair restores refund type and mandatory original-transaction linkage for refund semantics. Phase 3 classification remains unfrozen; deterministic semantic routing is insufficient, so further rule growth and v5 tuning stop.
- Validated 99 tests, original category 96.32%/type 100%, v2/v3/v4 category 90.53%/97.50%/67.67% and warm benchmark p95 0.403 ms; archived corpora/provenance and recorded reproducible freeze trees plus four-asset hashes.

- Indexed normalized family terms once per recognizer; final warm benchmark p95 is 0.436 ms. Original/v2/v3 category regression is 96.32%/88.95%/97.50%; all 89 tests and static analysis pass. Final knowledgeHash is `40b6b94c`; detailed remaining failure families are recorded in `docs/RECOGNITION_ALGORITHM.md`.
- Preserved atomic concept spans inside compounds and narrowly permitted embedded context/pet/income composition; constrained single-character replacement to adjacent reviewed components. Moved three tabletop/immersive entertainment lexicon terms to the hobby taxonomy while keeping 7486 positive and 355 negative terms.

- Finalized the V0.1 transaction schema for transfers, refunds, positive minor-unit amounts, and UTC timestamp persistence with occurrence-time offsets.
- Updated Android namespace/application ID, minimum API level, and package metadata for the V0.1 project baseline.
- Completed the Phase 1 manual bookkeeping foundation.
- Documented the repository's branch, pull request, diff review, squash merge, and post-merge cleanup workflow.
- Unified manual and intelligent text bookkeeping under the single “记一笔” entry and return successful smart entries directly to the ledger.
- Replaced category dropdowns with compact parent/child icon pickers and replaced the time dialog with a 24-hour wheel picker.
- Migrated the database to schema v2 with stable category SVG asset associations and backward-compatible default-category cleanup.
- Combined smart text input and manual fields on one entry page without a mode-selection step.
- Grouped ledger rows by occurrence wall date with weekday and daily income/expense totals.
- Replaced swipe-to-delete with editor deletion and long-press multi-select soft deletion, both with undo support.
- Changed category selection to a compact vertical, collapsible hierarchy and made the 24-hour time wheels loop.
- Replaced the account dropdown with icon choices and migrated account icon associations in schema v3.
- Changed smart text entry to run only after an explicit “识别” action and added a compact result card with direct confirmation through the shared save path.
- Replanned Phase 3 as the five-layer local hybrid recognizer and moved OCR to Phase 4; local history learning is no longer a separate phase.
- Migrated the database to schema v4 with category `semanticKey` / `isSystem` fields and minimal local `recognition_rules` hit/correction history.
- Changed text classification from hard-coded category-name rules and additive scoring to packaged indexes, stable semantics, `CategoryResolver`, and conflict-aware confidence.
- Moved recognition/history/feedback orchestration from `TransactionEditorPage` into a reusable `RecognitionCoordinator` and changed Personal History to indexed per-key queries.
- Made default category semantic keys an explicit stable mapping and removed the unused `primarySemanticKey` field.
- Changed type inference to fuse expense and income evidence before deriving type when no explicit sign or strong type signal exists.
- Unified development utilities under `tools/` and changed the benchmark to warm average/p95/max reporting with a p95 < 5 ms gate.
- Replaced `TextEntryParser`, the monolithic field extractor, and the inert n-gram interface with one production recognition pipeline used by App, evaluation, benchmark, and tests.
- Archived the unused 1600-record media/game snapshot and fetch script after removing them from the active knowledge-generation pipeline; neither had entered runtime.
- Changed evaluation to report P0/P1/P2 safe rejection, per-field and complete accuracy, display-vs-span content errors, confidence buckets, high-confidence wrong predictions, and average/p50/p95/p99/max latency.
- Changed recognition confirmation into explicit `confident`, `warning`, and `blocked` levels: warning retains top-1 prefill and permits reviewed confirmation, while only dangerous transaction states or missing legal amounts block quick entry.
- Indexed entity aliases and lexicon terms by first character, preserving Personal History priority while preventing broad/platform evidence from outranking specific products, actions, or services.
- Archived superseded Phase 3 planning/evaluation artifacts and documented the selective candidate-lexicon absorption workflow.
- Expanded the runtime lexicon to 7486 positive terms while retaining 355 reviewed negative/conflict terms, zero unresolved cross-category owners, and a 281148-byte runtime asset footprint.
- Capped clock-only meal context at warning confidence and added pet-medical modifier plus oral/eye taxonomy boundary handling after unseen stress evaluation, without changing original 190-case metrics.

### Fixed

- Preserved historical transaction wall-clock time across device timezone changes by restoring it from the saved occurrence offset.
- Added minute-level manual occurrence-time editing and retained the original offset when editing existing transactions.
- Verified transaction persistence across closing and reopening a real SQLite file.
- Ensured ledger rows and expanded child-category tiles render the selected second-level category SVG rather than the parent icon.
- Replaced title-only SVG variants with genuinely distinct category geometry and added regression coverage against duplicate shapes.
- Fixed attached-amount entity matching, common entity suffixes, amount-token boundaries, modifier/action composition, OCR clock selection, repeated transaction-block detection, and content-span removal for quantities and model numbers.

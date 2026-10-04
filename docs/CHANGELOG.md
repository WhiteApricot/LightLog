# Changelog

本文件采用简化的 Keep a Changelog 风格。重要功能完成后更新 `Unreleased`，不要记录尚未实现的功能。

## [Unreleased]

### Added

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
- Added priority-based explainable evidence fusion, stable semantic category resolution, and an inert Character n-gram classifier interface for future work.
- Added natural Chinese time parsing for relative days, weekdays, month boundaries, dayparts, 24-hour clocks, and spoken Chinese clock expressions.
- Added reproducible knowledge generation/validation and a 10,000-parse performance benchmark.
- Added field-aware amount/status extraction, absolute transaction-time parsing, numeric-role classification, multiple-transaction detection, and refund safety blocking.
- Added a 1666-entity Local Entity Knowledge Base, 1070 positive terms, 167 conflict terms, provenance-preserving source snapshots, and hard generation quality gates.
- Added exact, longest-substring and bounded fuzzy entity matching plus role-aware lexicon evidence.
- Added an independent 190-case blind-evaluation runner and documented the first unacceptable baseline without applying corpus-specific patches.
- Added a pure Dart production `LocalRecognizer`, structured field/span candidates, independent type evidence, confidence calibration, failure analysis, and a standalone benchmark shared by App and tools.
- Added reviewed knowledge roles/kinds/breadth, per-alias match policies, deterministic review samples, scene coverage gates, and runtime distribution reports.

### Changed

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
- Reduced runtime entity knowledge from an unreviewed quantity-driven snapshot to 81 approved consumer entities and 84 reviewed lexicon groups; the 1600 media/game snapshot records remain provenance-only and are excluded from runtime.
- Changed evaluation to report P0/P1/P2 safe rejection, per-field and complete accuracy, display-vs-span content errors, confidence buckets, high-confidence wrong predictions, and average/p50/p95/p99/max latency.

### Fixed

- Preserved historical transaction wall-clock time across device timezone changes by restoring it from the saved occurrence offset.
- Added minute-level manual occurrence-time editing and retained the original offset when editing existing transactions.
- Verified transaction persistence across closing and reopening a real SQLite file.
- Ensured ledger rows and expanded child-category tiles render the selected second-level category SVG rather than the parent icon.
- Replaced title-only SVG variants with genuinely distinct category geometry and added regression coverage against duplicate shapes.

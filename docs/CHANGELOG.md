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

### Fixed

- Preserved historical transaction wall-clock time across device timezone changes by restoring it from the saved occurrence offset.
- Added minute-level manual occurrence-time editing and retained the original offset when editing existing transactions.
- Verified transaction persistence across closing and reopening a real SQLite file.
- Ensured ledger rows and expanded child-category tiles render the selected second-level category SVG rather than the parent icon.
- Replaced title-only SVG variants with genuinely distinct category geometry and added regression coverage against duplicate shapes.

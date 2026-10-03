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

### Changed

- Finalized the V0.1 transaction schema for transfers, refunds, positive minor-unit amounts, and UTC timestamp persistence with occurrence-time offsets.
- Updated Android namespace/application ID, minimum API level, and package metadata for the V0.1 project baseline.
- Completed the Phase 1 manual bookkeeping foundation.

### Fixed

- Preserved historical transaction wall-clock time across device timezone changes by restoring it from the saved occurrence offset.
- Added minute-level manual occurrence-time editing and retained the original offset when editing existing transactions.
- Verified transaction persistence across closing and reopening a real SQLite file.

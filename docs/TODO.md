# 开发任务队列

本文只维护阶段任务及完成状态；需求范围以 [REQUIREMENTS.md](REQUIREMENTS.md) 为准。

## Phase 0 - Documentation and foundation

- [x] Freeze V0.1 requirements
- [x] Define architecture
- [x] Finalize V0.1 core transaction schema and time strategy
- [x] Define recognition pipeline
- [x] Finalize Android application ID, API 26, and V0.1 package metadata

## Phase 1 - Manual bookkeeping foundation

- [x] Add core dependencies
- [x] Implement Drift database and migrations
- [x] Seed default categories/accounts
- [x] Implement transaction repository
- [x] Implement ledger list
- [x] Implement manual add transaction
- [x] Implement edit transaction
- [x] Implement soft delete + undo
- [x] Add basic tests

## Phase 2 - Text smart entry

- [x] Implement deterministic text parsing pipeline
- [x] Produce reviewable RecognitionCandidate results and confirm through the existing editor/repository
- [x] Add parser, confidence, and confirmation-flow tests
- [x] Unify manual/text entry UX and return successful smart entries to the ledger
- [x] Add the lightweight monthly overview and 24-hour wheel time picker
- [x] Expand default income/expense categories and add database-backed SVG icons
- [x] Replace category dropdowns with parent/child icon pickers
- [x] Add and link the recognition algorithm working document
- [ ] Define duplicate fingerprint thresholds and add duplicate-detection tests

## Phase 3 - OCR entry

- [ ] Add isolated ML Kit OcrService and mock
- [ ] Extract candidate fields from payment screenshots
- [ ] Add confirmation flow without retaining source images

## Phase 4 - Recognition learning

- [ ] Persist local recognition rules and events
- [ ] Learn from confirmations, corrections, and undo feedback
- [ ] Enable evidence-based auto-confirm with notice and undo

## Phase 5 - Statistics

- [ ] Implement period and category aggregation
- [ ] Add weekly, monthly, yearly, and custom-range views
- [ ] Add trend and category charts

## Phase 6 - Import/export/backup

- [ ] Implement CSV import/export
- [ ] Implement versioned JSON backup/restore
- [ ] Add validation, compatibility, and round-trip tests

## Phase 7 - V0.1 hardening

- [ ] Complete critical unit, widget, migration, and Android integration tests
- [ ] Review privacy, accessibility, performance, and failure recovery
- [ ] Resolve release-blocking TBD items and prepare V0.1 checklist

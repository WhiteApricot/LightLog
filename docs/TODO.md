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

## Phase 2 - Deterministic text entry and UX foundation

- [x] Implement deterministic text parsing pipeline
- [x] Produce reviewable RecognitionCandidate results and confirm through the existing editor/repository
- [x] Add parser, confidence, and confirmation-flow tests
- [x] Unify manual/text entry UX and return successful smart entries to the ledger
- [x] Add the lightweight monthly overview and 24-hour wheel time picker
- [x] Expand default income/expense categories and add database-backed SVG icons
- [x] Replace category dropdowns with parent/child icon pickers
- [x] Add and link the recognition algorithm working document
- [x] Combine smart text input and manual editing in one entry form
- [x] Group ledger entries by wall-clock date with daily totals
- [x] Add editor deletion and long-press bulk soft deletion
- [x] Use compact vertical collapsible category grids and looping time wheels
- [x] Replace duplicate category artwork with distinct database-backed SVGs
- [x] Replace the account dropdown with database-backed icon choices
- [x] Require explicit recognition and add an above-the-fold result/confirm card
- [ ] Define duplicate fingerprint thresholds and add duplicate-detection tests

## Phase 3 - Five-layer local hybrid recognizer ([refactor plan](PHASE3_RECOGNITION_REFACTOR_PLAN.md))

- [x] Layer 1: strengthen normalization without losing raw input
- [x] Layer 2: use personal confirmation/correction history as local evidence
- [x] Layer 3: add a local Merchant Knowledge Base
- [x] Layer 4: extract and maintain a Category Lexicon
- [ ] Layer 5: only consider a local character n-gram classifier after a separate failure-distribution decision; no interface/model/runtime exists now
- [x] Add fuzzy matching with explicit thresholds and conflict handling
- [x] Fuse implemented layer evidence into priority-based, explainable confidence
- [x] Persist the minimum local rules needed for confirmation/correction learning
- [x] Add deterministic regression cases and a repeatable local performance benchmark
- [x] Add an offline blind-evaluation runner and record first metrics
- [x] Replace the old Parser with one pure-Dart production `LocalRecognizer` shared by App/evaluation/benchmark/tests
- [x] Resolve the first structural Phase 3 blockers with span extraction, numeric protection, independent type evidence, specificity-aware fusion and confidence gating
- [x] Replace quantity gates with reviewed knowledge distribution, alias policy, conflict and deterministic sample gates
- [ ] Preserve and rerun the complete 190-case corpus when the missing 74 original passing inputs are restored; the repository currently contains only the initial report and its 116 failures

## Future - Category management

- [ ] Add category create/rename/reorder/disable UI without physically deleting referenced categories
- [ ] Let user categories map to stable `semanticKey` values and resolve ahead of system defaults
- [ ] Design category merge/remap migration and history-rule behavior before implementing merge UI

## Phase 4 - OCR entry

- [ ] Add isolated ML Kit OcrService and mock
- [ ] Extract candidate fields from payment screenshots
- [ ] Add confirmation flow without retaining source images

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
- [ ] Harden advanced local rule governance and correction/undo feedback
- [ ] Resolve release-blocking TBD items and prepare V0.1 checklist

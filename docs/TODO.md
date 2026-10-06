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

## Phase 3 - Local semantic recognizer

- [x] Layer 1: strengthen normalization without losing raw input
- [x] Layer 2: use personal confirmation/correction history as local evidence
- [x] Layer 3: add a local Merchant Knowledge Base
- [x] Layer 4: extract and maintain a Category Lexicon
- [x] Layer 5: offline train/dev-selected Logistic Regression, compact int8 asset, pure Dart n-gram inference and guarded weak evidence in the unique LocalRecognizer
- [x] Add fuzzy matching with explicit thresholds and conflict handling
- [x] Fuse implemented layer evidence into priority-based, explainable confidence
- [x] Persist the minimum local rules needed for confirmation/correction learning
- [x] Add deterministic regression cases and a repeatable local performance benchmark
- [x] Add an offline blind-evaluation runner and record first metrics
- [x] Replace the old Parser with one pure-Dart production `LocalRecognizer` shared by App/evaluation/benchmark/tests
- [x] Resolve the first structural Phase 3 blockers with span extraction, numeric protection, independent type evidence, specificity-aware fusion and confidence gating
- [x] Replace quantity gates with reviewed knowledge distribution, alias policy, conflict and deterministic sample gates
- [x] Add confident/warning/blocked prefill semantics while retaining warning top-1 fields and blocking only dangerous cases
- [x] Expand reviewed mainland daily knowledge to 447 entities/1307 aliases and 2411 positive/355 negative terms with 106 production review samples
- [x] Preserve and rerun the complete 190-case corpus; final P0 is 97.56%, P1 is 88.06%, P2 safe rejection is 100%, and high-confidence wrong is 0
- [x] Archive superseded Phase 3 plans/reports and remove the inactive n-gram/snapshot pipeline placeholders
- [x] Selectively absorb 5072 reviewed positive terms from the candidate vocabulary pool, preserve zero unresolved owner conflicts, and validate both the original corpus and unseen stress holdout according to [the execution plan](PHASE3_LEXICON_ABSORPTION_PLAN.md)
- [x] Add data-driven lexical families, span conflict resolution, and proximity-aware composition rules; compositional holdout v3 category accuracy is 98.5% with zero high-confidence wrong predictions
- [x] Refine the high-recall family pool without reading holdouts before freeze; expand production to 197 flat families / 2145 unique terms / 316 rules / 95 composition semantics, add generator distribution/conflict gates and four-asset knowledgeHash
- [x] Preserve v4 initial (59.33% category) and one limited generic repair final (62.00%); archive candidates/corpora/superseded reports and validate 89 tests, original/v2/v3 regression and benchmark
- [x] Replace the two family/composition matchers with one indexed FamilyMatcher; add 117 standalone / 80 contextual-only policies without expanding 197 families / 2145 terms / 316 rules
- [x] Replace destructive concept suppression, fuse parent before child, reconcile semantics with preliminary type, and remove unused interface / duplicated routing / generator validation
- [x] Freeze before every holdout; preserve v5 immutable initial and one generic refund-safety repair final; pass 99 tests, analyzer and original 190 regression
- [ ] Phase 3 classification frozen — **not achieved**: v5 initial/final category 75.50% < 80%; type 94.50% → 96.50%, high-confidence wrong 0, P2 safe 100%, warm benchmark p95 0.403 ms. **deterministic semantic routing insufficient**. See [final algorithm/results](RECOGNITION_ALGORITHM.md). Stop tuning v5 and expanding family/composition.
- [x] Complete train/dev-only char 2–4 gram configuration selection, pure Dart weak fallback, parity/safety tests, compact asset and frozen original190/v2/v3/v4/v5 comparisons; high-confidence wrong 0 and P2 safe 100%. See tools/ngram/archive/flat/evaluation_summary.json.
- [ ] Further generalization evaluation requires a new unseen corpus; do not tune the frozen model on historical holdouts. Module freeze does not close Phase 3 classification.
- [ ] Resolve remaining non-blocking content-span families and taxonomy-oracle differences without weakening the zero/high-risk amount and refund safety policy

- [x] 按冻结train/dev完成A posterior → B层级sparse LR → C subword pooling逐级实验；C未达+2pp，按指定规则最终仅保留B，归档旧flat及拒绝模型。
- [x] 同父/跨父权限、弱默认方向reconcile、104-label parity、117项测试、六套历史安全回归与host benchmark；未扩充/重标训练数据。
- [x] 评估tiny PreparedMeal binary；保持具体食材安全边界时无完整pipeline收益，不集成生产。
- [ ] 最终冻结后v7一次验收和Phase3判定；禁止根据v7失败继续调参。

## Future - Category management

- [ ] Add category create/rename/reorder/disable UI without physically deleting referenced categories
- [ ] Let user categories map to stable `semanticKey` values and resolve ahead of system defaults
- [ ] Design category merge/remap migration and history-rule behavior before implementing merge UI

## Phase 4 - OCR entry

Next recognition capability remains Phase 4 OCR structured extraction; Phase 3 classification has **not** met its generalization closure gate. OCR remains outside this task.

- [ ] Add isolated ML Kit OcrService and mock
- [ ] Preserve `OcrDocument` block/line/boundingBox structure and classify each line with `LineRoleClassifier`
- [ ] Extract label-value fields by spatial proximity; separate `MerchantCandidate` and `ProductCandidate`
- [ ] Rank `ContentCandidate` values and forbid receipt-like full OCR text from becoming content
- [ ] Include OCR line distance in amount/time scoring and provide a multi-product fallback
- [ ] Expose field-level confidence and warning UI
- [ ] Keep OCR as structured preprocessing only; reuse `EntityMatcher → LexiconMatcher → TypeInference → EvidenceFusion → CategoryResolver → LocalRecognizer` instead of building a second classifier
- [ ] Add confirmation flow without retaining source images

Phase 3 and the next recognition evaluation do not require strong OCR cases to have correct content/core-text extraction. For the OCR stress subset, evaluate amount, type, category (especially category), and safety; content span and merchant/product extraction remain Phase 4 work.

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

## 历史：V0.1 104类 taxonomy 收缩

- [x] 按用户确认冻结 104 个二级语义，迁移 seed、mapping、已有知识和 review oracle；退役历史分类停用，历史账目不改写。
- [x] Generator 校验 104 类、失效 runtime semantic 引用为零；本轮不读取或运行 holdout。
- [x] 在唯一LocalRecognizer中实现所有证据及分类映射失败后的支出/收入other.general fallback，复用Candidate安全门禁，保持warning。
- [x] 落实明确正餐文本时间 > occurredAtLocal时间段 > 其他food subtype；集中餐段窗口，禁止模型单独猜餐段，保留饮品/零食/食材边界。
- [x] 逐条迁移五套历史失效taxonomy oracle，原始数据归档，104-class校验和SHA256封存后停止访问内容，生产完成前保持v6 blind。
- [x] 生产冻结后统一评测五套migrated-104与v6 immutable first-run，记录失败，禁止继续调本轮算法。v6 category=76%、meal=76%、high-confidence wrong=0；无P2样本。v5/v6未达80%，Phase3整体暂不收口，结果见RECOGNITION_ALGORITHM.md。
- [x] 字符模型仅使用104标签，完成训练、弱fallback集成、测试和评测；未开始OCR。

## Phase 3 最终 96 类收尾（2026-10-06）

- [x] 归档104类源码/模型/数据/指标，冻结96类契约及七套oracle；v7 seal 后保持 blind。
- [x] seed/知识/训练/测试/UI映射迁移；schema v5原子remap及FK/历史/软删除测试。
- [x] train/dev-only Stage-B重训、Direction、F0/F1/F2/F3探索、每parent child校准及Meal必要修复。
- [x] 最终format/analyze/test/parity/dataset/taxonomy/benchmark后freeze；121项测试通过。
- [x] 六套历史regression及v7唯一first-run已完成；Phase 3 NOT CLOSED，保留F3，禁止v7驱动调参。
- [x] 清理、文档与最终结果归档；采用聚焦commit/push交付feature branch，不merge main（实际提交与远端状态以Git为准）。

后续独立任务：审计真实方向/用途语言与训练模板分布、改进作用域表示、复核通用退款关联门禁和口语时间；不得复用本次v7调参/补训练。6个P0/P1退款关联漏检是剩余安全风险，详见冻结后失败分析。

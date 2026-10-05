# 本地语义识别算法

本文描述最终生产结构。隐私、Candidate 与确认边界见 [RECOGNITION.md](RECOGNITION.md)，数据字段见 [DATABASE.md](DATABASE.md)。

## 唯一生产入口

App、evaluation、benchmark、generator review 与业务测试均调用 LocalRecognizer。domain 为纯 Dart，同步执行；历史、活动分类和本地时间由调用方注入。识别只产生 RecognitionCandidate，不写账。

流水线：Normalize → Entity/Lexicon/Family match → SpanConflictResolver → FieldExtractor 与 preliminary type → History/Context evidence → parent-first EvidenceFusion → TypeInference.reconcile → CategoryResolver → confidence 与安全门禁。

FamilyMatcher 合并原有两个 matcher 的职责：字符串只匹配一次，随后仅处理命中的 spans；同时产生 standalone prior 与组合 evidence。按首字符索引 term、按 left family 索引 rule，不扫描全部规则，也不对整个知识库做笛卡尔积。没有 old/new 双路径。

已删除独立 LexicalFamilyMatcher、CompositionalMatcher、concept-only suppression helper、未使用的 Recognizer interface。ContextEvidenceBuilder 不再重复显式餐食词典；TypeInference 不再维护收入来源与支出商品名词的另一套 routing。保留 amount/time/status、退款安全、history、merchant KB 与 CategoryResolver。

## Family schema 与默认语义

family source schema v2 包含 id、kind、terms、policy，以及可选的 prior（单个 semanticKey/score）。policy 为 standalone 或 contextualOnly；模型以 prior 是否存在表达同一约束，单个 family 不支持多个竞争默认值。requiresAdjacentFamily 只约束单字匹配；组合 allowOverlap 显式声明可嵌入的上下文关系，算法不再硬编码具体 family 对。

197 families、2145 normalized unique terms、316 composition rules 保持不变，没有新增词或规则。117 families 为 standalone，80 为 contextual-only。Prior 覆盖 78 child semantics，composition 覆盖 95；联合覆盖 22 parents、100 children。

仅稳定概念具有默认值；宽泛设备、动作、平台、人物等依然可以只有上下文能力。Prior score 按概念稳定性取 0.70–0.78，不能产生高置信自动确认。Composition 是更高优先级的精化或覆盖，明确商品/action/service lexicon 也高于弱 prior；prior 没有成为另一套全文商品词典。

## 非破坏性 span 处理

所有 concept matches 保留到语义处理阶段。概念长度本身不能删除 semantic evidence。SpanConflictResolver 只比较实际输出的正 semantic evidence；negative 或无 span evidence 保留。

更长完整概念已有 prior 时，可以替换其内部的假 substring；更长、同义且不更弱的 evidence 可以去重；不同语义需更高或相同 specificity/score 的实际替代 evidence。Composition 可覆盖其包含的默认值，但单纯 contextual-only concept 不会清空已有分类。

## Parent-first fusion

EvidenceFusion 是唯一融合实现。先按 semantic/family 去相关，每个 child 使用最强证据的 priority/score 和有限独立支持形成 anchor。当前两级 semantic taxonomy 的 parent 是 type.domain。Parent 以最强 child anchor 加有上限的独立支持聚合，避免子类数量或重复别名制造优势；选择 parent 后只在该 parent 内排名 children。Parent 竞争和 child 竞争分别参与 ambiguity/confidence 门禁。

优先级依次为有效 personal history、composition、specific product/action/service、specific entity、general product/action/service、family prior、merchant default、venue/context/platform。负面 evidence 降低对应输出 confidence；fuzzy、宽泛实体、平台、仅商户、仅 prior 和时间推断均有 confidence ceiling。没有新 ontology、hierarchy engine、embedding 或模型。

## 两阶段 type reconciliation

TypeInference.inferPreliminary 读取交易状态、显式金额正负号、入账/付款字段及动作；金额与内容只产生标记为 isDefault 的弱 expense。类别融合前不再按这个初步类型删除 semantic evidence。

TypeInference.reconcile 根据获胜语义修正弱默认或无强方向的类型。显式方向与强语义相反时保留方向并产生 typeConflict；退款状态不能被改回普通交易。income.refund.* 语义也恢复 refund 类型，并统一加入 relatedTransactionRequired，未关联原账目始终 blocked。

## 稳定字段与确认安全

Normalize 保留 raw/display/matching 视图。FieldExtractor 区分日期、订单号、数量、型号和金额；AmountCandidate 保留 role、feature、reason、score，并对接近的不同金额报告 ambiguity。NaturalTimeParser 使用注入的设备本地 now，明确交易日期优先于乘车/有效期等其他日期。

PersonalHistory 只按 normalized content 查询，净支持、纠正次数和最近使用共同限制分数。CategoryResolver 将稳定 semantic 映射到活动两级分类，不能伪造不存在的映射。

amount/type/category/time/content 分别计算 confidence。warning 保留 top-1 并要求人工确认；失败、取消、非交易、多交易、无合法金额和未关联退款保留 blocked 门禁。没有修改 OCR structured extraction。

## Generator quality gates

单一 compositionQuality 检查 id、归一化 term、跨 family 危险共享词、引用、taxonomy、距离、重复 pair/rule、prior policy/score、跨 type prior、两个稳定 object prior 的矛盾和 contextual orphan。只有明确 contextual operand 可以覆盖稳定 object 默认值。Prior 最大 0.79，composition 最小 0.80。

报告 standaloneFamilyCount、contextualFamilyCount、familiesWithSemanticPrior、priorSemanticCoverage、compositionSemanticCoverage、parentCoverage、childCoverage、orphanFamilies、unusedRules，以及 term/kind/rule/domain/conflict 分布。unusedRules 是结构有效性报告，不宣称 106 条 review samples 已覆盖全部 316 rules。family 的机械数量门槛已删除；原 lexicon/entity 质量门禁保留。当前无无效引用、taxonomy、重复 rule、危险共享冲突或 orphan；review 105/106。

四份 runtime 资产共同参与 knowledgeHash：merchants、category_lexicon、lexical_families、composition_rules。最终 FNV-1a hash 为 288a37c0。

## 冻结与 blind protocol

设计、schema、代码、synthetic mechanism tests、原 190 regression 和 benchmark 完成前未读取任何 v2/v3/v4/v5 corpus。98 tests、analyze、format、generator、diff check 通过后记录 pre-holdout tree aebe9b65694f9c1bceb61c0c1c4d76f14ec72edd。四资产 SHA-256 与 frozenAt 保存在 [freeze](../tools/knowledge/review/phase3_semantic_routing_freeze.json)。旧 regression 完成且生产未变后再次记录 [v5 freeze](../tools/knowledge/review/phase3_semantic_routing_v5_freeze.json)。

v5 首次运行立即保存 [initial report](../tools/evaluation/phase3_semantic_routing_v5_initial.json) 和 [initial analysis](../tools/evaluation/phase3_semantic_routing_v5_initial_analysis.md)，工具拒绝覆盖。之后仅做一次通用退款 reconciliation/安全门禁修复；没有新增任何 term、family 或 composition rule。99 tests 与原 regression/benchmark 再次通过，final tree 68cf26d20640d9a9c91f8acd1fe69d037a4c7e6f，见 [final freeze](../tools/knowledge/review/phase3_semantic_routing_final_freeze.json)。[Final report](../tools/evaluation/phase3_semantic_routing_v5_final.json) 已保存，此后停止调 v5。

## 最终 evaluation

| Corpus | Category | Type | High-confidence wrong | P2 safe |
|---|---:|---:|---:|---:|
| 原 190 | 96.32% | 100% | 0 | 100% |
| v2 regression | 90.53% | 100% | 0 | 100% |
| v3 regression | 97.50% | 98% | 0 | 100% |
| v4 regression | 67.67% | 97.33% | 0 | 100% |
| v5 initial | 75.50% | 94.50% | 0 | 100% |
| v5 final | 75.50% | 96.50% | 0 | 100% |

v3 的最终 type 比修复前 99% 低 1pp：通用 refund 语义现在统一要求退款类型和关联门禁，旧 corpus 部分 income/refund oracle 存在差异；没有为旧 oracle 增加例外。

v5 为 400 cases，覆盖全部 118 child semantics；56 semantics 的分类全部正确。Parent accuracy 81.25%，child accuracy 75.50%。Initial/final category=null 均为 47，非空 wrong-category 均为 51。98 个 category failures 中：43 无 semantic output，另外 4 有 semantic 但无 category mapping，28 非空 parent 错，23 parent 对但 child 错。Type failures 22 → 14，与 category failures 可以重叠，不应相加。

P0/P1/P2 分类分别为 84.75%/71.43%/100%。全量 group、semantic、confidence/confirmation 和失败分布保留在 reports。Final warm evaluation p50/p95/p99 为 0.256/0.689/1.141 ms；10,000 次 benchmark 为 0.145/0.403/0.495 ms。

Recognition domain 20 → 19 文件，2900 → 2891 行；generator 728 → 643 行，重复 validation 合并到 compositionQuality，新增机制与 schema tests。候选与旧中间 knowledge review 归档；各次有历史价值的 blind initial/final 保留，根目录无测试 JSON。

Frozen source snapshots are reachable through commits 776afbb6bee24d8323f557f4448f20a3f8d0a0ee (pre-blind) and b3af88ec355140c15d86ab2d98a9ff5287720138 (single generic repair). Trees were recorded before evaluation; snapshot commits were materialized during archival.

## v5 final group category accuracy

| Group | Cases | Category | Parent | Type |
|---|---:|---:|---:|---:|
| fallback | 2 | 100.00% | 100.00% | 100.00% |
| family_pet_core | 30 | 86.67% | 86.67% | 93.33% |
| finance_core | 18 | 44.44% | 44.44% | 88.89% |
| hierarchy_digital | 4 | 50.00% | 100.00% | 100.00% |
| hierarchy_education | 2 | 100.00% | 100.00% | 100.00% |
| hierarchy_food | 4 | 75.00% | 100.00% | 100.00% |
| hierarchy_housing | 4 | 75.00% | 75.00% | 100.00% |
| hierarchy_medical | 4 | 100.00% | 100.00% | 100.00% |
| hierarchy_social | 2 | 50.00% | 50.00% | 50.00% |
| hierarchy_sports | 3 | 100.00% | 100.00% | 100.00% |
| hierarchy_subscription | 3 | 66.67% | 66.67% | 100.00% |
| hierarchy_transport | 4 | 25.00% | 25.00% | 100.00% |
| hierarchy_travel | 2 | 50.00% | 50.00% | 100.00% |
| income_core | 78 | 73.08% | 83.33% | 89.74% |
| semantic_core | 195 | 80.00% | 85.13% | 99.49% |
| span_routing | 6 | 100.00% | 100.00% | 100.00% |
| travel_social_core | 33 | 63.64% | 69.70% | 100.00% |
| type_reconcile | 6 | 66.67% | 66.67% | 100.00% |

## 决策与下一步

Phase 3 classification **未达到 freeze 条件**。v5 < 80%，结论为 **deterministic semantic routing insufficient**。不继续扩 family/composition，不继续调 v5。下一项独立算法工作应评估 character 2–4 gram + lightweight linear classifier / Naive Bayes 作为低置信 fallback evidence，保持相同 LocalRecognizer 和 safety gates；本轮未实现 n-gram。Phase 4 OCR structured extraction 仍单独维护，不能用 OCR 内容提取掩盖分类泛化不足。

# Phase 3 候选词库吸收执行计划

> 状态：已于 2026-10-05 执行完成。15,269 个 normalized positive 候选中选择性吸收 5,072 个，覆盖 118/118 semanticKey；候选 negativeTerms 未批量导入。最终验证结果见 [RECOGNITION_ALGORITHM.md](RECOGNITION_ALGORITHM.md)。

本文是 `lightlog_lexicon.json` 的一次性执行规范。候选文件包含 118 个 semanticKey、15,271 个 positive terms、15,434 个 negative terms、2,984 个组合词和 1,106 组跨分类冲突。它只作为 candidate vocabulary pool，禁止整包复制进 runtime。执行目标是在不改变单一 `LocalRecognizer` 架构的前提下，选择性吸收约 3,000–6,000 个真正有价值的新增 positive terms。

## 冻结边界与输入

- 生产入口、证据优先级、confidence/confirmation gating 和 `CategoryResolver` 不因导词而重写。
- 候选文件通过命令行 `--candidate <path>` 传入，不把开发机绝对路径写入仓库。
- 原 190-case regression、现有 runtime assets、review samples 和 benchmark 先记录 baseline。
- 新 stress holdout 在生产代码、源词库、生成器门禁和 benchmark 优化全部冻结前保持 blind：不得打开、grep、search、parse 或预读取。
- OCR stress subset 本轮只考察 amount、type、category 和 safety，不以 content span / merchant-product extraction 为通过条件。

## 执行产物

新增 `tools/knowledge/prepare_lexicon_candidates.dart`，只负责确定性分析与生成待审清单，不直接改 runtime。建议输出以下可重复生成的临时/评审产物：

```text
tools/knowledge/review/lexicon_candidate_report.json
tools/knowledge/review/lexicon_candidate_review.json
```

报告保存候选原字段、normalized term、建议 semantic/role、分数、冲突、过滤原因和来源字段；review 文件只保存最终 `accepted/rejected/contextOnly` 决策及备注。选择性合并仅写入现有 `category_lexicon_source.json` / `lexicon_expansion_source.json`，不得创建第二套 runtime 词库。

## 1. 解析与 taxonomy validation

1. 校验 JSON version、statistics、118 个 category 对象和 `crossCategoryConflicts` schema。
2. 候选 `semanticKey` 必须存在于 `defaultCategories`；未知、已停用或父级/名称与当前 taxonomy 明显不一致的记录标为 `invalidTaxonomy`，不自动映射。
3. 将 `positiveTerms`、`colloquialTerms`、`actions`、`objects`、`modifiers`、`negativeTerms`、`conflictTerms` 拆为带来源字段的候选；保留原词用于审计。
4. `actions/objects/modifiers` 不能因字段名直接成为独立 positive：只有本身具有明确记账语义时才能单独进入；否则标为 `contextOnly`，供组合或冲突机制使用。

## 2. 规范化、diff 与去重

1. 复用 production matching/index normalization；禁止另写一套会产生不同 key 的清洗规则。
2. 构建现有 base + expansion 的 normalized term owner 索引，分别统计 exact existing、same-semantic duplicate、cross-semantic collision 和真正新增。
3. 同一 semantic 内重复词合并，并保留所有候选来源；与现有词完全相同或规范化后相同的项不计入新增吸收数。
4. 一个高确定性词原则上只有一个 primary semantic。跨 semantic 重复项不得复制到多个 positive 列表。

## 3. 风险过滤与冲突归属

默认拒绝以下候选，并在报告中记录单一主原因和可选次原因：

- 单个汉字、单个字母/数字、过短拉丁缩写，以及 production short/high-risk validator 命中的词；
- 纯金额、日期、数量、型号、订单号、支付状态或平台 UI 模板文本；
- 需要猜测主语/对象才能成立的多义词、过宽名词或脱离上下文的通用动作；
- 明显机械排列、同义反复、不可自然输入的长串、解释性句子、营销/搜索语句；
- 非记账语言、taxonomy 边界错误、低价值品牌堆积和仅用于 OCR content 的票据整行；
- 与已有高确定性 owner 冲突但没有可靠区分上下文的词。

多义词进入 `conflict/context` 机制：结合候选自带的 1,106 组冲突、当前 generator 冲突 owner 和实际词义，指定唯一 primary owner；其余 semantic 只可增加小而必要的 negative/conflict/context 项。无法确定 owner 的词拒绝，不以多处复制规避决策。

## 4. 候选评分

为每个真正新增 positive 计算 0–100 的可解释分数，并把各分项写入报告：

```text
semantic precision       0..30
real bookkeeping usage   0..20
weak-coverage gain       0..15
specificity              0..15
natural colloquial form  0..10
independent-source value 0..10
- ambiguity risk         0..30
- synthetic/templated    0..25
- short-token risk       0..25
- cross-category conflict 0..25
```

- `>= 75`：进入 semantic-level review 队列，不代表自动接受；
- `60..74`：只有弱覆盖 semantic 或明确组合上下文可人工提升；
- `< 60`：默认拒绝。

优先级按当前 `quality_report.json` 的 `termsBySemantic` 从低到高分层：先补 narrow/弱覆盖和真实高频缺口，再补已充分覆盖类别。目标 3,000–6,000 是上限区间而非配额；达不到质量门禁时宁可少吸收。

## 5. Semantic-level review 与 selective merge

1. 按 semanticKey 生成 review batch；每批同时展示现有 positive/negative、候选新增、跨类冲突和相邻 taxonomy。
2. 人工确认 `accepted/rejected/contextOnly`、primary semantic、role、specificity、score 与简短理由。
3. 合并优先扩展现有相同 semantic + role + specificity group；只有确有不同证据角色时才新增 group。
4. 每批先处理 positive，再仅为已确认的真实边界补 negative/conflict。禁止批量导入候选 JSON 的 15k+ negativeTerms。
5. negative/conflict 只保留能区分相邻类别、能阻止已知误判且不会压制正确长词的项；通用词的大面积互斥列表一律拒绝。

## 6. 生成器门禁与知识再生成

所有 accepted term 最终必须通过 `generate_knowledge.dart` 的 normalized duplicate、cross-category owner、短词、高风险词、taxonomy、review sample、规模和资产体积校验。必要时扩展 generator 的报告/校验，但不得降低现有门禁来容纳候选。

```bash
dart tools/knowledge/prepare_lexicon_candidates.dart --candidate <lightlog_lexicon.json> --report tools/knowledge/review/lexicon_candidate_report.json --review tools/knowledge/review/lexicon_candidate_review.json
dart tools/knowledge/generate_knowledge.dart
```

生成后记录最终 entity、alias、positive、negative 数量；另记录候选总数、exact existing、接受数、拒绝数、context-only 数及按原因分布。runtime assets 总大小必须 `< 2 MiB`。

## 7. 冻结前验证

按以下顺序执行，任一步失败都先修复生产词库/通用逻辑，再进入下一步：

1. generator validation 与 knowledge loader/matcher unit tests；
2. 原 190-case regression，保存新报告并与当前 final baseline 对比；
3. `dart format .`、`flutter analyze`、`flutter test`；
4. benchmark：warm recognize `p95 < 5 ms`，同时记录 p50/p95/p99、max 和 cold decode；
5. 若词量导致 p95 回退，允许优化现有 matcher 索引/最长匹配，但不得另建测试专用路径；
6. 确认 high-confidence wrong 仍为 `0`，P0/P1/P2 safety、amount/type/category/time 不出现不可解释回归；
7. review diff，冻结生产代码、知识源、generator 和性能优化。

## 8. Unseen holdout 协议

仅在上一步完全冻结后首次读取 `lightlog_phase3_stress_holdout_v2.json`。第一次运行的原始 report 必须立即以不可覆盖的新文件保存；从第一次运行完成后，该数据才可转为普通 regression。

至少统计：overall、P0、P1、P2、P2 safe rejection、amount/type/category/time accuracy、high-confidence wrong、confident/warning/blocked distribution、p50/p95/p99 latency、failure families，以及 OCR subset category accuracy。OCR subset 不要求 content extraction 正确。

holdout 失败只允许少量、明显可泛化且有独立回归测试的修复；禁止按原句、金额、商户组合或 case id 硬编码。修复后保留首次报告，另写 final report 和 failure analysis。

## 9. 完成门禁

- 实际吸收 3,000–6,000 个新增 positive 为目标；质量不足时可低于下限，但必须说明过滤原因，绝不为凑数放宽门禁。
- 高确定性词维持单一 primary semantic；所有未解决 cross-category positive conflicts 为 0。
- negative/conflict 数量经过精简且逐项可解释，不跟随候选规模同比膨胀。
- runtime assets `< 2 MiB`；benchmark warm p95 `< 5 ms`；high-confidence wrong `= 0`。
- App、evaluation、benchmark、unit tests 继续共用 production `LocalRecognizer`。
- 更新 knowledge statistics、evaluation reports、`RECOGNITION_ALGORITHM.md`、`TODO.md` 和 `CHANGELOG.md`，并报告主要剩余 failure families。

# 本地混合识别算法

本文记录 Phase 3 单一生产识别内核的实际实现。稳定的隐私与 Candidate 边界见
[RECOGNITION.md](RECOGNITION.md)，数据字段见 [DATABASE.md](DATABASE.md)。

## 唯一入口与流水线

`LocalRecognizer.recognize(RecognitionInput)` 是唯一生产算法入口。App 通过
`RecognitionCoordinator` 装配历史和活动分类；evaluation、benchmark 与 unit tests 通过各自输入
adapter 调用相同的 `KnowledgeDecoder` 和 `LocalRecognizer`，不存在 test-only Parser。

```text
Raw text / OCR text
→ raw + display + matching normalization
→ transaction status + natural-time spans
→ protected numeric spans + AmountCandidate scoring
→ entity / lexicon matches + content span
→ lexical family matches + span conflict resolution + composition rules
→ independent TypeEvidence / TypeInference
→ Personal History + Entity + Lexicon + Context evidence
→ specificity-aware Evidence Fusion + confidence gating
→ semanticKey / CategoryResolver
→ RecognitionResult (RecognitionCandidate)
```

`domain/` 是纯 Dart，同步且不依赖 Flutter、Riverpod、Drift、AssetBundle 或 `dart:io`。AssetBundle、
CLI `File`、Drift history 和 ledger draft mapping 位于 `data/application` 或工具 adapter。识别器只能
提出 Candidate，没有数据库写入能力。

## 文本视图与 content span

Normalization 保留不可变 `rawText` 和大小写友好的 `displayText`，另建用于匹配的
`matchingText` 与紧凑 `indexKey`。字段解析以半开区间 span 记录来源，内容提取通过选择、保护或移除
span 完成，不对原文做无边界的全局替换。评测分别统计真正的 content span error 与仅展示格式差异。

显式商户/商品字段优先；叙述句在已知实体、具体 product/action/service 和场景商户之间按 span 与角色
选择。支付平台是可移除上下文，不能覆盖具体商品或行为。结果展示尽量保留用户原始大小写；OCR 在实体
字符间插空格时可回落到已审核 alias 的展示形式。

## 状态、数字和金额

`TransactionStatusDetector` 输出 success、failed、cancelled、refund、nonTransaction 或 unknown，
并识别多交易块。失败、取消、非交易页、多交易和未关联退款进入结构化安全 issue，不能直接保存。

日期、时刻、实体数字、长订单号、手机号、数量、尺寸、型号、标题数字和时长先形成 protected span 或
numeric role。`AmountExtractor` 对全部剩余数字生成带 feature/reason/score 的 `AmountCandidate`：

- 实付/支付金额/付款金额/实际支付最高，应付/到账次之，总金额/商品金额再次；
- 优惠、原价、余额、面额、订单号、手机号、车次、里程和数量降权或排除；
- 支持货币符号、元/块、`18块6`、中文整数金额和 OCR 数字内空格；
- 最高候选分差不足且金额不同则报告 ambiguity；相同金额的重复展示不制造伪冲突；
- 0、超过两位小数和无法解析值不进入可用金额。

## 时间

`NaturalTimeParser` 支持今天/昨天/前天、本周/上周星期、月初/月末、餐时/daypart、24 小时钟、
中文时刻和多种绝对日期。多个业务日期按支付/交易时间、下单时间和其他业务时间排序，乘车日期、场次、
有效期不能覆盖明确交易时间。裸“周五”没有周范围，产生 `ambiguousWeekday`，不猜测具体周。全部解析
基于注入的设备本地 `now`；未给时间时保留当前本地时间。

## TypeEvidence、语义证据与 Fusion

类型和类别独立决策。显式正负号、收入/支出动作、交易状态、金额和内容分别产生 `TypeEvidence`；未知
类别仍可保留可靠 expense/income type，类别 semanticKey 也不能反向强制类型。退款单独映射 refund。

类别优先级为：

```text
通过净支持门禁的 Personal History
> specific product / action / service
> specific reviewed entity
> merchant default semantic (fallback)
> venue / context
> platform / broad entity
```

同 family 证据先去相关；跨来源同向证据仅小幅加分。fuzzy、platform、broad-only、merchant-only 和强
冲突有 confidence ceiling。amount/type/category/time/content 各有独立 confidence，overall 取安全门禁
后的结果。预测字段与确认安全级别分离：`confident` 预填并正常确认；`warning` 仍保留金额、类型、内容、
时间和分类 top-1，同时展示低置信/冲突并允许用户修改或人工确认；`blocked` 尽量展示已提取字段，但禁用
快捷入账。只有支付失败/取消、非交易页、明显多笔、未关联退款、空输入或无合法金额属于 blocked；分类
低置信、分类冲突、一般时间歧义和可恢复金额歧义只属于 warning。

Personal History 只按索引化 normalized content 查询。命中次数必须形成正净支持；纠正、冲突和最近使用
共同限制分数，单次确认不会机械触发最高优先级。

## 知识资产

运行时实体使用受控 `kind`（merchant/platform/service/mediaTitle/gameTitle/productBrand）、`breadth`
（broad/specific）、review status、默认 semantic 和每 alias match policy（exactOnly/substring/fuzzy）。
实体默认语义只是 fallback；platform 可不带 semantic。词典使用受控 evidence role
（product/action/service/merchantType/venue/platform）、specificity 和 negative/conflict terms。

数量与质量同时是硬门禁。当前生成结果为：

- 447 个 approved runtime entities、1307 个 normalized aliases；
- 267 个 lexicon groups、7486 个 positive terms、355 个 negative/conflict terms；
- 63 个高频大陆日常 semanticKey 覆盖率 100%，每项至少 10 个真实表达和 2 个有意义冲突词；
- 106 条覆盖实体、alias、product/action/service、组合语义、platform、broad、conflict 和 income 的
  production matcher/fusion review samples 为 106/106；
- 分层人工清单核对 50 个实体和 100 个 lexicon term，均存在于最终 runtime；
- runtime entity kind 分布：merchant 229、service 187、platform 30、productBrand 1；大陆场景占比 100%，
  media/game title runtime 占比 0%；
- Phase 3 的 1600 个未审核 media/game snapshot records 从未进入 runtime，现已连同抓取脚本归档并退出 active generation pipeline；
- runtime assets 281148 bytes，远低于 2 MiB。

生成命令：

```bash
dart tools/knowledge/generate_knowledge.dart
```

生成器验证 schema、kind/role/breadth、alias policy、规模、实体分布、每 semanticKey 词族、重复与未解决
冲突、短/高风险词、固定抽样、人工抽查清单和体积，并写出 `tools/knowledge/quality_report.json`。公开快照
仅作为显式开发输入，App 运行时从不联网。

## Evaluation、失败分析与性能

长期工具：

```bash
dart tools/evaluation/evaluate_recognition.dart --corpus <corpus.json> --report <report.json>
dart tools/evaluation/analyze_failures.dart <report.json> <summary.md>
dart tools/benchmark/benchmark_recognition.dart
```

evaluation 输出 P0/P1/P2 exact、P2 safe rejection、amount/type/category/time/content/complete、展示格式与
真实 span 错误、confidence buckets、high-confidence wrong，以及 average/p50/p95/p99/max。报告带 corpus、
recognizer version 与 knowledge hash。benchmark 分开统计 cold knowledge decode 和 warm recognize。

2026-10-05 候选词库吸收后的 benchmark（Windows、10,000 次 warm parse）：average 202 µs、p50 152 µs、
p95 420 µs、p99 528 µs、max 2236 µs，p95 < 5 ms 门禁通过；cold decode 27314 µs。

完整 190-case corpus 已恢复为 `tools/evaluation/phase3_regression_corpus.json`。该轮盲测先冻结算法与
知识门禁，初测报告归档于 `tools/evaluation/archive/phase3/phase3_usability_initial.json`；仅做泛化修复后的最终报告为
`phase3_usability_final.json`，失败摘要为 `phase3_usability_final_analysis.md`。最终实测：P0 40/41
（97.56%）、P1 118/134（88.06%）、P2 safe rejection 100%、amount 100%、type 98.95%、category
96.84%、time 100%、content 93.16%、content span 94.21%、high-confidence wrong 0、p95 1.076 ms。
唯一 P0 未通过项是旧 corpus 将金额 0 标为 partial/`invalid_amount`，而当前安全规则按“无合法金额”
进入 blocked/`amount_unrecognized`；这是明确的安全语义差异，不为提高指标放宽。

P1 已高于 75% 停止点和 80% 阶段目标，因此本轮不进入 n-gram。若后续独立 corpus 的 P1 明显低于
75%，停止继续堆
确定性规则，先分析失败分布，再由人工决定是否创建真正的 char n-gram evidence source。n-gram 即使启用，
也只能成为同一个 `LocalRecognizer` 的内部证据层，不能形成第二套识别器。

## Phase 3 候选词库吸收与 stress holdout

候选原件归档为 `tools/knowledge/archive/phase3/lightlog_lexicon_candidate.json`。确定性 prepare 工具复用
production normalization，对 15,269 个 normalized positive 候选完成 taxonomy、现有词 diff、短词、
跨类别 owner、显式 conflict、低价值模板、机械重复和语义级上限检查；接受 5,072 个，过滤 10,197 个，
覆盖候选的 118/118 semanticKey。候选中的巨量 negativeTerms 不导入，最终 negative/conflict 仍为 355，
未解决 cross-category positive conflicts 为 0。逐词决策和汇总位于 `tools/knowledge/review/`。

吸收后原 190-case regression 与吸收前完全一致：P0 97.56%、P1 88.06%、P2 safe rejection 100%、
amount 100%、type 98.95%、category 96.84%、time 100%、content 93.16%、high-confidence wrong 0。

生产代码、知识源和性能优化冻结后，首次运行并原样保存
`phase3_stress_holdout_v2_initial.json`。初测 overall 55.79%、P0 66.67%、P1 56.39%、P2 exact 48.72%、
P2 safe rejection 97.44%、amount 100%、type 97.37%、category 81.58%、time 100%、content 77.37%、
high-confidence wrong 3。仅做三类可泛化修复：时钟独立触发的餐时语义置信度封顶、宠物医疗组合证据、
以及“口腔眼科”taxonomy 边界归属。

最终 stress report 为 `phase3_stress_holdout_v2_final.json`：overall 55.79%、P0 66.67%、P1 56.39%、
P2 exact 48.72%、P2 safe rejection 100%、amount 100%、type 97.37%、category 82.11%、time 100%、
content 77.37%、high-confidence wrong 0；confirmation 分布为 confident 20 / warning 155 / blocked 15，
单次 evaluation latency p50/p95/p99 为 266/948/1284 µs。OCR noise subset 的 category accuracy 为
30/35（85.71%），本轮不考核其 content span。

剩余失败主要集中在 OCR/content span（42）、category/fusion 与 taxonomy oracle（34）、status 期望差异
（16）、safe-rejection issue code 差异（12）和 type inference（5）。OCR 商户/商品字段结构化与 content
ranking 仍按 Phase 4 路线处理，不为本轮 corpus 单独改写 Phase 3 content extractor。

## Lexical family 与 compositional holdout v3

Semantic Lexicon 仍直接产生 category evidence，现有 7486 个 positive term 未重建或拆解。
新增 lexical family 是独立 concept 类型，不与 `RecognitionEvidence.family` 的 evidence 去相关职责混用。
首轮运行时资产包含 65 个 family、246 个 term 和 55 条 rule，覆盖组合失败需要的对象、动作、
修饰和场景概念。

```text
EntityMatcher / LexiconMatcher / LexicalFamilyMatcher
→ SpanConflictResolver
→ CompositionalMatcher
→ EvidenceFusion
```

`SpanConflictResolver` 抑制被更长、更具体且不更弱的 span 完整包含的短词，family span 也可阻断
“电动车”内部“动车”这类 substring 误命中，不影响独立多词证据。`CompositionalMatcher` 只组合
当前输入已命中的 family span，遵守 `maxDistance`，不重扫全词库；输出带 span 和规则说明的
普通 `RecognitionEvidence`。生成器校验 family/rule id、空 term、taxonomy 引用、重复/冲突 rule、
距离/分数范围，并报告高风险超短 term。

冻结生产代码、知识、生成器、unit tests、原 regression 和 benchmark 后，首次 200-case holdout
报告 `phase3_compositional_holdout_v3_initial.json` 为 overall/category 65.0%、P0 76.0%、P1 63.53%、
P2 60.0%、high-confidence wrong 0、warning 199 / blocked 1，evaluation p95 0.768 ms。

仅扩展可泛化的组合概念后，`phase3_compositional_holdout_v3_final.json` 为 overall 98.0%、category
98.5%、P0 100%、P1 97.65%、P2 100%、high-confidence wrong 0；group category 为 action_object 100%、
close_category 100%、containment 92%、income_boundary 100%、long_tail_mixed 96%、modifier_context 100%、
platform_specific 100%；warning 199 / blocked 1，evaluation p95 0.954 ms。剩余 4 例为 2 个 containment
边界、1 个 refund type oracle 差异和 1 个社交礼金 taxonomy 边界。

最终原 190-case regression 为 P0 40/41、P1 117/134、P2 safe rejection 100%、category 96.31%、
high-confidence wrong 0。两个新差异是 holdout 与原 corpus 对同一表达给出相反 taxonomy oracle 的
“儿童医院”和“给爸妈生活费”。warm 10,000-parse benchmark p95 0.786 ms，低于 5 ms。已达 Phase 3
当时的停止条件。后续 v4 表明该结果不能外推到日常泛化；本轮结论见下节，不引入 n-gram。

## Phase 3 family generalization v4

2026-10-05 在 `feat/phase-3-local-recognition` 上开展候选概念精炼。知识设计阶段没有读取任何
holdout（包括已经看过的 v2/v3）；先冻结 production、generator、旧 190-case regression 和
benchmark，再运行 v2/v3。历史 regression 暴露一组通用 containment 回退，有限修正后重新冻结，
首次运行 v4 并立即保存 `tools/evaluation/phase3_family_generalization_v4_initial.json`。
冻结源的 SHA-256 记录保存在 `tools/knowledge/review/phase3_family_freeze.json` 与
`phase3_family_v4_freeze.json`，evaluation 自身拒绝覆盖已存在的 `_initial.json`。

候选 399 个 family / 5761 个唯一词 / 353 个组合提示不是标准答案。使用显式 concept allowlist、
自然核心词审核和 production-compatible normalization diff，合并相近子类，剔除机械包装、危险短词、
无意义组合和多义 owner；忽略候选 semantic 提示。最终生产保留候选词 1819 个、过滤 3942 个。
保留原 65 个 family ID 与 55 条 rule，扩展后的最终资产为：

- 197 个 flat family、2145 个 normalized 唯一 family terms、316 条 composition rule；
- 组合输出覆盖 95 个 semanticKey，仍保持 447 entities / 1307 aliases / 7486 positive / 355 negative；
- 无无效 family 引用、无效 semanticKey、重复 rule 或未解决危险共享词，unused family 为 0；
- 医院/门诊保留经过审核的 venue/action 共享角色，其余 family term 只有一个 owner；
- generator review samples 105/106（99.06%），换锁芯的生活服务/住房维修边界仍有分歧；
- 四文件 FNV-1a `knowledgeHash`：initial `69d5deae`，final `40b6b94c`。

Generator 报告同时包含 family 词数、kind、unused、每 family/semantic 规则数、semantic 覆盖列表、
重复与跨 family 歧义、短词及 domain 分布。Family quality 校验在写 runtime 之前完成。Runtime 仍使用
简单平面匹配；normalized term 在初始化时建首字索引，每次只查输入实际出现的首字。组合不重扫词库，
不使用 hierarchy、graph、embedding、ML 或 n-gram。

Span 处理保留被其他概念跨入的 atomic constituent，例如完整 compound 同时包含一个独立 service 时，
不能丢掉组成规则需要的对象。不同 object 的长 span 仍抑制内含短对象；嵌入式 context/object、pet/supply
和 income/income 关系允许不同 span 重叠，完全相同的 span 不充当两份独立证据。较长组合 evidence
可以抑制它完整包含的较短组合。被长 action/income family 包含的原有语义词不被无条件删除。

v4 初测未达标后只进行一次有限修复：增加三组通用车辆/数码/住房可替换部件，增加更换与检测概念，
单字“换”必须紧邻已审核部件（换整机和远距说明不触发）；将三条桌游/剧本杀/密室词归入兴趣爱好。
没有按 case ID、金额或整句添加规则，没有扩展 OCR/content extractor，也没有继续循环调 v4。

最终普通 regression：

| Corpus | Category | Type | P0 exact | P1 exact | P2 exact | P2 safe | High-confidence wrong |
|---|---:|---:|---:|---:|---:|---:|---:|
| 原 190-case | 96.32% | 98.95% | 40/41 | 117/134 | 8/15 | 100% | 0 |
| stress v2 | 88.95% | 97.37% | 13/18 | 84/133 | 18/39 | 100% | 0 |
| compositional v3 | 97.50% | 99.50% | 25/25 | 164/170 | 5/5 | 100% | 0 |

v3 的 category 比历史 98.50% 低 1 个百分点，保留真实差异，不针对旧 oracle 继续扩词。
报告为 `phase3_family_expansion_regression.json`、`phase3_family_expansion_v2_regression.json`、
`phase3_family_expansion_v3_regression.json`。

v4 共 300 cases，覆盖全部 118 个默认二级 semanticKey：

| Metric | Initial | Final |
|---|---:|---:|
| Category | 178/300（59.33%） | 186/300（62.00%） |
| Overall exact | 176/300（58.67%） | 184/300（61.33%） |
| P0 exact/category | 32/56 | 39/56 |
| P1 exact/category | 141/235 | 142/235 |
| P2 exact | 3/9 | 3/9 |
| P2 category | 5/9 | 5/9 |
| Type | 96.00% | 96.00% |
| Amount/time | 100% / 100% | 100% / 100% |
| P2 safe（runner 口径） | 100% | 100% |
| High-confidence wrong | 1 | 0 |
| 118 semantics 全部样本分类正确 | 41/118 | 41/118 |
| p50/p95/p99（单次 evaluation） | 277/660/1362 µs | 291/680/1241 µs |

Final 118 个语义中 95 个至少正确一次；“覆盖”不等同于每个语义都可靠。P2 safe 表示当前 runner 的
安全度量，不等于所有 P2 都 exact，也不等于所有 warning 都被 blocked。

各 group 均为 20 cases：

| Group | Initial category | Final category |
|---|---:|---:|
| transport_extended | 55% | 75% |
| digital_extended | 65% | 70% |
| housing_home | 75% | 80% |
| daily_personal | 70% | 70% |
| food_extended | 55% | 55% |
| medical_extended | 60% | 60% |
| education_extended | 75% | 75% |
| pets_family | 70% | 70% |
| sports_outdoor | 55% | 55% |
| travel_social | 50% | 50% |
| entertainment_communication | 50% | 60% |
| finance_extended | 60% | 60% |
| income_extended | 65% | 65% |
| income_refund_sale | 55% | 55% |
| cross_domain_composition | 30% | 30% |

Initial/final confirmation 均为 warning 297 / confident 1 / blocked 2；overall confidence 分布均为
<0.5：287，0.5–0.65：9，0.65–0.8：3，≥0.8：1。低分的 warning 保留字段，但不能把词族规模
视为高置信保障。初测唯一 high-confidence wrong 是 tabletop venue taxonomy；final 已修正。

Final 剩余 116 个 exact failures，其中 114 个 category failures（75 个没有可用二级语义输出）、
12 个 type failures。主要 failure families：孤立核心商品/服务只有 family concept 而没有可落地
semantic evidence；购买与维修/服务之间的路由；家庭/人情/运动场景组合；收入来源及退款类型；
娱乐、旅行、住房维修和生活服务的 taxonomy 边界。聚集最多的是 cross-domain（14）、travel/social
（10）、income/refund/sale（11 个 exact）、food（9）和 sports/outdoor（9）。完整 failure 分析保存在
`phase3_family_generalization_v4_initial_analysis.md` / `phase3_family_generalization_v4_final_analysis.md`。

Final warm benchmark（1000 warm-up + 10000 parses）：average 207.60 µs、p50 152 µs、p95 436 µs、
p99 516 µs、max 1619 µs；cold decode 30838 µs。Generator、format、analyze 和 89 个 tests 通过。

**Phase 3 classification 未达到冻结收口条件**：v4 final category 62.00% < 90%，尽管 safety 与性能通过。
不能用 197/2145/316/95 的规模门槛替代泛化验收。本轮停止，后续知识修复需新的独立需求与未见 corpus；
不再对 v4 无限扩 family，不引入 n-gram。下一识别能力仍是 Phase 4 OCR structured extraction，
但不能宣称 Phase 3 分类已经 frozen。

候选与一次性初稿筛选脚本已归档至 `tools/knowledge/archive/phase3/`；根目录四个 corpus 已移入
`tools/evaluation/`。此前 usability/absorption/composition/stress 的 superseded final reports 与 analysis
已移入 `tools/evaluation/archive/phase3/`，历史 initial 和本轮 v4 initial 均保留，根目录无临时 JSON。

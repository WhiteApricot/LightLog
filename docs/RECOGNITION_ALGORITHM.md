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

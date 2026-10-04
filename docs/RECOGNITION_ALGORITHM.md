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
后的结果。Phase 3 始终要求用户确认，当前结构性回归的 high-confidence wrong 为 0。

Personal History 只按索引化 normalized content 查询。命中次数必须形成正净支持；纠正、冲突和最近使用
共同限制分数，单次确认不会机械触发最高优先级。

## 知识资产

运行时实体使用受控 `kind`（merchant/platform/service/mediaTitle/gameTitle/productBrand）、`breadth`
（broad/specific）、review status、默认 semantic 和每 alias match policy（exactOnly/substring/fuzzy）。
实体默认语义只是 fallback；platform 可不带 semantic。词典使用受控 evidence role
（product/action/service/merchantType/venue/platform）、specificity 和 negative/conflict terms。

数量不再是质量门禁。当前生成结果为：

- 81 个 approved runtime entities、216 aliases；
- 84 个 lexicon groups、365 positive terms、54 negative/conflict terms；
- 44 个必需大陆日常场景语义覆盖率 100%；
- 固定 30 条 review samples 为 30/30；
- 1600 个未审核 media/game snapshot records 保留 provenance，但全部排除出 runtime；
- runtime assets 约 38 KiB，远低于 2 MiB。

生成命令：

```bash
dart tools/knowledge/generate_knowledge.dart
```

生成器验证 schema、kind/role/breadth、alias policy、重复与未解决冲突、场景覆盖、固定抽样和体积，并写出
`tools/knowledge/quality_report.json`。公开快照仅作为显式开发输入，App 运行时从不联网。

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

2026-10-04 当前 benchmark（Windows、10,000 次 warm parse）：average 536 µs、p50 510 µs、p95 751 µs、
p99 959 µs、max 1675 µs，p95 < 5 ms 门禁通过；cold decode 4360 µs。

仓库保留首次 190-case 报告，但没有保留其中 74 条原本通过的输入，只能重跑报告中的 116 条失败子集。
当前失败子集实测：P0 12/14、P1 66/89、P2 safe rejection 100%、amount 100%、type 93.10%、category
89.66%、time 96.55%、content span 87.93%、high-confidence wrong 0、p95 约 1.27 ms。若假设旧报告的
74 条全字段通过项未回退，可重建 P0 39/41（95.12%）、P1 111/134（82.84%）、type 182/190
（95.79%）、category 178/190（93.68%）、time 186/190（97.89%）；这些是重建值，不冒充完整 190 条
重跑。完整 corpus 恢复后必须正式复验。

P1 重建值不低于 75%，因此本轮不进入 n-gram。若完整 corpus 复验后 P1 明显低于 75%，停止继续堆
确定性规则，先分析失败分布，再由人工决定是否创建真正的 char n-gram evidence source。n-gram 即使启用，
也只能成为同一个 `LocalRecognizer` 的内部证据层，不能形成第二套识别器。

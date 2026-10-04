# 本地混合识别算法

本文记录 Phase 3 本地文字识别器的当前实际实现。稳定的隐私与 Candidate 边界见 [RECOGNITION.md](RECOGNITION.md)，数据字段与迁移见 [DATABASE.md](DATABASE.md)。

## 当前流水线

```text
Raw text
→ amount / type / time parsing
→ Normalization
→ Personal History + Merchant KB + Category Lexicon + disabled n-gram slot
→ Evidence Fusion
→ semanticKey
→ CategoryResolver
→ RecognitionCandidate
→ 用户确认/修改
→ Repository
```

解析器没有数据库写入能力。只有用户保存后，账目 Repository 才写正式交易；识别反馈由独立的 `RecognitionRepository` 更新本地规则。

## 稳定语义与分类映射

识别层不输出用户可见分类 ID，而输出稳定 `semanticKey`，例如：

```text
expense.food.drink
expense.transport.taxi
expense.medical.medicine
income.salary.monthly
```

`CategoryResolver` 在当前活动分类中解析语义。若多个二级分类映射到同一语义，优先用户分类（`isSystem = false`），再按 `sortOrder` 选择。当前默认分类由 schema v4 seed 填充语义键；未来分类管理可修改映射而无需重写商户知识库。找不到映射时 Candidate 保留语义和 issue，不绑定过期 ID。

## 第一层：Normalization

`RecognitionNormalizer` 保留 `rawText`，并生成：

- `normalizedText`：ASCII 大小写、全半角、空白和常见标点统一；
- `normalizedContent`：去除支付成功、支付平台标签及带标签的订单/交易号；
- `normalizedMerchant`：在内容基础上谨慎去除结尾公司后缀、门店号及明显门店/地址括号。

清洗只处理高确定性噪声，不做拼音、繁简转换、错别字修复或任意截断。展示内容仍来自去除金额和时间后的用户文本，规范化结果仅用于匹配和历史学习。

## 第二层：Personal History

用户保存文字账目时，以规范化商户串和最终二级分类的 `semanticKey` 更新本地 `recognition_rules`：

- 预测与最终分类一致：对应语义 `hitCount + 1`；
- 用户改到另一语义：原预测 `correctionCount + 1`，最终语义 `hitCount + 1`；
- 保存 `lastUsedAt` 作为简单最近使用证据。

基础评分由命中次数、纠正次数和 30 天内最近使用共同决定，限制在 `0.55..0.99`。只有 `hitCount > correctionCount` 的精确规范化内容规则参与匹配。Personal History 在融合时拥有最高优先级，可覆盖 Merchant KB；本轮不实现复杂衰减、规则合并或撤销反馈治理。

## 第三层：Merchant Knowledge Base

运行时资产为 `assets/knowledge/merchants.json`。每条记录包含：

```text
canonicalName
aliases
primarySemanticKey
semanticKey
confidence
```

当前包含 71 个高频品牌、190 个规范化名称/别名，覆盖餐饮、咖啡茶饮、外卖、商超便利、出行、铁路、加油、酒店旅行、药房、影音订阅、数码、教育和运动等场景。知识库只做 canonical/alias 精确匹配；门店后缀先由 Normalization 处理。本轮未加入模糊匹配，避免相似短品牌造成误判。

应用启动后的首次需要由 `KnowledgeLoader` 解码资产并通过 Riverpod FutureProvider 缓存；别名在加载时建立 `Map` 索引，单次解析不重复 JSON decode，也不扫描全部商户。

### 生成与校验

可编辑源文件位于：

```text
tools/knowledge/merchants_source.json
tools/knowledge/category_lexicon_source.json
```

执行：

```bash
dart tools/knowledge/generate_knowledge.dart
```

脚本会统一 alias 索引形式，验证 semantic taxonomy、confidence/score 区间，检测重复 canonical、重复/冲突 alias 和词条，并输出 compact JSON。生成过程不抓取 POI，不调用运行时网络。新增事实应优先依据许可清晰的结构化公开数据或品牌官网核验，禁止批量抓取受限地图/点评平台。

当前打包资产总计约 16.2 KiB：商户 11,318 bytes，词典 5,287 bytes，远低于 1 MB。

## 第四层：Category Lexicon

运行时资产为 `assets/knowledge/category_lexicon.json`。当前包含 39 个语义条目、148 个关键词/alias。每项包含 `semanticKey`、正向关键词、alias、负向冲突词和 evidence score。

加载时按关键词首字符建立索引；匹配只访问输入中出现首字符对应的候选列表。负向词在同一输入出现时抑制该词条，例如“咖啡机”不会因“咖啡”直接归为饮品，“宠物医院”不会归为普通门诊。

词典负责未知商户的语义泛化，不补全具体品牌。例如“幸福大药房”可产生 `expense.medical.medicine`，但内容仍为用户原文。

## 第五层：Character n-gram 预留

本轮不包含模型、训练脚本或 ML runtime。`NgramClassifier` 已定义以下边界：输入规范化文本与商户，输出同一种 `RecognitionEvidence` 列表。默认 `DisabledNgramClassifier` 返回空列表。Evidence Fusion 已接受 `source = ngram`，优先级低于确定性词典和时间上下文。

未来实现前仍须确定离线训练集、包体预算、泛化评估、confidence 校准与模型版本兼容；不得上传用户消费数据。

## Evidence Fusion

分类层统一输出：

```text
source
semanticKey
score
description
negative
```

融合不是简单求和：

1. Personal History 有有效记录时直接成为首选；
2. 否则按 Merchant exact、Lexicon、Context、n-gram 的优先级选择；
3. 同一语义由不同来源支持时最多小幅增加 confidence；
4. 不同语义的强证据差距小于 `0.12` 时将 confidence 限制到 `0.55` 并添加冲突 issue；
5. Personal History 与通用知识冲突时仍保留个人结果，只轻微降分；
6. 首选原始分低于 `0.58` 或没有证据时返回不确定，不强行回退“其他”。

字段证据（金额、内容、类型、时间）与分类 evidence 一并保留供解释，但不会通过相加绕过分类阈值。冲突 Candidate 可以带低 confidence 和当前最优分类供用户复核；缺金额、内容、分类语义或当前分类映射则是 blocking issue。

## 金额与类型

- 金额支持可选正负号、整数或最多两位小数、可选“元/块”，使用 `MoneyParser` 转成整数分；
- 多金额不擅自选择，产生 blocking issue；
- `+` 或工资/薪资/奖金/报销等收入词确定收入，`-` 确定支出，其余为支出候选；
- 正式持久化金额始终为正整数，方向由交易类型表达。

## 中文自然时间

所有相对时间均基于传入的 `now`，便于稳定测试。支持：

- 今天、昨天、前天、明天；
- 今早、今天早上、今晚、昨晚、昨天中午、前天早上；
- 本周一至周日、上周一至周日及组合 daypart；
- 这个月初/本月初：本月 1 日 09:00；
- 这个月底/本月底：本月最后一日 20:00；
- 凌晨 02:00、早上 08:00、上午 09:00、中午 12:00、下午 15:00、晚上 20:00；
- `12:30`、`18点`、`晚上八点半` 等显式时刻。

显式时刻覆盖 daypart 默认值；“晚上八点”等 1–11 点表达转换到 24 小时制。周起始日固定为周一。通过 `DateTime` 日历运算覆盖跨月、跨年和闰年月底。

## 性能与测试

商户别名使用哈希索引，词典使用首字符索引；资产仅加载一次。可重复基准：

```bash
flutter test tools/benchmark_recognition.dart
```

2026-10-04 当前 Windows debug test 环境最终验证中，10,000 次代表性解析耗时 1,033 ms，平均约 103.4 µs/次。单元测试另以 500 次解析必须小于 500 ms 作为宽松回归门槛；门槛用于发现数量级退化，不作为跨设备硬实时承诺。

回归测试覆盖已知品牌、大小写 alias、门店后缀、未知品牌词典、个人历史覆盖、证据冲突、不确定结果、收入、金额歧义、相对时间、周/月/年边界、闰年月底、中文时刻、schema migration 与反馈持久化。

## 当前限制

- 商户库是高频小集合，不追求穷举；
- 没有 fuzzy matching、拼音或错别字纠正；
- Personal History 只做精确规范化内容匹配，尚无撤销反馈与复杂衰减；
- n-gram 仅有接口；
- confidence 仍需在更大的离线评估集上校准；
- 自动入账策略尚未开启，当前仍由用户确认。

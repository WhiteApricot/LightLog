# Phase 3 本地识别器后续重构执行计划

> 状态：待执行；本文只记录调研结论与实施顺序，不代表下述重构已经完成。
>
> 审计基线：2026-10-04，分支 `feat/phase-3-local-recognition`，`HEAD=b6a8d0d`。本次审计同时读取了当时工作区中尚未提交的 Phase 3 大修代码、测试、知识资产与首次 blind evaluation 报告。因此后续执行前必须先确认这些文件仍与本文所列路径和职责一致，不能只根据 `HEAD` 猜测。

## 1. 范围、约束与完成定义

本计划的目标是把当前识别流水线收敛为一个纯 Dart、同步、可独立运行和评测的生产内核，并让 App、evaluation、benchmark 和 unit tests 全部调用同一个 `Recognizer`。允许外围使用 Flutter `AssetBundle`、Riverpod 和 Drift，但这些依赖不得进入识别领域模型或算法实现。

本计划不包含 OCR 插件接入、不实现 Character n-gram、不启用自动入账、不改变数据库 schema、不引入网络服务，也不保留“评测识别器”和“App 识别器”两套逻辑。OCR 在 Phase 4 只负责把图片转成带布局信息的输入，之后必须进入同一个生产 `Recognizer`。

重构完成同时满足：

- `LocalRecognizer.recognize(RecognitionInput)` 是唯一生产算法入口。
- 金额仍使用正整数分；所有时间基于注入的设备本地 `now`，Candidate 仍不直接写库。
- `domain/` 不 import Flutter、Riverpod、Drift 生成类型、`dart:io` 或平台路径。
- App、evaluation、benchmark、unit tests 不再直接拼装 Parser 内部阶段。
- 当前 `TextEntryParser` 旧入口及其重复 helper 在迁移完成后删除，不留兼容分叉。
- 190-case corpus 的首次结果仍保留为 immutable baseline；后续报告使用带版本的新文件名，不覆盖首次报告。

## 2. 当前状态审计

### 2.1 逐文件职责与判断

| 当前文件 | 当前职责与实际耦合 | 处理决定 |
|---|---|---|
| `domain/recognition_models.dart` | 同时承载 `EntryDraft`、证据、状态、金额候选和最终 Candidate；import `ledger_models.dart`，且 Candidate 内含 `toTransactionDraft`，把识别领域与账本持久化草稿绑在一起。span、字段 confidence、结构化 issue、type evidence 均缺失。 | **Refactor + Move**：保留概念，改为纯识别模型；账本转换移到 application/App adapter。 |
| `domain/field_extractor.dart` | 在一个类中同时做字符规范化、状态正则、时间解析、数字扫描/角色判断、金额评分、content 删除和多交易检测；offset 基于 `time.remaining`，无法回指 raw text；`_incomeWords` 又承担类型判断。 | **Split + Delete old**：拆成 span scanner、status detector、amount extractor、content extractor；迁移测试后删除 `FieldAwareExtractor` 巨型实现。 |
| `domain/natural_time_parser.dart` | 纯 Dart，可注入 `now`，已有相对/绝对时间；但返回删除后的 `remaining`，会丢失 raw offset，且多个日期统一 `replaceAll`，未输出候选/角色/protected span。 | **Keep + Refactor**：保留规则主体，改为返回 `TimeCandidate`/span；不再负责破坏性删文本。 |
| `domain/normalization.dart` | 纯 Dart；同时把 display 文本 lower-case，并通过 replace 删除平台、订单、地址/门店/公司后缀。当前 raw/display 与 matching 未真正双轨。 | **Keep + Refactor**：字符映射保留；输出 raw/display/matching/index 四种视图及 offset mapping，matching 清洗不得修改 display。 |
| `domain/text_entry_parser.dart` | 当前事实上的算法总装：重复调用 extractor、收集 evidence、强制 type、过滤 evidence、fusion、分类解析、清 content、餐时规则和 Candidate 组装。直接依赖 Drift `Category` 和 ledger enum；`_cleanContent`、`_forcedType`、`_typeFromSemantic`、meal context 均堆积于此。 | **Replace + Delete**：由 `LocalRecognizer` 和专责组件取代；所有调用方迁移后删除文件。 |
| `domain/knowledge_catalog.dart` | 解析 JSON、建索引、实体 exact/substring/fuzzy、词典匹配、edit distance、运行时数据模型全在一处。纯 Dart，但职责过多；实体 `kind` 是自由字符串，运行时把除 platform 外所有实体降为 merchantType。 | **Split + Move**：JSON decode/index build 移到 data；领域保留 immutable catalog、`EntityMatcher`、`LexiconMatcher`；kind/role/specificity 改为受控 enum。 |
| `domain/evidence_fusion.dart` | 纯 Dart；按来源和 role 排序，但 winner 主要由单条 evidence 决定，冲突只看 score gap；实体默认语义仍能压过具体行为，confidence 既是分类置信又被 Candidate 当整体置信。 | **Refactor**：保留单独文件，改为 role/specificity/target 聚合，并将决策与 confidence calibration 分开。 |
| `domain/category_resolver.dart` | 逻辑小且方向正确，但直接使用 Drift `Category`；解析结果也返回数据库对象。 | **Keep logic + Refactor boundary**：改用纯 `RecognitionCategory` 输入和稳定 ID 输出。 |
| `domain/personal_history.dart` | 纯 Dart、按 exact normalized key 匹配；当前 score 公式可保留为基线，但 role 默认 context，且 correction 语义和冲突 gating 不充分。 | **Keep + Refactor**：历史仍最高优先级，但必须满足有效样本、净支持度和冲突安全条件。 |
| `domain/ngram_classifier.dart` | 空接口和 disabled 实现；当前没有模型。 | **Delete now / reintroduce only after stop gate**：避免为未决定方案保留假接口。若停止点评审决定进入 n-gram，再以真实输入输出需求新建。 |
| `data/knowledge_loader.dart` | `AssetBundle` adapter，合理属于 Flutter data 层；但同时固定资源路径并直接创建 domain catalog。 | **Keep adapter + Refactor**：只读取字符串/bytes，交给共用 `KnowledgeDecoder`；CLI 使用 file adapter，但 decoder 与 catalog 相同。 |
| `data/recognition_repository.dart` | Drift 查询与反馈写入边界基本正确；直接引用 normalizer 生成 key，内部使用 `DateTime.now()`，反馈 API 用 category ID 再查 semantic key。 | **Keep + Refactor**：Repository 留在 data；由 application 传入已确定 semantic key 和审计时间，避免 data 层重复 normalize/取时。 |
| `application/recognition_coordinator.dart` | 从 Parser 先算 history key，再查 Repository，再 parse；直接传 Drift `Category`。识别和 feedback 是合理 application 职责，但接口仍暴露持久化类型。 | **Keep + Refactor**：转换数据库分类为纯 domain snapshot，加载 history，构造 `RecognitionInput`，调用唯一 `LocalRecognizer`。 |
| `app/providers.dart` | Riverpod/`rootBundle` 装配位置正确；Provider 名仍是 `textEntryParserProvider`。 | **Keep + Rename**：改为 knowledge、recognizer、coordinator 三段装配；不含算法分支。 |
| `entry/presentation/transaction_editor_page.dart` | 已把历史读取移出 UI，但仍负责 `DateTime.now()`、Candidate 到表单赋值、保存后反馈编排、错误文案和 Candidate 状态展示。只在 Candidate complete 时回填，partial 的可编辑字段未被利用。 | **Refactor UI integration**：保留表单展示/编辑；时钟、识别、反馈由 application service；Candidate→`TransactionDraft` 映射移出 domain，保存成功事件显式触发反馈。 |
| `tools/evaluation/evaluate_recognition.dart` | 直接 `File` 读 asset、直接构造 `TextEntryParser`、复制默认分类转 Drift `Category`、手工注入 history，并在 runner 内重新定义 complete/reject/issue code。底层 Parser 与 App 相同，但生产入口/装配/状态语义并不相同。 | **Refactor**：只负责 corpus I/O、调用 production Recognizer、比较和汇总；状态和 issue code 来自领域结果。 |
| `tools/benchmark_recognition.dart` | 直接构造 Parser、复制分类 seed、只报 average/p95/max；样本很少且混合了首次初始化外的 warm parse。 | **Move + Refactor** 到 `tools/benchmark/benchmark_recognition.dart`；使用同一 harness/Recognizer，报 p50/p95/p99/max。 |
| `tools/knowledge/generate_knowledge.dart` | 同时读源、生成 taxonomy 衍生词、校验、写 runtime asset/report；硬门禁偏数量。`_addTaxonomyLexicon` 自动制造“分类名+费用/费/购买/办理”等非真实语言词。 | **Refactor**：停止自动词形扩张，增加 schema、分布、抽样 manifest 和质量门禁；生成仍是唯一 runtime asset 来源。 |
| `tools/knowledge/merchants_source.json` | 约 71 条人工清单，其中 64 条默认 merchant、7 条 platform；kind 未覆盖 service/product brand 等。 | **Migrate schema + curate**，不在算法 WP 中顺手调分。 |
| `tools/knowledge/source_data/wikidata_entities.json` | 1600 条全部为 media/game title（电影 800、游戏 800），造成 1600+ entity 数量很好看但消费场景分布严重失衡。 | **Audit + aggressively prune/downweight**；只保留具有付费记录价值且 alias 安全的标题，允许总量下降。 |
| `tools/knowledge/category_lexicon_source.json` | 少量人工真实词 + 生成器扩张到 1070 positive/167 negative；role 不完整。 | **Rebuild curated source**，按 product/action/service/merchantType/venue/platform 标注；删除伪词形。 |
| `tools/knowledge/quality_report.json` | 报数量、覆盖、冲突和大小；当前仍含重复 canonical、35 个冲突 alias、4 个冲突 term。 | **Replace quality criteria**：新增分布、短 alias、抽样准确率、role 覆盖、broad 比例、人工审核状态。 |
| recognition unit tests | 覆盖基础金额、时间、实体、历史和性能，但 Parser 测试重复加载资产/复制分类；部分断言把现有错误语义固化，如麦当劳默认“其他餐饮”。 | **Migrate and expand**：阶段级纯单测 + production Recognizer contract test；不以 blind case 字符串特判。 |
| `docs/PHASE3_BLIND_EVALUATION.md` / `phase3_blind_initial.json` | 保存首次 190-case 基线：P0 65.85%、P1 33.58%、P2 safe rejection 93.33%、14 个高置信错误。报告已指出结构性问题。 | **Keep immutable**；后续报告另存版本并由 failure analyzer生成摘要。 |

### 2.2 已符合未来方向的部分

- Candidate 与正式 Transaction 已有安全边界；当前 Parser 不直接写库。
- `NaturalTimeParser`、Normalization、Personal History 和 Evidence Fusion 的主体是无 Flutter 的 Dart 代码，可增量重构而非推倒重写。
- `RecognitionRepository` 已使用 normalized content 索引按 key 查询，不再全表扫描。
- `KnowledgeLoader` 已把 Flutter asset 读取隔离在 data 层。
- `RecognitionCoordinator` 已建立 application 层雏形。
- 知识源、生成物和 quality report 已分离，runtime asset 约 390 KiB，离 2 MiB 上限有余量。
- benchmark 有 warm-up 和 p95 门禁；blind baseline 不可接受后停止了 corpus-specific 调参。

### 2.3 主要重复、死代码与职责泄漏

- `TextEntryParser.historyLookupKey()` 与 `parse()` 各执行一次 Field Extraction，同一输入被扫描两遍，且两个结果可能因未来 clock/规则变化产生偏差。
- `TextEntryParser._cleanContent()` 与 `FieldAwareExtractor` 的 content 清洗、`RecognitionNormalizer` 的 noise 清洗形成三套删除逻辑。
- `FieldAwareExtractor._incomeWords`、`TextEntryParser._forcedType`、semantic key 前缀推 type 形成耦合的多处类型判断。
- evaluation 的 `_candidateStatus` / `_issueCodes` 重新解释领域结果；App 则直接看 `isComplete` 和中文 issue，语义可能漂移。
- App、evaluation、benchmark、parser tests 都各自组装分类和知识；它们只共享算法类，没有共享 production composition/contract。
- `RecognitionCandidate.toTransactionDraft()` 属于错误层级；UI 又自行构造 `TransactionDraft`，构成重复转换逻辑。
- `NgramClassifier` 当前只有空实现，没有调用价值；在决策门之前属于预留死接口。
- `KnowledgeCatalog` 内 exact、substring、fuzzy 与 JSON decode/索引构建难以分别测试和演进。
- generator 的 `_normalize` 只是 `RecognitionNormalizer.indexKey` wrapper，可在建立共用 knowledge normalization contract 后删除。

### 2.4 Keep / Refactor / Move / Merge / Delete 清单

**Keep**

- Candidate-only 安全边界、semantic key、整数金额、本地时钟注入原则。
- `NaturalTimeParser` 的已验证日期/时段规则主体。
- Normalization 的全半角转换和稳定 `indexKey` 思路。
- Personal History 的 indexed exact lookup 及最高优先级原则。
- `RecognitionCoordinator`、`RecognitionRepository`、`KnowledgeLoader` 的分层位置。
- 首次 blind report、190-case corpus、runtime asset < 2 MiB 门禁和 p95 < 5 ms 门禁。

**Refactor**

- `recognition_models.dart`、`natural_time_parser.dart`、`normalization.dart`、`evidence_fusion.dart`、`category_resolver.dart`、`personal_history.dart`。
- App Provider、Coordinator、Repository feedback API、UI Candidate 应用流程。
- evaluation、benchmark、knowledge generator 和全部 recognition tests。

**Move**

- JSON decode/index build：`domain/knowledge_catalog.dart` → `data/knowledge_decoder.dart`。
- Candidate→账本草稿转换：domain → `application/recognition_result_mapper.dart`。
- meal context：Parser 私有方法 → `domain/context_evidence.dart` 或 fusion 前的明确 stage。
- status/type/content helper：Parser/FieldExtractor → 对应 domain 组件。
- benchmark：`tools/benchmark_recognition.dart` → `tools/benchmark/benchmark_recognition.dart`。

**Merge**

- 三套 content/noise 清洗合并为 span extraction + display/matching projection。
- 所有 type 信号合并为 `TypeInference`，但保持与 category fusion 两个独立输出。
- App/evaluation/benchmark/test 的知识与分类 fixture 装配合并为生产 decoder + 小型共用 test/tool harness。
- issue code 与 result status 合并为领域 enum，不再由中文字符串反推。

**Delete（仅在调用方迁移和测试通过后）**

- `domain/text_entry_parser.dart`。
- 当前巨型 `FieldAwareExtractor` 实现及其内部 `_incomeWords`、破坏性 content replace 逻辑。
- `domain/ngram_classifier.dart` 空接口/disabled 实现。
- `RecognitionCandidate.toTransactionDraft()`。
- evaluation 中 `_candidateStatus`、`_issueCodes` 和手工 production pipeline 装配。
- benchmark/test 中重复的 Drift `Category` 构造块。
- generator 中 taxonomy 自动词形扩张 `_addTaxonomyLexicon` 及纯数量下限（以质量门禁替代，不删除 2 MiB 安全上限）。

### 2.5 当前是否真正共用同一逻辑

结论：**部分共用，但尚未达到“同一个 production Recognizer”**。

App 走 `AssetBundle → TextEntryParser → RecognitionCoordinator → Drift history`；evaluation/benchmark 走 `dart:io File → TextEntryParser`，并各自手工创建分类和历史。三者调用同一个 `TextEntryParser.parse`，但 knowledge loader、category model、history lookup、Candidate status、issue code 和 feedback 不共用。后续禁止通过复制 Parser 到 `tools/` 解决可运行性；必须先让生产内核纯 Dart，再让所有入口调用它。

## 3. 目标架构

### 3.1 最终目录

```text
lib/features/recognition/
├── domain/
│   ├── recognizer.dart                 # LocalRecognizer，唯一同步生产入口
│   ├── recognition_models.dart         # input/result/candidate/evidence/issue/span
│   ├── normalization.dart              # raw/display/matching/index + offset mapping
│   ├── field_extractor.dart             # 阶段编排，不再包含所有规则
│   ├── transaction_status_detector.dart
│   ├── natural_time_parser.dart
│   ├── amount_extractor.dart
│   ├── content_extractor.dart
│   ├── type_inference.dart
│   ├── knowledge_models.dart            # entity/lexicon/index 的纯模型
│   ├── entity_matcher.dart
│   ├── lexicon_matcher.dart
│   ├── personal_history.dart
│   ├── context_evidence.dart
│   ├── evidence_fusion.dart
│   ├── confidence_calibrator.dart
│   └── category_resolver.dart
├── data/
│   ├── knowledge_decoder.dart           # JSON schema decode + index build，纯 Dart
│   ├── knowledge_loader.dart            # Flutter AssetBundle adapter
│   └── recognition_repository.dart      # Drift history/feedback
└── application/
    ├── recognition_coordinator.dart     # async I/O + domain snapshot + Recognizer
    └── recognition_result_mapper.dart   # Candidate → editor/ledger draft

tools/
├── evaluation/
│   ├── evaluate_recognition.dart
│   ├── analyze_failures.dart
│   └── phase3_blind_initial.json
├── benchmark/
│   └── benchmark_recognition.dart
└── knowledge/
    ├── generate_knowledge.dart
    ├── validate_knowledge.dart           # 仅在拆出后确有复用价值时新增
    ├── *_source.json
    ├── review_samples.json
    └── quality_report.json
```

目录是职责目标，不要求第一步一次性创建所有文件。只有当相应逻辑和测试实际迁移时才新建文件，禁止先生成空 interface/wrapper。

### 3.2 核心接口

```dart
final class RecognitionInput {
  final String rawText;
  final DateTime nowLocal;
  final int timezoneOffsetMinutes;
  final List<RecognitionCategory> activeCategories;
  final List<PersonalHistoryRecord> personalHistory;
}

abstract interface class Recognizer {
  RecognitionResult recognize(RecognitionInput input);
}

final class LocalRecognizer implements Recognizer {
  LocalRecognizer({required KnowledgeCatalog knowledge});
}
```

`RecognitionResult` 必须直接包含结构化 `status`、`issues`、字段候选、选中 span、field confidence、category confidence、overall confidence、是否允许建议回填，以及 Candidate。UI/runner 不得解析中文 issue 文案来恢复状态。

`RecognitionCategory` 只含识别需要的 `id/parentId/type/semanticKey/isSystem/isActive/sortOrder/name`，不引用 Drift。Coordinator 负责从数据库 `Category` 映射；evaluation 使用相同模型 fixture。

### 3.3 四类调用方如何共享唯一内核

```text
Flutter AssetBundle ─┐
CLI File reader ─────┼─> KnowledgeDecoder ─> KnowledgeCatalog ─┐
test fixture strings ┘                                         │
                                                               v
App Coordinator ─────> RecognitionInput ─────────────────> LocalRecognizer
Evaluation runner ───> RecognitionInput ─────────────────> LocalRecognizer
Benchmark ───────────> RecognitionInput ─────────────────> LocalRecognizer
Unit/contract tests ─> RecognitionInput ─────────────────> LocalRecognizer
```

- App 可以通过 `RecognitionCoordinator` 异步获取 Drift history/categories，但最终只调用同步 `Recognizer.recognize`。
- evaluation 不调用 Coordinator（它不需要 Drift），但必须调用同一个 `LocalRecognizer`、`KnowledgeDecoder`、领域 category snapshot 和 status/issue 定义。
- benchmark 测量 `LocalRecognizer.recognize` 热路径；knowledge decode/asset I/O 单独报告 cold-start，不混入 p95 算法门禁。
- unit tests 可测阶段组件；另设 production contract test，确保默认装配使用的就是 `LocalRecognizer`，不存在 test-only pipeline。

## 4. 算法重构方案

### 4.1 Span-based extraction 与双轨文本

所有字段提取先在字符规范化但不删内容的文本上产生半开区间 `[start,end)` span。每个 span 包含 `kind`、raw/display slice、matching value、source/label、score 和是否 protected。字段组件不得通过 `replaceAll` 形成下一阶段输入。

文本保留四个视图：

- `rawText`：原始输入，审计和 OCR 坐标回指。
- `displayText`：只做安全的全半角/空白展示整理，保留英文大小写和用户写法。
- `matchingText`：lower-case、标点统一、别名匹配使用；不得回写 UI content。
- `indexKey`：仅用于 history/entity hash lookup 的紧凑 key。

Normalization 需要 offset mapping，使 matching span 能映射回 display/raw。Content Extractor 对已识别的时间、金额、标签、订单号、数量等 span 做集合运算，再按角色选择 merchant/product/action/service span；不能靠全文连续 replace。

### 4.2 Protected numeric spans 与 AmountCandidate

先扫描所有数字，再由独立 detectors 标记日期/时刻、订单/交易号、手机号、数量单位、型号/版本、车次、标题序号、距离/时长。被可靠 detector 覆盖的数字是 protected span，金额阶段不能选择；低可靠重叠则保留候选但加冲突 issue。

金额候选评分使用特征而非字符串个案：

- 正向：实付/支付/付款/收款 label 距离与方向、货币符号、金额格式、总计字段、交易块布局、末尾自然语言金额。
- 负向：原价、优惠、余额、面额、退款金额（普通支出场景）、订单号、数量、protected overlap。
- 一致性：相同值多处出现可支持；不同高分候选接近则不选中并返回 `ambiguousAmount`。
- 输出保留所有 `AmountCandidate`、feature breakdown 和选中理由，阈值只能由 regression calibration 调整，不针对单条 case。

中文口语金额（如“18块6”）作为通用金额 grammar 支持；连字符品牌、标题数字、型号数字由 protected span/边界规则解决。

### 4.3 Transaction status 与多交易

`TransactionStatusDetector` 输出 status evidence 和 transaction block spans。failed/cancelled/nonTransaction 是安全阻断；refund 输出 refund type evidence 但在缺少 `relatedTransactionId` 时仍不可保存；success 不是完整性的充分条件。OCR 长文本按强 status/amount/time label 和邻近区域聚类，检测多个独立交易块，而不是只计 marker 次数。

### 4.4 Absolute / relative time

`NaturalTimeParser` 返回候选列表而不是删除后的 remaining：绝对日期、相对日期、daypart、clock 分别有 span 和 role。组合时遵循：明确交易/支付时间 > 下单时间 > 无标签时间；乘车/场次/入住/有效期属于业务时间，除非输入目标明确要求，否则不覆盖交易时间。显式 clock 覆盖 daypart 默认时刻；所有相对计算基于 `RecognitionInput.nowLocal`。

### 4.5 TypeEvidence 与 CategoryInference 解耦

`TypeInference` 独立聚合 sign、收/付动词、退款/status、收入/支出 action、账户流向等 `TypeEvidence`，无分类时也可给出普通 expense 或保持 unknown。Category Fusion 只决定 semantic key，不能再由 semantic key 是否命中决定 type 是否存在。

冲突策略：强显式符号/status > 强动作 > 历史 type > 弱默认。普通消费语言在有支付/花费/实付/明确金额+消费内容证据时可推 expense；仅有裸数字或非交易文本不得默认 expense。Category 与 type 冲突时降级 review/reject，不通过过滤掉另一侧 evidence 来伪造一致。

### 4.6 Specificity、history、fusion 与 merchant fallback

Evidence 除 source/score 外增加 `role`、`specificity`、matched span、entity breadth 和 target semantic。总体优先级：

```text
可靠 Personal History
> specific product/action/service
> specific merchant/entity
> merchantType/venue
> broad merchant default
> platform/context
```

- platform 只描述交易渠道，不应覆盖商品/服务语义。
- broad brand/entity 默认语义只作 fallback；当输入出现更具体的商品、维修、订阅、餐时或服务动作时必须让位。
- merchant default semantic 只在没有可靠具体 span 时参与决策，并设置 confidence ceiling。
- Personal History 仍最高优先，但只有 normalized key 精确、净支持为正、纠正率可接受且与强 status/type 不冲突时才可高置信；历史冲突必须 review。
- 同一 span 派生的多个证据不能被当成独立来源重复加分；按 evidence family/span 去相关后再融合。

### 4.7 Confidence calibration 与安全门

把 `categoryConfidence`、`amountConfidence`、`typeConfidence`、`timeConfidence` 与 `overallConfidence` 分开。`overallConfidence` 取关键字段的保守组合，并受冲突、broad fallback、fuzzy、ambiguous span 的 ceiling 限制。高置信定义和自动确认阈值由离线 calibration 决定；Phase 3 仍不自动入账。

必须建立：

- calibration buckets（例如 `<0.5`、`0.5–0.65`、`0.65–0.8`、`>=0.8`）的 accuracy/coverage；
- 高置信错误硬门禁 `0`；
- 任何强冲突、fuzzy-only、platform-only、broad fallback-only 不能进入高置信区；
- 阈值调优只使用公开 regression/development split，blind holdout 不参与逐 case 调参。

### 4.8 复杂输入的通用数据流

以下表格说明预期的阶段行为，不是字符串特判：

| 输入 | 通用 span/evidence 解释 | 预期决策原则 |
|---|---|---|
| `淘宝 iPhone手机壳 49.9` | platform=`淘宝`；product=`手机壳`；`iPhone` 是 product brand/context；amount=`49.9` | product specific 覆盖 platform/broad phone brand；display content 选择 `iPhone手机壳`，matching 可 lower-case。 |
| `晚饭麦当劳 25` | meal action/daypart word=`晚饭`；merchant=`麦当劳`；amount=`25` | content 选 merchant；餐时 action 比 merchant 的“其他餐饮”默认更具体，分类为晚餐。 |
| `7-Eleven 15` | entity span 含数字和连字符，应先于裸 numeric scanner 被保护；末尾 `15` 是金额 | entity span 中的 `7`/`Eleven` 不成为金额；display 保留大小写和连字符。 |
| `12306 553` | exact entity span=`12306` 并保护其数字；末尾=`553` 金额 | 识别铁路服务，content 为 `12306`，不因实体全数字而吞掉或选错金额。 |
| `速度与激情8 20` | media title exact/longest span 保护标题数字 `8`；末尾 `20` 金额 | 标题数字不是金额；只有经审计的 title entity 才触发保护，不能泛化为任意“文字+数字”。 |
| OCR：原价/优惠/实付/时间/订单号共存 | label-value spans、protected order/time spans、交易 block；原价/优惠为负向 amount evidence，实付为强正向 | 选同一交易 block 内实付；content 从 merchant/product label span 获取；若存在两个 block 则拒绝合并。 |

## 5. Knowledge Base 重构计划

### 5.1 新 schema

每个 entity 至少具有：

```text
id, canonicalName, aliases, entityKind,
defaultSemanticKey?, defaultRole, breadth,
region, source, reviewedAt, reviewStatus, confidence
```

受控 `entityKind`：`merchant`、`platform`、`service`、`mediaTitle`、`gameTitle`、`productBrand`。受控 evidence role：`product`、`action`、`service`、`merchantType`、`venue`、`platform`。`breadth` 为 `specific` / `broad`；platform 和跨品类 product brand 默认 broad。实体可没有 default semantic，只提供 span/entity identity，避免强迫所有品牌绑定分类。

### 5.2 1600+ entity 审计

1. 生成分布报告：来源、kind、semantic key、breadth、alias 长度、数字 alias、ASCII alias、默认置信、是否人工审核。
2. 对当前 1600 条 media/game title 全量自动筛出高风险 alias：短词、常用词、纯数字、与商户/词典重叠、多个 owner、编辑距离邻近。
3. 分层人工抽样：每个 kind/semantic/breadth 至少固定样本量，并对高风险项 100% 审核。
4. 删除与真实消费无关、alias 高歧义或无法合法维护来源的实体；不为守住 1500 数量门禁而保留。
5. 大陆日常覆盖优先补充：连锁餐饮/茶饮、便利店/商超、药房/医院服务、公共交通/铁路/航空、打车/共享出行、运营商/宽带、水电燃气、快递、洗护维修、住宿、教育考试、健身、宠物、本地生活服务。只使用可审查、许可清晰的来源或人工清单，不引入运行时联网。

### 5.3 alias 审核

- canonical 不自动等于安全 alias；每条 alias 记录 normalized form、长度、script、owner 和 risk flags。
- 禁止未限定的高频普通词、过短英文缩写、纯数字 alias 直接 fuzzy；`12306` 等确有价值项用 exact-only policy。
- alias 可标记 `exactOnly`、`substringAllowed`、`fuzzyAllowed`；默认从严。
- 冲突 alias 不再简单静默删除后算质量通过；报告 owner、处置（删除/限定/人工批准）并要求 unresolved=0。
- product brand 如 Apple/苹果、小米、华为默认 broad，无具体商品/服务 span 时只作弱 fallback。

### 5.4 真实语言 lexicon

- 移除 taxonomy 自动生成的“分类名+费用/费/购买/办理”等伪自然词形。
- 每个条目记录 phrase、semantic key、role、specificity、positive contexts、negative/conflict terms、review status。
- 词来自真实记账表达的去标识化人工整理和失败簇归纳；blind holdout 中的单条字符串不能直接复制为特判。
- action/service 与 product 分开：如“维修”是 action，需与手机/电脑/家电 span 组合；“会员”是 broad service，需平台/健身/视频上下文消歧。
- negative/conflict term 必须描述可泛化冲突，如“手机壳”抑制 phone device、“宠物医院”抑制 human clinic、“贷款利息”抑制 interest income。

### 5.5 质量门禁

保留 schema/taxonomy、冲突为零、runtime < 2 MiB 等硬门禁；删除“entity >=1500 / alias >=5000 / positive >=800 / negative >=150”作为成功标准，改为：

- 受控 kind/role/breadth 字段 100% 合法，provenance/reviewStatus 完整。
- unresolved canonical/alias/term conflicts = 0。
- 高风险短 alias、纯数字 alias、broad entity 均有明确 match policy。
- 固定 seed 的分层抽样通过率：exact alias >= 99%，substring >= 98%，fuzzy precision >= 98%，默认 semantic 人工正确率 >= 95%；样本和结果写入 report。
- 大陆日常消费场景的目标分布下限按 kind/场景设置，不以总量替代；media/game 不得支配实体总量。
- 每个高频 semantic key 至少有经审核的真实 product/action/service/merchantType 证据组合；只有 taxonomy 名称不算覆盖。
- runtime asset < 2 MiB；生成结果稳定可复现。

## 6. Evaluation 与长期工具体系

### 6.1 保留的工具

- `tools/evaluation/evaluate_recognition.dart`：读取 corpus，调用 production `LocalRecognizer`，输出机器报告；不含算法逻辑。
- `tools/evaluation/analyze_failures.dart`：读取报告，按 priority/group/field/issue/evidence role/confidence bucket 聚类，输出 JSON + Markdown；不修改知识或阈值。
- `tools/benchmark/benchmark_recognition.dart`：固定 warm-up、重复次数和输入 mix，分别测 hot recognize 与 cold knowledge decode。
- 190-case regression corpus：版本化保留，分 development/regression 与 blind holdout 治理；首次报告永不覆盖。
- unit tests：阶段规则和边界；production contract/integration tests 验证真实装配。
- knowledge validation：schema、冲突、抽样 precision、分布、大小和 reproducibility。

### 6.2 指标定义

每次正式 evaluation 至少输出：

- P0 complete accuracy、P1 complete accuracy、P2 exact accuracy、P2 safe rejection。
- amount、type、category、time、content span accuracy、complete accuracy。
- `displayFormattingMismatch`：span 指向正确语义内容，但大小写、全半角、空白或标点展示不一致。
- `contentSpanError`：选错/多选/漏选 merchant/product/action/service span。二者不得再合并为 content extraction。
- high-confidence wrong count，且列出字段、confidence bucket、主导 evidence 和 ceiling 是否触发。
- latency average、p50、p95、p99、max；注明环境、debug/release mode、warm-up、样本数。
- safe rejection 的 issue-code precision/recall，至少覆盖 non-transaction、failed/cancelled、refund relation、ambiguous amount、multiple transactions。

评测的 `status`、`issueCodes`、`isComplete` 直接来自 `RecognitionResult`，runner 不再通过中文字符串推断。报告记录 corpus version、knowledge version/hash 和 recognizer version，保证结果可追溯。

### 6.3 Corpus 防泄漏

- 190 条作为长期 regression，另保留未参与调参的 blind holdout；任何新增失败样例先归纳成规则族，再加入公开 regression。
- 结构重构期间可使用现有失败分布验证方向，但不得把 case ID/完整输入放进生产条件分支。
- 每个修复必须有最小合成单测 + 至少一个同类变体，证明是 grammar/span/role 规则而非字符串特判。

## 7. 分阶段 Work Packages

下面顺序是强依赖顺序。每个 WP 独立完成、测试、review 后再进入下一项；不得长期保留两条生产入口。

### WP1 — 纯 Dart 内核边界与唯一入口

**修改**：`recognition_models.dart`、`category_resolver.dart`、`knowledge_catalog.dart`（迁移期间）、`recognition_coordinator.dart`、`knowledge_loader.dart`、`app/providers.dart`、相关 tests/tools。

**新建**：`domain/recognizer.dart`、`domain/knowledge_models.dart`、`data/knowledge_decoder.dart`、production recognizer test fixture。

**删除/迁移**：移除 domain 对 Drift `Category` 和 `TransactionDraft` 的依赖；`toTransactionDraft` 移到后续 application mapper。暂不删除 Parser，先把它内部调用转入 `LocalRecognizer`，但 WP1 结束时所有新调用只面向 `Recognizer`。

**接口**：`RecognitionInput → RecognitionResult`；knowledge 在构造时注入，history/categories/now 在 input 注入。

**依赖**：无；是其余 WP 前置。

**测试**：domain import boundary test、KnowledgeDecoder parity、Recognizer contract、App provider smoke test。

**验收**：`domain/` 无 Flutter/Drift/`dart:io` import；App/eval/bench 可创建同一 `LocalRecognizer`；当前行为基线不刻意改变。

**命令**：`dart format lib/features/recognition test/features/recognition tools`；`flutter analyze`；`flutter test test/features/recognition`。

### WP2 — Span / Content Extraction 与双轨文本

**修改**：`normalization.dart`、`field_extractor.dart`、`recognition_models.dart`、`recognizer.dart`。

**新建**：`content_extractor.dart`，必要时在 models 内定义 `TextSpanRange`，不要另造空抽象。

**删除/迁移**：迁移并删除 Parser `_cleanContent`、Normalizer/FieldExtractor 中破坏性 content replace 链。

**接口**：raw text → normalized views + mapped spans → `ContentCandidate(displayText, matchingText, role, span, score)`。

**依赖**：WP1。

**测试**：大小写保持、全半角 mapping、merchant/product/action/service span、冗余自然语言、长 OCR label、重叠 span；将 display mismatch 与 span error 分开。

**验收**：`Steam`/英文品牌 display 不被 lower-case；平台可排除而具体商品保留；content 不依赖按 case 的全文 replace。

**命令**：`dart format ...`；`flutter test test/features/recognition/normalization_test.dart test/features/recognition/content_extractor_test.dart`；`flutter analyze`。

### WP3 — Protected Numeric Span、Amount 与 Time

**修改**：`natural_time_parser.dart`、`field_extractor.dart`、`recognition_models.dart`、`recognizer.dart`。

**新建**：`amount_extractor.dart`；如确有复用再建 `numeric_span_detector.dart`。

**删除/迁移**：删除当前 `_number` 单循环评分和基于 `time.remaining` offset 的金额实现。

**接口**：normalized views + entity/time/status label spans → protected numeric spans + ranked `AmountCandidate` + `TimeCandidate`。

**依赖**：WP2；entity exact span 的保护可先用 knowledge catalog exact matcher，完整 specificity 在 WP5。

**测试**：型号、标题数字、车次、纯数字实体、数量、中文口语金额、多金额 OCR、绝对/相对时间、多个业务日期、span offset。

**验收**：amount >= 97% 的 development target；ambiguous 不猜；time >=97%；所有候选含可解释 feature breakdown。

**命令**：相关 unit tests；`flutter test test/features/recognition`；`flutter analyze`。

### WP4 — Transaction Status 与 TypeEvidence 解耦

**修改**：`field_extractor.dart`、`recognizer.dart`、`recognition_models.dart`。

**新建**：`transaction_status_detector.dart`、`type_inference.dart`。

**删除/迁移**：删除 `_incomeWords`、Parser `_forcedType/_typeFromSemantic` 和“无 semantic key 就无 type”的逻辑。

**接口**：spans/status/category evidence → 独立 `TypeDecision(type, confidence, evidence, conflicts)`；category decision 仍可为空。

**依赖**：WP2–3。

**测试**：普通支出无分类、强收入词/动作、正负号、refund、失败/取消/non-transaction、多 transaction block、type/category 冲突。

**验收**：type >=95%；未知分类的明确普通支出仍保留 expense type；裸数字/非交易页不默认 expense。

**命令**：type/status unit tests；recognition suite；`flutter analyze`。

### WP5 — Entity/Lexicon Specificity 与 Evidence Fusion

**修改**：`knowledge_catalog.dart`（最终拆除）、`evidence_fusion.dart`、`personal_history.dart`、`recognizer.dart`、knowledge runtime schema decoder。

**新建**：`entity_matcher.dart`、`lexicon_matcher.dart`、`context_evidence.dart`、`confidence_calibrator.dart` 初版。

**删除/迁移**：删除 `KnowledgeCatalog` 中 matcher 混合实现和 Fusion 旧 priority helper；不再把所有非 platform entity 当 merchantType。

**接口**：结构化 spans/catalog/history → evidence families → category decision + conflicts + confidence ceilings。

**依赖**：WP2–4；使用旧知识内容但新 schema 可先兼容 decode，WP7 再改数据。

**测试**：product/action/service > broad entity/platform、merchant fallback、餐时行为、negative evidence、同 span 去相关、history override 与 history conflict、fuzzy ceiling。

**验收**：示例族均由 role/specificity 规则通过；强冲突不高置信；Fusion 不引用字符串 case。

**命令**：matcher/fusion/history tests；全 recognition tests；benchmark quick run；`flutter analyze`。

### WP6 — Confidence Calibration 与安全 gating

**修改**：`confidence_calibrator.dart`、`recognizer.dart`、`recognition_models.dart`、evaluation report schema。

**新建**：calibration test/fixture；不引入 ML package。

**删除/迁移**：删除单一 `fusion.confidence` 直接充当 Candidate 总置信的逻辑。

**接口**：各字段 decision/conflict flags → per-field + overall confidence、review/complete/reject gate。

**依赖**：WP3–5。

**测试**：confidence bucket、ceiling、critical field minimum、conflict/fuzzy/platform-only/broad-only gating。

**验收**：development/regression 上 high-confidence wrong=0；所有高置信结果有充分且可解释证据；Phase 3 仍只建议、不自动入账。

**命令**：calibration tests；evaluation（development corpus）；`flutter analyze`。

### WP7 — Knowledge Base 质量重构

**修改**：`merchants_source.json`、`category_lexicon_source.json`、`generate_knowledge.dart`、`tools/knowledge/README.md`、runtime assets、quality report。

**新建**：review sample manifest/schema；可选独立 validator（仅当 generator 与 CI 共用时）。

**删除/迁移**：删除 taxonomy 自动伪词形、纯数量门禁；清理/降权大批 media/game、broad brand/platform 和危险 alias。

**接口**：reviewed source + provenance → deterministic runtime assets + quality report。

**依赖**：WP5 的 role/kind/breadth schema稳定后执行。

**测试**：decoder schema、generator determinism、alias policy、抽样 precision、distribution、runtime size。

**验收**：质量门禁全部通过；允许 entity/alias/term 总数下降；大陆真实消费覆盖改善；runtime <2 MiB。

**命令**：`dart tools/knowledge/generate_knowledge.dart`（或最终 validator 命令）；knowledge tests；recognition tests；`git diff -- assets/knowledge tools/knowledge` 人工审查。

### WP8 — Evaluation / Failure Analysis 统一

**修改**：`tools/evaluation/evaluate_recognition.dart`、报告 schema、`docs/PHASE3_BLIND_EVALUATION.md` 的后续结果链接（不覆盖 baseline）。

**新建**：`tools/evaluation/analyze_failures.dart`、共用 tool harness/fixtures（只放装配与 I/O）。

**删除/迁移**：删除 runner 内 status/issue 推断、Drift Category 构造、直接 Parser 调用。

**接口**：corpus + production Recognizer → versioned JSON report → failure JSON/Markdown summary。

**依赖**：WP1–7。

**测试**：metric math、percentile、小样本零分母、display/span 分类、safe rejection、report reproducibility。

**验收**：全部规定指标与版本/hash 输出；App 与 runner 的同输入/同 context 结果 deep-equal。

**命令**：evaluation tool tests；运行 190-case regression；运行 analyzer；`flutter analyze`。

### WP9 — App 接入与旧代码清理

**修改**：`app/providers.dart`、`recognition_coordinator.dart`、`recognition_repository.dart`、`transaction_editor_page.dart`、widget tests。

**新建**：`recognition_result_mapper.dart`。

**删除**：`text_entry_parser.dart`、旧 `FieldAwareExtractor` 残余、`ngram_classifier.dart` 空接口、`toTransactionDraft`、`textEntryParserProvider` 和所有直接 Parser 调用。

**接口**：UI → Coordinator → RecognitionInput → production Recognizer → result mapper → editor；保存成功 → Coordinator feedback。

**依赖**：WP1–8 全部完成后才能删除旧入口。

**测试**：Provider/Coordinator、partial result 回填、用户修改后反馈、保存成功但反馈失败、Candidate 不直接写库、Widget 识别/确认流。

**验收**：`rg "TextEntryParser|FieldAwareExtractor|DisabledNgramClassifier" lib test tools` 无旧调用（允许 migration commit 中临时存在，最终必须为零）；App 只有唯一生产内核。

**命令**：`dart format .`；`flutter analyze`；`flutter test`。没有原生插件变更，不运行 Android build。

### WP10 — Regression、Benchmark 与文档收尾

**修改**：benchmark 路径/实现、recognition 文档、architecture、development、TODO、CHANGELOG、必要 README 链接。

**新建**：版本化 after-refactor evaluation report；benchmark report 可只输出 CI log，不必提交易波动结果，除非文档要求固定环境基线。

**删除/迁移**：删除旧 `tools/benchmark_recognition.dart` 路径和重复 fixture。

**依赖**：WP9。

**测试/验收**：全量 format/analyze/test、190-case evaluation、failure analysis、benchmark；检查 diff 无生成垃圾/密钥/绝对路径；更新所有事实文档。

**命令**：

```bash
dart format .
flutter analyze
flutter test
flutter test tools/benchmark/benchmark_recognition.dart
# evaluation 命令以 WP8 最终 CLI 为准，并显式传 corpus/report
git diff --check
```

不涉及 Android plugin/Manifest/Gradle/OCR/文件系统平台集成，因此默认不运行 `flutter run`。

## 8. 阶段验收、停止点与 n-gram 决策

第一阶段（WP1–WP10 完成）的正式门槛：

| 指标 | 门槛 |
|---|---:|
| P0 | >= 95% |
| P1 | >= 80% |
| P2 safe rejection | >= 95% |
| type | >= 95% |
| category | >= 85% |
| amount | >= 97% |
| time | >= 97% |
| high-confidence wrong | 0 |
| warm recognition p95 | < 5 ms |
| runtime knowledge | < 2 MiB |

达到上述目标并冻结新 regression 后，才尝试 P0 约 100%、P1 >=90%。不能通过放宽 complete、降低安全拒绝或把错误降成“格式不一致”来达标。

**强制停止点**：结构性修改、知识质量重构和统一 evaluation 完成后，如果 P1 仍明显 `<75%`：

```text
停止继续堆确定性规则
→ analyze_failures 按失败族、证据缺口和置信区间复盘
→ 检查是 corpus/标签、span、知识分布还是表示能力上限
→ 形成独立 ADR/实验计划
→ 再决定是否进入 Character n-gram
```

只有人工确认进入 n-gram 后才重新创建真实 classifier 接口、训练/验证 split、模型资产格式、包体/延迟门禁和 fusion ceiling。不得恢复当前空接口作为“已支持”。n-gram 也必须作为同一个 `LocalRecognizer` 内部 evidence source，不能成为第二套识别器。

## 9. 最终顺序 Checklist

### 基线与边界

- [ ] 确认分支、工作区和本文审计基线差异，保护用户未提交修改。
- [ ] 固定并备份首次 190-case report，不覆盖 `phase3_blind_initial.json`。
- [ ] 建立纯 Dart `RecognitionInput` / `RecognitionResult` / structured issue 边界。
- [ ] 建立纯 Dart `RecognitionCategory`，移除 domain 对 Drift `Category` 的引用。
- [ ] 建立唯一 `Recognizer` 与 production `LocalRecognizer`。
- [ ] 将 JSON decode/index build 移到共用 `KnowledgeDecoder`。
- [ ] 让 AssetBundle、CLI File、test string 只充当输入 adapter。
- [ ] 增加 domain import boundary 和 production contract tests。

### Span 与字段

- [ ] 将 Normalization 拆为 raw/display/matching/index 四轨并维护 offset mapping。
- [ ] 定义半开区间 span、overlap/containment 规则和测试。
- [ ] 将 content 清洗改为 span selection，移除三套 replace helper。
- [ ] 新增 merchant/product/action/service content candidate tests。
- [ ] 新增 display formatting mismatch 与 content span error 的独立断言。
- [ ] 将 NaturalTimeParser 改为候选 span 输出。
- [ ] 覆盖 absolute/relative/daypart/clock 与多业务日期优先级。
- [ ] 建立 protected numeric spans。
- [ ] 建立 AmountCandidate feature scoring 与 ambiguity gate。
- [ ] 覆盖标题、型号、车次、订单号、手机号、数量、口语金额和 OCR 多金额。
- [ ] 建立 transaction block/status detector 和多交易拒绝。

### Type、知识匹配与融合

- [ ] 建立独立 `TypeEvidence` / `TypeInference`。
- [ ] 删除 `_incomeWords`、`_forcedType`、semantic-prefix-only type 逻辑。
- [ ] 验证未知 category 的明确 expense 仍有 type。
- [ ] 拆出 `EntityMatcher` 与 `LexiconMatcher`。
- [ ] 引入受控 entity kind、evidence role、specificity、breadth。
- [ ] 实现 specific product/action/service > broad entity/platform。
- [ ] 将 merchant default semantic 限制为 fallback 并加 confidence ceiling。
- [ ] 对同 span/同 family evidence 去相关。
- [ ] 保留 Personal History 最高优先，但加入净支持/纠正/冲突 gate。
- [ ] 重构 Fusion 为结构化 category decision。
- [ ] 分离 amount/type/category/time/overall confidence。
- [ ] 实现 conflict/fuzzy/platform/broad-only confidence ceilings。
- [ ] 建立 calibration buckets，确保 high-confidence wrong=0。

### Knowledge quality

- [ ] 生成现有 entity 按 source/kind/semantic/breadth/alias risk 的审计报告。
- [ ] 审计 1600 条 media/game title 的消费价值和 alias 风险。
- [ ] 删除或降权无关、高歧义、宽泛实体，允许总数下降。
- [ ] 补充经审核的中国大陆日常商户与服务覆盖。
- [ ] 为 alias 增加 exactOnly/substringAllowed/fuzzyAllowed policy。
- [ ] 将 merchant/platform/service/media/game/product brand 写成受控 kind。
- [ ] 将 product/action/service/merchantType/venue/platform 写成受控 role。
- [ ] 标注 broad/specific，并允许实体无默认 semantic。
- [ ] 删除 taxonomy 自动伪词形扩张。
- [ ] 用真实语言重做 lexicon，并补 negative/conflict terms。
- [ ] 建立固定 seed 的分层抽样 review manifest。
- [ ] 将 unresolved conflicts、抽样 precision、分布和 review status 加入硬门禁。
- [ ] 保留 runtime knowledge <2 MiB 与 deterministic generation。

### Evaluation 与唯一生产调用

- [ ] 重构 `evaluate_recognition.dart`，只调用 production `LocalRecognizer`。
- [ ] 删除 runner 自定义 status/issue 推断。
- [ ] 增加 P0/P1/P2 safe rejection 和各字段指标。
- [ ] 增加 display formatting mismatch / content span error 独立指标。
- [ ] 增加 average/p50/p95/p99/max latency。
- [ ] 增加 confidence bucket、coverage 和 high-confidence wrong 清单。
- [ ] 新建 `analyze_failures.dart` 并测试指标聚合。
- [ ] 将 benchmark 移到 `tools/benchmark/` 并共享 production harness。
- [ ] 分开测 hot recognize 和 cold knowledge decode。
- [ ] 加入 App/runner 同输入同 context deep-equal contract test。

### App 迁移与清理

- [ ] 将 Coordinator 改为组装纯 domain input 并调用唯一 Recognizer。
- [ ] 将 Candidate→editor/ledger draft 映射移出 domain/UI 重复逻辑。
- [ ] 将 feedback 的 normalization/semantic/clock 决策移出 Drift Repository。
- [ ] 让 partial Candidate 的可靠字段可安全回填并保持用户可编辑。
- [ ] 覆盖保存成功、反馈失败、用户改分类和重复识别的 Widget/application tests。
- [ ] 删除 `TextEntryParser` 及其 Provider/全部调用。
- [ ] 删除旧巨型 `FieldAwareExtractor` 残余逻辑。
- [ ] 删除 `RecognitionCandidate.toTransactionDraft()`。
- [ ] 删除空 `NgramClassifier` / `DisabledNgramClassifier`。
- [ ] 用 `rg` 确认不存在第二套 Parser、status、issue 或 content helper。

### 最终门禁与文档

- [ ] 运行 knowledge generation/validation 并人工 review 生成 diff。
- [ ] 运行 recognition unit/contract/integration/widget tests。
- [ ] 运行 190-case regression 并生成版本化 report。
- [ ] 运行 failure analyzer，确认失败分布不是 case-specific patch。
- [ ] 运行 benchmark，确认 p95 <5 ms 并记录 p50/p99/max。
- [ ] 确认 P0/P1/P2、field accuracy、high-confidence wrong 和 asset size 门槛。
- [ ] 若 P1 <75%，执行停止点并产出 n-gram 决策，不继续堆规则。
- [ ] 若第一阶段达标，再规划 P0≈100%、P1>=90% 的独立迭代。
- [ ] 更新 `RECOGNITION.md`、`RECOGNITION_ALGORITHM.md`、`ARCHITECTURE.md`、`DEVELOPMENT.md`。
- [ ] 更新 `TODO.md` 与 `CHANGELOG.md` Unreleased；必要时更新 README。
- [ ] 运行 `dart format .`、`flutter analyze`、`flutter test` 和最终 `git diff --check`。
- [ ] 检查 diff 无无关文件、密钥、机器绝对路径或未说明 TBD。

后续执行入口：**阅读本文，从 WP1 的第一项开始；每完成一个 WP，先满足该 WP 的测试与验收，再勾选 Checklist，禁止跳到知识调参或 n-gram。**

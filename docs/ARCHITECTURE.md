# 架构约定

V0.1 采用轻量、按 feature 组织的架构。目标是隔离 UI、业务规则、持久化和平台能力，而不是形式化套用复杂 Clean Architecture。

## 推荐目录

```text
lib/
├── app/                 # 应用入口、主题、路由、全局 Provider
├── core/                # 跨 feature 的小型通用能力
├── data/                # 数据库与共享数据基础设施
└── features/
    ├── ledger/          # 账本列表、搜索、筛选、编辑、删除
    ├── entry/           # 手动与文字录入
    ├── recognition/     # OCR、解析、规则和候选结果
    ├── statistics/      # 聚合与图表
    └── settings/        # 分类、账户、导入导出与设置
```

feature 内仅在复杂度需要时使用：

```text
presentation/
domain/
data/
```

禁止为追求目录形式创建大量空 interface、单实现 wrapper 或无业务价值的转发层。

Phase 1 的实际实现保持该边界：`data/database` 保存 Drift schema、连接和 seed，`features/ledger` 保存账本模型、Repository 与列表，`features/entry` 保存手动录入 UI，`app/providers.dart` 负责数据库和 Repository 的 Riverpod 装配。Widget 不直接执行 Drift query。发生时间的 UTC instant 与固定 offset 墙上时间转换集中在 `core/occurrence_time.dart`，避免 UI 使用当前设备时区解释历史账目。

Phase 2 在 `features/recognition/domain` 中实现无 UI、无数据库写入能力的确定性解析器和 Candidate 模型。主界面唯一的“记一笔”入口由 `EntryPage` 直接打开共用 `TransactionEditorPage`：用户点击“识别”后才生成 Candidate；完整结果显示在输入框下方并同步填入手动表单。结果卡的“确认入账”和表单底部“保存”都调用同一个验证/保存方法，生成带 `source = text` 和 confidence 的 `TransactionDraft`，再由既有 `LedgerRepository` 写库。解析器接收 Repository 暴露的数据库分类列表，不在 UI 中硬编码分类 ID。

Phase 3 大修新增轻量 `RecognitionCoordinator`：文字录入和未来 OCR 都通过它按规范化 key 查询 `RecognitionRepository`、构造纯 Dart `RecognitionInput`、调用唯一生产 `LocalRecognizer`，并在最终保存后记录反馈。`TransactionEditorPage` 不再负责全量历史加载或识别编排，只把可靠的 partial 字段回填到可编辑表单。`domain/` 的字段/span、Normalization、实体/词典匹配、TypeInference、Fusion、CategoryResolver 和结果模型不依赖 Flutter、Riverpod、Drift、AssetBundle 或 `dart:io`；外围 `data/application` 负责资产、持久化和 ledger 映射。

分类与账户选择 UI 分别从数据库 `Category.iconAsset`、`Account.iconAsset` 读取 SVG，不按名称维护 Widget 映射。分类使用嵌入表单滚动区的紧凑纵向网格，不创建内部横向滚动区；一级分类默认展示，点击后展开或收起其二级分类。账户使用五项图标网格点选。日期选择和可循环的 24 小时时间滚轮只修改本地墙上时间；UTC instant 与发生时 offset 的转换仍由 `OccurrenceTime` 和 Repository 负责。

Phase 3 在 `features/recognition` 内实现本地混合识别器。`domain` 保存唯一 `LocalRecognizer`、字段/span、自然时间、Personal History、知识模型、Evidence Fusion、`CategoryResolver` 与 Candidate，以及纯Dart `NgramClassifier` / `NgramModel`；`data` 负责共用 JSON decoder、AssetBundle adapter 和历史 Repository；`application` 负责 Coordinator 与 ledger 映射。Provider从AssetBundle加载紧凑int8资产并注入识别器，训练工具独立位于tools/ngram。模型仅由同一EvidenceFusion作为有门禁的弱fallback，不建第二条pipeline。旧 Parser、空接口已删除。OCR 作为独立平台输入顺延到 Phase 4，识别文字后仍进入同一个 `LocalRecognizer`。

首页本月概览由纯领域计算 `MonthlyOverview.fromEntries` 从当前账本流派生，按每笔账保存的 offset 还原所属本地月份，合计普通 `income` / `expense`、排除转账，并依据关联原账类型冲减退款。它不引入统计模块、图表或预算持久化；预算区域当前仅是“未设置”占位。

账目列表由 `LedgerDayGroup` 按每笔账的固定 offset 墙上日期分组并计算每日收支。列表行显示二级分类 SVG。单条删除由编辑器调用 Repository；长按多选使用 `softDeleteMany` / `restoreMany` 批量处理，二者均为 soft delete 并提供撤销。

## 数据流

正常手动记账：

```text
UI
→ ViewModel/Controller
→ Repository
→ Drift
```

智能记账：

```text
Raw Input / OCR Text
→ raw/display/matching normalization
→ status/time/protected numeric spans/amount/content
→ Personal History / Merchant KB / Category Lexicon / future n-gram
→ independent TypeInference + Evidence Fusion
→ semanticKey
→ CategoryResolver
→ RecognitionCandidate
→ Confirm
→ Repository
→ Transaction
```

关键不变量：

```text
OCR != Transaction
LLM != Transaction
Parser != Transaction
```

任何识别系统都只能提出 Candidate。Phase 3 仍要求用户确认；高置信自动确认尚未启用，必须等更完整的离线校准、提示和撤销闭环完成后再评估。

## 核心模型职责

- `EntryDraft`：用户尚未提交的结构化输入，允许字段缺失。
- `RecognitionCandidate`：识别系统的候选结果，包含字段证据、冲突和 confidence，不是正式账目。
- `Transaction`：经过用户确认或自动确认策略后写入账本的正式记录。
- `RecognitionRule`：以规范化内容和稳定 `semanticKey` 保存的本地确认/修改统计。

分类的数据库 ID 只由 `CategoryResolver` 在流水线末端解析。系统分类带 `semanticKey/isSystem`；未来用户分类可映射到同一语义，解析器和静态知识资产不依赖用户可见分类 ID。

模型字段以 [DATABASE.md](DATABASE.md) 为准；识别语义以 [RECOGNITION.md](RECOGNITION.md) 为准。

`Transaction.amountMinor` 始终为正整数，方向由 `type` 决定。转账通过来源/目标账户表达且不计入收支统计；退款保留原账目关联，由领域统计逻辑按退款语义处理。时间持久化统一遵循 `DATABASE.md` 的 UTC epoch milliseconds 与发生时 UTC offset 约定。

## Repository 边界

业务层不得散落 Drift query。账目、分类、账户和识别规则的读写通过职责明确的 Repository 进入持久化层。

```text
Business Logic
→ Repository contract
→ Local Repository
→ Drift / SQLite
```

边界应允许 Future 增加 Cloud Repository，但 V0.1 不实现远端 repository、同步协调器或网络层。不要为尚不存在的远端能力过度抽象。

## 平台能力隔离

Android 插件能力通过接口隔离，例如：

```text
OcrService
├── MlKitOcrService
└── MockOcrService
```

同样的边界可用于文件选择、文件导出和分享接收。业务规则只依赖抽象输入/输出；插件对象、Android Context 和平台路径不得渗入业务层。OCR 测试使用 Mock，不依赖模拟器或真实图片识别。

## 状态管理

统一使用 Riverpod。Provider 负责依赖装配和 UI 状态暴露，核心解析、规则、去重和统计逻辑保持为可独立测试的 Dart 代码。

不得混用 Provider、Bloc、GetX、MobX 等其他状态管理体系。

## 数据与隐私边界

- V0.1 仅使用本地 Drift + SQLite，不上传消费数据。
- 金额以整数最小货币单位持久化。
- 分类为可维护的一级/二级数据，不硬编码在 UI。
- 原始支付截图仅用于当次识别，默认不持久化。
- V0.1 不引入 analytics、telemetry、Web Search 或 LLM。

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
Raw Input
→ EntryDraft
→ Parser/OCR
→ RuleEngine
→ RecognitionCandidate
→ Confidence
→ Confirm/Auto-confirm
→ Repository
→ Transaction
```

关键不变量：

```text
OCR != Transaction
LLM != Transaction
Parser != Transaction
```

任何识别系统都只能提出 Candidate。低置信度必须确认；高置信度可按策略自动确认并写入，但必须提示且可撤销。

## 核心模型职责

- `EntryDraft`：用户尚未提交的结构化输入，允许字段缺失。
- `RecognitionCandidate`：识别系统的候选结果，包含字段证据、冲突和 confidence，不是正式账目。
- `Transaction`：经过用户确认或自动确认策略后写入账本的正式记录。
- `RecognitionRule`：从本地历史确认/修改中形成的可解释规则。

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

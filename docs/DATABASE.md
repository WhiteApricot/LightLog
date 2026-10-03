# 数据模型

本文定义 V0.1 的概念 schema，不要求当前阶段生成 Drift 表代码。SQLite + Drift 是锁定方案；字段类型、索引和约束在实现前按最小需求最终确认。

## 通用约定

- 主键建议使用 UUID；具体 UUID 生成实现为 TBD。
- 金额统一使用整数最小货币单位。CNY 的 `amountMinor` 单位为“分”，禁止用浮点数持久化金额。
- V0.1 默认 `currency = CNY`。
- 时间输入与展示使用设备本地时区。
- 时间持久化策略为 **TBD**：编码前在“UTC 持久化 + 本地展示”或明确时区约定的 epoch 方案中确定一种，并全库统一。
- 类型枚举值在写入后应保持稳定；重命名必须考虑迁移和导入兼容。

## transactions

正式账目表建议字段：

| 字段 | 含义 |
| --- | --- |
| `id` | UUID 主键 |
| `type` | `expense` / `income` / `transfer` / `refund` |
| `categoryId` | 一级分类 ID |
| `subcategoryId` | 二级分类 ID |
| `content` | 内容或规范化商户名 |
| `note` | 可选备注 |
| `amountMinor` | 整数最小货币单位；CNY 为分 |
| `currency` | V0.1 默认 `CNY` |
| `occurredAt` | 账目发生时间 |
| `accountId` | 账户/支付方式 ID |
| `source` | `manual` / `text` / `image` / `import` |
| `confidence` | 自动识别置信度；手动录入可为空或使用明确约定 |
| `fingerprint` | 重复检测指纹 |
| `createdAt` | 创建时间 |
| `updatedAt` | 最后更新时间 |
| `deletedAt` | 非空表示软删除 |
| `syncVersion` | 未来同步兼容字段；V0.1 不实现同步 |

`categoryId` 与 `subcategoryId` 应保持一级/二级关系一致。删除账目只设置 `deletedAt`，查询默认排除软删除数据，并支持撤销。

订单号/交易号需要支持重复检测，但其最终存储方式（独立字段或受控的来源元数据）为 **TBD**，实现 OCR 前确定，避免将不透明 JSON 变成核心查询依赖。

## categories

| 字段 | 含义 |
| --- | --- |
| `id` | 主键 |
| `parentId` | 父分类 ID；`null` 表示一级分类 |
| `name` | 分类名称 |
| `type` | 适用账务类型 |
| `sortOrder` | 展示顺序 |
| `isActive` | 是否可用于新账目 |
| `createdAt` | 创建时间 |
| `updatedAt` | 最后更新时间 |

V0.1 仅支持一级与二级分类，不创建更深层级。分类必须是可维护数据，不得硬编码到 UI。已有历史账目引用的分类不得物理删除，优先设置 `isActive = false`。

## accounts

| 字段 | 含义 |
| --- | --- |
| `id` | 主键 |
| `name` | 展示名称 |
| `type` | 微信、支付宝、银行卡、现金、其他等稳定类型 |
| `isActive` | 是否可用于新账目 |
| `sortOrder` | 展示顺序 |
| `createdAt` | 创建时间 |
| `updatedAt` | 最后更新时间 |

V0.1 只表示支付方式，不管理余额。被历史账目引用的账户优先停用而非删除。

## recognition_rules

该表应能表达可解释的本地学习规则，但不要在 V0.1 初期锁死为复杂规则 DSL。建议概念字段：

| 字段 | 含义 |
| --- | --- |
| `id` | 主键 |
| `pattern` | 原始/规范化文本匹配模式 |
| `merchantPattern` | 商户匹配模式，可选 |
| `amountMinMinor` / `amountMaxMinor` | 可选金额区间，单位为分 |
| `timeRange` | 可选时间区间；具体表示为 TBD |
| `categoryId` | 目标一级分类 |
| `subcategoryId` | 目标二级分类 |
| `normalizedContent` | 推荐的规范化内容/商户名 |
| `hitCount` | 命中次数 |
| `correctionCount` | 被用户纠正次数 |
| `confidence` | 当前可解释评分 |
| `createdAt` / `updatedAt` | 时间戳 |

规则必须保留足够证据以支持置信度调整；不能仅因命中过一次就永久自动入账。

## recognition_events（推荐）

建议记录系统原始预测、用户确认、用户修改、最终结果、来源和时间，用于本地评估规则准确率及更新 `recognition_rules`。具体保存完整字段快照还是结构化差异为 **TBD**。

该表不得保存原始支付截图，也不得用于 analytics 或 telemetry；V0.1 数据仍仅在本机。

## 索引与约束

实现阶段至少评估：

- `transactions.occurredAt`、`deletedAt`、`type`、分类字段的查询索引。
- 订单号/交易号及 `fingerprint` 的重复检测索引。
- 分类父子关系、账务类型和账户引用的完整性约束。

具体索引组合根据实际查询确定，当前为 **TBD**，不提前做复杂优化。

## Migration 规范

- SQLite schema 由 Drift 管理，schema version 与 migration 必须显式维护。
- 每次 schema 修改必须同步更新本文和 JSON `schemaVersion` 兼容策略。
- 禁止无 migration 的破坏式 schema 修改。
- migration 必须测试既有数据升级，不得以清库作为正式升级方案。
- 尚未决定的细节使用 `TBD`，在编码前完成最小必要决策。

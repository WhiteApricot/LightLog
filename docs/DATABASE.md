# 数据模型

本文定义 V0.1 的概念 schema 和已经落地的数据库约束。SQLite + Drift 是锁定方案；当前实现的 schema version 为 `3`。

## 通用约定

- 账目主键使用 UUID v4；默认分类和账户使用稳定、可读的固定 ID，以支持幂等 seed。
- 金额统一使用整数最小货币单位。CNY 的 `amountMinor` 单位为“分”，必须始终为正整数；账务方向由 `type` 决定，禁止用正负金额表达方向，也禁止用浮点数持久化金额。
- V0.1 默认 `currency = CNY`。
- 新建账目的时间输入使用设备本地时区，并支持到分钟。
- `occurredAt` 使用 UTC epoch milliseconds；同时保存 `timezoneOffsetMinutes`，记录交易发生时设备相对 UTC 的分钟偏移。展示和编辑历史账目时必须以 `occurredAt + timezoneOffsetMinutes` 还原发生时当地墙上时间，不得调用当前设备 `.toLocal()`；编辑已有账目时保留原始 offset。
- `createdAt`、`updatedAt`、`deletedAt` 使用 UTC epoch milliseconds；`deletedAt = null` 表示未删除。
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
| `amountMinor` | 正整数最小货币单位；CNY 为分，方向由 `type` 决定 |
| `currency` | V0.1 默认 `CNY` |
| `occurredAt` | 账目发生时间，UTC epoch milliseconds |
| `timezoneOffsetMinutes` | 发生时设备相对 UTC 的分钟偏移 |
| `accountId` | 账户/支付方式 ID；转账时为转出账户 |
| `destinationAccountId` | 可空；转账时为转入账户 ID |
| `relatedTransactionId` | 可空；退款或其他关联场景指向原账目 ID |
| `source` | `manual` / `text` / `image` / `import` |
| `confidence` | 自动识别置信度；手动录入可为空或使用明确约定 |
| `fingerprint` | 重复检测指纹 |
| `createdAt` | 创建时间，UTC epoch milliseconds |
| `updatedAt` | 最后更新时间，UTC epoch milliseconds |
| `deletedAt` | 可空；删除时间，UTC epoch milliseconds，非空表示软删除 |
| `syncVersion` | 未来同步兼容字段；V0.1 不实现同步 |

`categoryId` 与 `subcategoryId` 应保持一级/二级关系一致。删除账目只设置 `deletedAt`，查询默认排除软删除数据，并支持撤销。

- `transfer` 必须通过 `accountId` 和 `destinationAccountId` 表达转出/转入账户，两个账户不得相同；转账不计入收入、支出或净收支统计。
- `refund` 必须通过 `relatedTransactionId` 保留与原账目的关联。退款金额仍保存为正整数，后续统计依据退款类型及原账目语义冲减对应收入或支出，不把退款机械当作普通收入或支出。
- `destinationAccountId` 和 `relatedTransactionId` 在表结构上可空，因为非转账、非关联账目不需要它们；对应类型的必填关系由数据库约束或 Repository 写入校验保证。

订单号/交易号需要支持重复检测，但其最终存储方式（独立字段或受控的来源元数据）为 **TBD**，实现 OCR 前确定，避免将不透明 JSON 变成核心查询依赖。

## categories

| 字段 | 含义 |
| --- | --- |
| `id` | 主键 |
| `parentId` | 父分类 ID；`null` 表示一级分类 |
| `name` | 分类名称 |
| `type` | 适用账务类型 |
| `iconAsset` | 稳定关联的分类 SVG 资源路径 |
| `sortOrder` | 展示顺序 |
| `isActive` | 是否可用于新账目 |
| `createdAt` | 创建时间 |
| `updatedAt` | 最后更新时间 |

V0.1 仅支持一级与二级分类，不创建更深层级。分类必须是可维护数据，不得硬编码到 UI。`iconAsset` 作为分类数据随 seed/migration 维护，Widget 不按分类名称推断图标。schema v3 默认包含 23 个一级分类和 118 个二级分类，覆盖 17 个支出一级分类与 6 个收入一级分类；每个默认分类使用按稳定 ID 命名且图形签名不同的 24×24 SVG。已有历史账目引用的分类不得物理删除，优先设置 `isActive = false`。

## accounts

| 字段 | 含义 |
| --- | --- |
| `id` | 主键 |
| `name` | 展示名称 |
| `type` | 微信、支付宝、银行卡、现金、其他等稳定类型 |
| `iconAsset` | 稳定关联的账户 SVG 资源路径 |
| `isActive` | 是否可用于新账目 |
| `sortOrder` | 展示顺序 |
| `createdAt` | 创建时间 |
| `updatedAt` | 最后更新时间 |

V0.1 只表示支付方式，不管理余额。账户图标随 seed/migration 维护，UI 直接读取 `iconAsset`，不按账户名称推断资源。被历史账目引用的账户优先停用而非删除。

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

- `transactions.occurredAt`、`deletedAt`、`type`、分类字段的查询索引；统计查询优先评估 `(type, occurredAt)` 组合索引。
- `accountId`、`destinationAccountId` 与 `relatedTransactionId` 的关联查询索引。
- 订单号/交易号及 `fingerprint` 的重复检测索引。
- 分类父子关系、账务类型、原账目和账户引用的完整性约束。
- `amountMinor > 0`、`timezoneOffsetMinutes` 位于 `-840..840`、转账账户不相同，以及 `transfer`/`refund` 所需关联字段的条件约束。

schema v1 已为 `transactions.occurredAt`、`deletedAt`、`(type, occurredAt)` 和 `fingerprint` 建立索引。其他关联索引在相应查询落地并确认瓶颈后再增加，不提前做复杂优化。

## Migration 规范

- SQLite schema 由 Drift 管理，schema version 与 migration 必须显式维护。
- 每次 schema 修改必须同步更新本文和 JSON `schemaVersion` 兼容策略。
- 禁止无 migration 的破坏式 schema 修改。
- migration 必须测试既有数据升级，不得以清库作为正式升级方案。
- 尚未决定的细节使用 `TBD`，在编码前完成最小必要决策。

schema v1 通过 Drift `MigrationStrategy` 显式创建全部表。schema v2 为分类增加带安全默认值的 `iconAsset`，迁移分类名称并停用重复旧分类。schema v3 为账户增加 `iconAsset`，并将全部默认分类与账户迁移到按稳定 ID 命名的新 SVG；历史账目和默认数据 ID 不变。数据库打开且建表/迁移完成后继续执行幂等 seed。v1→v3 migration 由隔离数据库测试覆盖；未来 JSON 备份实现必须以 schema version 3 为当前写出版本，并为旧版本定义显式兼容路径。

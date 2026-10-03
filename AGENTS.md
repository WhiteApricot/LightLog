# AGENTS.md

本文件规定 AI agent 和开发人员在本仓库中的长期工作方式。它只保存跨版本有效的工程约束；具体版本的需求、任务和完成状态必须维护在 `docs/` 中，不在此重复。

## 1. 项目身份

- 中文名：轻记
- package/project：`light_log`
- GitHub repository：`WhiteApricot/LightLog`
- 产品方向：Android 优先、local-first、单机单用户智能记账 App
- 主要语言：简体中文
- 默认货币：CNY / ¥
- 时间输入与展示：设备本地时区；持久化策略以 `docs/DATABASE.md` 为准
- Android 目标适配下限：API 26

API 26 是业务开发和测试的兼容性下限，Android 工程固定 `minSdk = 26`。新增实现只保证 API 26 及以上行为正确；使用更高 API 能力时必须提供适当兼容处理。

## 2. 文档是需求与设计的事实来源

开始任务前，根据任务范围阅读以下文档：

- `docs/REQUIREMENTS.md`：当前版本的正式需求、范围和隐私约束
- `docs/ARCHITECTURE.md`：目录、数据流、边界和状态管理约定
- `docs/DATABASE.md`：概念 schema、字段语义和 migration 规则
- `docs/RECOGNITION.md`：文字/OCR 识别、置信度与学习规则
- `docs/DEVELOPMENT.md`：环境、命令、测试和协作流程
- `docs/TODO.md`：当前版本任务队列和进度
- `docs/CHANGELOG.md`：已完成的重要变更
- `README.md`：仓库入口与文档导航

版本范围或任务发生变化时，更新对应 `docs/` 文件；只有跨版本的工作规则发生变化时才更新本文件。若代码、任务描述和文档冲突，应先指出冲突并确认事实来源，不得静默选择一种解释。

## 3. 锁定技术方向

- Flutter 3.47.6
- Dart 3.13.5
- Material 3
- Riverpod
- Drift + SQLite
- Google ML Kit Text Recognition
- fl_chart
- Android-first；保留 iOS 工程结构，但当前 Windows 环境不构建 iOS

除非任务明确授权并说明迁移理由，不得更换状态管理、数据库、OCR 或图表方案，不得升级 Flutter、Dart、AGP、Gradle、Kotlin 或 NDK。

## 4. 每个开发任务的标准流程

### 4.1 开始前

1. 阅读本文件及与任务直接相关的 `docs/*.md`。
2. 检查 `git status`、当前分支和相关文件，识别用户已有的未提交修改。
3. 阅读相关现有代码和测试，不凭目录名或旧文档猜测实现状态。
4. 对照 `docs/REQUIREMENTS.md` 和 `docs/TODO.md` 确认任务属于当前版本。
5. 给出或形成最小可行实现方案；发现未决定事项时使用 `TBD` 或请求确认，不自行扩大范围。

### 4.2 实现中

1. 只修改实现任务所必需的文件，保留无关已有改动。
2. 优先扩展现有结构，禁止无理由整体重写、大规模重构或删除可用功能。
3. 核心业务逻辑与 UI、插件和持久化细节分离，并可进行 unit test。
4. 数据访问通过 Repository；业务层不得散落 Drift query。
5. 状态管理统一使用 Riverpod，不混入 Provider、Bloc、GetX、MobX 等体系。
6. Android 特有能力通过抽象接口隔离，业务层不得直接依赖 Android Context、插件对象或本机路径。
7. 错误必须显式处理；不得静默吞错、伪造成功结果或用不安全默认值掩盖失败。
8. 避免为假设中的未来需求创建空接口、无意义 wrapper 或过度抽象。

### 4.3 完成前

1. 检查 diff，确认没有无关文件、生成物、密钥、本机路径或意外格式化。
2. 执行与风险匹配的格式化、静态分析和测试。
3. 更新因本次实现而变化的需求、架构、数据库或识别文档。
4. 更新 `docs/TODO.md` 的完成状态；重要功能或行为变更写入 `docs/CHANGELOG.md` 的 `Unreleased`。
5. 总结改动、验证结果、已知限制和仍待处理的 `TBD`。

## 5. 代码维护规则

- 遵循 `analysis_options.yaml`；不得遗留 analyzer error 或无合理解释的 warning。
- 面向用户的默认文案使用简体中文；代码标识符使用清晰英文。
- 保持函数、类型和模块职责单一，优先可读性和可测试性，不追求形式化分层。
- 公共行为变更必须同步修改调用方、测试和相关文档。
- 修复 bug 时应先稳定复现，尽可能加入回归测试，再做最小修复。
- 不得通过删除断言、跳过测试、放宽关键校验或清空数据来“修复”问题。
- 删除或弃用代码前确认无调用方、无数据兼容影响，并清理对应测试和文档。
- 性能优化必须基于明确瓶颈，不能以牺牲正确性、可读性或数据安全为代价。

## 6. 核心数据与识别安全规则

- 持久化金额禁止使用 `double`，统一使用正整数最小货币单位；人民币使用“分”，账务方向由 `type` 决定。
- 交易发生时间保存为 UTC epoch milliseconds，并记录发生时设备 UTC offset；审计时间保存为 UTC epoch milliseconds。完整约定以 `docs/DATABASE.md` 为准。
- 分类是可维护的一级/二级数据，不得硬编码到 UI 逻辑。
- 账目删除采用 soft delete；不得无迁移地破坏历史数据。
- OCR、Parser、规则引擎及未来识别能力只能生成 `RecognitionCandidate`，不得直接构造并静默写入正式 `Transaction`。
- 低置信度或冲突结果必须确认；高置信度自动入账必须提示并可撤销。
- 默认不保存原始支付截图，不编造 OCR 未识别出的字段。
- 所有消费数据默认仅保存在本机；不得擅自加入上传、analytics、telemetry、Web Search、LLM 或云服务。

更完整规则以 `docs/DATABASE.md` 和 `docs/RECOGNITION.md` 为准。

## 7. 数据库与兼容性维护

- Drift schema version 和 migration 必须显式管理。
- 修改 schema 时同步更新 `docs/DATABASE.md`、migration 测试及 JSON 备份的 `schemaVersion` 兼容策略。
- 禁止无 migration 的破坏式 schema 修改，禁止把清库作为正式升级方案。
- 已持久化的枚举值、字段语义和导入导出格式应保持向后兼容；必须破坏兼容时先制定迁移方案。
- 被历史账目引用的分类或账户优先停用，不做物理删除。
- 涉及时间、金额、重复检测或统计口径的变更必须增加边界测试。

## 8. 依赖与构建配置

新增第三方 package 前必须确认：

1. Dart/Flutter 标准库或现有依赖无法合理完成。
2. 依赖符合当前版本范围，体积、权限和维护成本合理。
3. Android API 26 及以上兼容，并不会引入与 local-first/隐私原则冲突的网络或数据收集行为。
4. 已说明引入原因，并更新必要文档。

不得无理由修改：

- Maven 或 Flutter 国内镜像
- Android SDK 路径及其他本机绝对路径
- package/application ID
- 签名、release keystore 或密钥文件
- Flutter、Dart、AGP、Gradle、Kotlin、NDK 版本

构建配置变更必须有明确任务依据，并进行相应 Android 验证。

## 9. 测试与验证

普通 Dart/Flutter 改动默认执行：

```bash
dart format .
flutter analyze
flutter test
```

只有涉及 Android plugin、Manifest、Gradle、OCR、文件系统或其他原生能力时，才额外执行：

```bash
flutter run
```

不得为了普通小改动反复执行耗时的完整 Android build。若受环境限制无法完成某项验证，必须明确说明未执行项和原因，不得声称验证通过。

测试重点与分层策略见 `docs/DEVELOPMENT.md`。测试不得依赖真实网络、用户本机绝对路径或不可控系统时间；OCR 业务逻辑使用 Mock。

## 10. 文档维护要求

以下变化必须在同一任务中更新文档：

- 产品范围、验收标准或明确排除项变化：更新 `docs/REQUIREMENTS.md`。
- 模块边界、数据流、目录或状态管理变化：更新 `docs/ARCHITECTURE.md`。
- 表、字段、约束、索引或 migration 变化：更新 `docs/DATABASE.md`。
- Parser、OCR、规则、confidence 或学习策略变化：更新 `docs/RECOGNITION.md`。
- 环境、命令、编码或测试流程变化：更新 `docs/DEVELOPMENT.md`。
- 当前任务进度变化：更新 `docs/TODO.md`。
- 完成重要功能、修复或兼容性变化：更新 `docs/CHANGELOG.md` 的 `Unreleased`。
- 仓库入口、平台状态或文档导航变化：更新 `README.md`。

不要在多个文件复制大段同一内容；确定一个事实来源，其他文件使用链接或简短摘要。不得在 Changelog 中虚构尚未实现的功能。

## 11. Git 规则

- 开始和结束任务时检查 `git status`，不得覆盖、回滚或混入用户的无关改动。
- 使用短生命周期 feature branch；`main` 应尽量始终保持可运行。
- 提交应聚焦一个逻辑变更，包含对应测试和必要文档，不提交构建产物、本机配置、SDK 路径、密钥或临时文件。
- 使用简化 Conventional Commits：

```text
feat:
fix:
refactor:
test:
docs:
chore:
```

- commit 前检查 staged diff；push 前确认分支、远端和提交内容。
- 未经明确要求不得 commit、push、merge、rebase、创建 tag 或发布 release。
- 禁止使用会丢失工作区内容的命令，例如无明确授权的 `git reset --hard` 或强制覆盖。
- 合并冲突必须理解双方意图后逐项解决，不得整侧覆盖。

## 12. 版本与后期维护流程

具体版本任务只维护在 `docs/REQUIREMENTS.md` 和 `docs/TODO.md`，本文件仅规定通用流程：

1. 开始版本：冻结范围、记录排除项、拆分阶段任务并确认 schema/兼容性影响。
2. 开发期间：按任务实现、测试并持续维护 `Unreleased`，不提前实现 Future 功能。
3. 版本收尾：完成回归、migration/备份恢复、隐私、API 26 设备兼容性和关键失败路径检查。
4. 发布准备：清空阻塞性 TBD，确认版本号、Changelog、签名和发布配置；签名与发布操作必须单独获得授权。
5. 发布后：保留可追溯 tag/Changelog；修复从可复现问题开始，并评估旧数据和旧备份兼容性。

依赖升级和平台升级应作为独立维护任务处理：先阅读 release notes，评估破坏性变化，最小范围升级，并完成全量静态分析、测试与必要的 Android 运行验证。

## 13. 完成定义

任务只有同时满足以下条件才可报告完成：

- 实现符合当前 `docs/REQUIREMENTS.md`，且没有扩大范围。
- 代码遵守架构、数据、隐私和 API 26 兼容性约束。
- 必要测试已添加并通过，或明确记录无法执行的验证。
- 相关文档、TODO 和 Changelog 已同步。
- diff 中没有无关改动、敏感信息或本机绝对路径。
- 剩余风险、限制和 TBD 已明确列出。

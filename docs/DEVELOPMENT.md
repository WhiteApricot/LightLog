# 开发规范

## 本地环境

当前已验证的主要开发环境：

```text
Flutter 3.47.6 stable
Dart 3.13.5
Android SDK 36
Gradle 9.3.1
Pixel 8 Emulator
Windows 11
VS Code
```

项目 Android 优先，最低支持 Android API 26。保留 iOS 工程结构，但当前 Windows 环境不构建 iOS。不得在文档、脚本或受版本控制配置中写入用户电脑的绝对 SDK 路径。

Phase 1 已安装 Riverpod、Drift/SQLite 与 UUID 依赖，以及 Drift 代码生成开发依赖。分类图标使用 `flutter_svg` 渲染轻量矢量资源；Flutter SDK 本身不提供 SVG 解码，因此采用该单一、维护活跃的专用依赖，不引入图片缓存、网络或遥测能力。Google ML Kit Text Recognition 和 fl_chart 仍按对应阶段确认后再添加，不得在无对应功能时提前引入。

## 常用命令

```bash
flutter pub get
dart run build_runner build
dart format .
flutter analyze
flutter test
flutter run
```

普通 Dart/Flutter 改动完成后执行 format、analyze、test。只有涉及 Android plugin、Manifest、Gradle、OCR 或文件系统等原生能力时才执行 `flutter run`；不要为普通小改动反复执行完整 Android build。

## 编码规范

- 遵循 `analysis_options.yaml`，提交前消除 analyzer error 和无合理解释的 warning。
- 使用简体中文编写面向用户的默认文案；代码标识符使用清晰英文。
- 核心业务逻辑独立于 Widget 和插件 API，优先使用小型、可测试的纯 Dart 类型与函数。
- 状态管理统一使用 Riverpod，不混入其他体系。
- 数据访问通过 Repository，业务层不散落 Drift query。
- 平台能力通过接口隔离，业务层不依赖 Android Context、插件对象或本机路径。
- 持久化金额使用正整数 `amountMinor`，方向由账务类型决定；展示层才负责格式化为元。
- 交易发生时间使用 UTC epoch milliseconds，并同时保存发生时设备 UTC offset；审计时间统一使用 UTC epoch milliseconds。
- 历史账目展示和编辑必须使用持久化的 UTC offset 还原发生时墙上时间，编辑时保留原 offset；不得用当前设备 `.toLocal()` 重新解释。
- 转账与退款统计规则必须通过领域逻辑实现并覆盖测试，不得依赖金额正负号推断。
- Parser、OCR 和 RuleEngine 只能产出 `RecognitionCandidate`，不能直接写正式账目。
- 分类为可维护的一级/二级数据，不硬编码到 UI。

## 测试策略

unit test 优先覆盖：

- 金额解析
- 时间解析
- 文本解析
- RuleEngine
- Confidence
- DuplicateDetector
- 统计计算
- 转账排除与退款冲减语义
- UTC 时间、设备 offset 与本地日期边界
- 真实临时 SQLite 文件关闭、重开后的持久化
- JSON/CSV 导入导出

OCR 使用 Mock 测试字段提取之后的业务逻辑，少量真实设备/模拟器测试用于验证插件集成。Repository 和 migration 应使用隔离数据库测试。Widget test 只覆盖关键交互，不替代业务 unit test。

修复 bug 时应尽可能先补充或同步加入能复现问题的测试。不得依赖真实网络、用户本机绝对路径或不稳定时间；时间相关逻辑应可注入测试时钟。

## Git 工作流

`main` 必须尽量始终保持可运行。完整 feature、Phase 或跨多个模块的变更使用短生命周期分支并通过 PR 合并；范围明确、风险低的小修或纯文档修订可在获得授权后直接提交到 `main`。一次提交聚焦一个逻辑变更，不夹带格式化无关文件、生成物或本机配置。

### 开工检查

每次任务开始先获取远端引用并确认工作区、当前分支以及相对 `main` 的 ahead/behind：

```bash
git status --short --branch
git branch --show-current
git fetch origin --prune
git rev-list --left-right --count origin/main...HEAD
```

`git rev-list` 输出依次为当前分支相对 `origin/main` 的 behind 和 ahead。发现未提交修改时先确认归属，不得覆盖或混入无关改动。

开始新 Phase 前必须从最新 `main` 创建新分支：

```bash
git switch main
git pull --ff-only origin main
git switch -c feat/phase-N-short-name
```

只使用 `--ff-only` 同步 `main`，避免拉取时隐式生成 merge commit。不得使用 force push；未经明确授权不得 rebase、reset、强制覆盖或改写共享历史。

### Feature branch 与 PR

完成实现、测试和文档后：

```bash
git diff --check
git status --short
git add <本任务文件>
git diff --cached --check
git diff --cached --stat
git commit -m "feat: concise description"
git push -u origin feat/phase-N-short-name
```

随后通过 GitHub UI、GitHub CLI、已连接的 GitHub 工具或官方 GitHub API 创建 `feature branch -> main` 的 PR。PR 正文应概述行为变化和验证命令；不得在脚本、日志或仓库中暴露访问令牌。

合并前必须 review PR diff，而不能只看提交信息：

```bash
git fetch origin --prune
git diff --stat origin/main...HEAD
git diff --name-status origin/main...HEAD
git rev-list --left-right --count origin/main...HEAD
```

确认变更文件均在任务范围内、没有敏感信息或构建产物、分支不落后于 `main`，并在 GitHub 上确认 PR 可合并且无冲突。完整 feature 默认使用 squash merge，使 `main` 保留一个聚焦提交；不得绕过失败的检查。

### 合并后清理

PR 合并后验证远端 `main` 指向 merge commit，再删除已经完成且不再使用的开发分支：

```bash
git switch main
git pull --ff-only origin main
git branch -d feat/phase-N-short-name
git push origin --delete feat/phase-N-short-name
git status --short --branch
```

只删除已经确认合并且不再使用的分支；不得删除 `main`。若分支未被 Git 识别为已合并（例如 squash merge），应先通过 PR 状态和远端提交确认，不得用 `-D` 绕过检查，除非另有明确授权。

## Commit

使用简化 Conventional Commits：

```text
feat:
fix:
refactor:
test:
docs:
chore:
```

示例：`docs: define V0.1 recognition pipeline`。未获明确要求时不要自动 commit、push、merge 或创建 release。

## 新任务流程

```text
1. 阅读 AGENTS.md、需求/架构文档
2. fetch 并检查工作区、当前分支及相对 main 的 ahead/behind
3. 新 Phase 从最新 main 创建 feature branch
4. 给出符合当前范围的最小实现方案
5. 编码，保留无关已有改动
6. 更新 TODO、必要设计文档和 CHANGELOG 的 Unreleased
7. 执行 dart format、flutter analyze、flutter test；原生改动再运行应用
8. review diff 后按授权 commit/push/PR；合并后清理完成分支
9. 总结改动、验证结果、TBD 和剩余问题
```

## 依赖与构建配置

新增 package 前确认标准库或现有依赖不能合理完成、维护状态和体积可接受、且功能属于 V0.1。不得无理由升级 Flutter、Dart、AGP、Gradle、Kotlin、NDK，或修改 Maven/Flutter 国内镜像、Android SDK 路径及 package/application ID。

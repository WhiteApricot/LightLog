# 轻记（light_log）

“轻记”是一个 Android 优先、local-first、单机单用户的智能记账应用。项目当前处于 **V0.1 MVP 开发中**，目标是让常见账目在数秒内完成录入。

## 当前状态

- 平台：Android 优先；保留 iOS 工程结构，但当前 Windows 环境不构建 iOS。
- 技术栈：Flutter 3.47.6、Dart 3.13.5、Material 3、Riverpod、Drift + SQLite、Google ML Kit Text Recognition、fl_chart。
- Phase 1 手动记账基础闭环已实现：本地 Drift 数据库、默认分类/账户、响应式账本、手动新增/编辑以及软删除撤销。
- Phase 2 已实现统一手动/文字入口、确定性文字记账候选、可解释 confidence、分类图标选择、本月概览和确认后入账；重复检测仍待定义阈值。
- OCR、规则学习、统计和导入导出仍按后续阶段推进。

## 文档

- [V0.1 需求基线](docs/REQUIREMENTS.md)
- [架构约定](docs/ARCHITECTURE.md)
- [数据模型](docs/DATABASE.md)
- [智能识别设计](docs/RECOGNITION.md)
- [文字识别算法工作文档](docs/RECOGNITION_ALGORITHM.md)
- [开发规范](docs/DEVELOPMENT.md)
- [变更记录](docs/CHANGELOG.md)
- [任务队列](docs/TODO.md)

AI 编程代理还必须先阅读 [AGENTS.md](AGENTS.md)。

## 开发环境

- Flutter 3.47.6 stable
- Dart 3.13.5
- Android SDK 36，最低支持 Android API 26
- Windows 11 + Pixel 8 Emulator 为当前主要开发环境

不要在仓库中写入本机 SDK 绝对路径。详细环境与工作流见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。

## 基本命令

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

仅在涉及 Android 插件、Manifest、Gradle、OCR 或文件系统等原生能力时运行 `flutter run`。

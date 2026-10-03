# 轻记（light_log）

“轻记”是一个 Android 优先、local-first、单机单用户的智能记账应用。项目当前处于 **V0.1 MVP 开发中**，目标是让常见账目在数秒内完成录入。

## 当前状态

- 平台：Android 优先；保留 iOS 工程结构，但当前 Windows 环境不构建 iOS。
- 技术栈：Flutter 3.47.6、Dart 3.13.5、Material 3、Riverpod、Drift + SQLite、Google ML Kit Text Recognition、fl_chart。
- 当前仓库仍是 Flutter 默认工程；业务依赖与业务功能尚未实现。

## 文档

- [V0.1 需求基线](docs/REQUIREMENTS.md)
- [架构约定](docs/ARCHITECTURE.md)
- [数据模型](docs/DATABASE.md)
- [智能识别设计](docs/RECOGNITION.md)
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

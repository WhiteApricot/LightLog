# 最终本地统计语义工具（96 类）

唯一production：NgramModel/NgramClassifier、assets/knowledge/ngram.bin，纯Dart、local-only。共享字符2–3 sparse vocabulary与非循环已有语义evidence；一个资产包含Direction、Parent、Child和masked PreparedMeal heads。详细合同与结果见 [算法文档](../../docs/RECOGNITION_ALGORITHM.md)。旧A/B/C报告不覆盖，实验实现仅archive。

训练只来自data既有38,539 train/4,832 dev；禁止新训练文本及holdout补训练。final_dataset_migration.json记录96覆盖、dedup/conflict/leakage和SHA256。final_oracle_seal.json记录七套oracle迁移hash；v7封存后直到production freeze不得读取、搜索或分析。原用户v7不改写。

在独立checkout使用固定requirements.txt，不升级依赖：

```text
dart tools/knowledge/generate_knowledge.dart
dart tools/ngram/export_pipeline.dart
python tools/ngram/train_final.py
python tools/ngram/select_final.py
python tools/ngram/reference.py
dart tools/ngram/evaluate.dart
dart format .
flutter analyze
flutter test
git diff --check
dart tools/benchmark/benchmark_recognition.dart
python tools/ngram/final_acceptance.py freeze
python tools/ngram/final_acceptance.py regression
python tools/ngram/final_acceptance.py v7
```

train_final/select_final输出命名不可覆盖；新实验使用新目录/名字。选择基于完整production dev Category，再Parent，再更小模型；所有F1/F2/F3路径已比较。每parent仅一组child threshold/margin；弱child保留父类top child并warning。Direction不使用type/default direction features，class balancing与阈值只用train/dev。PreparedMeal只用food子集，先mask餐段和时刻，precision≥97%；head on/off完整dev消融决定是否保留。参考解码与Dart验证全部4832dev的各类/辅助概率，1e-10，保持无特征拒识。

final96保存选型、parity、latency、freeze和最终不可覆盖验收报告；archive/104-final保存原104状态。冻结后的历史regression与v7不得用于重调；若失败只分析并保留dev选定生产。host warm指标不能当API26实机结果。未实现OCR、云服务或第二套分类器。

最终结果：Dev C/P/T=90.91/94.18/97.60%，false other=.52%、Meal=100%；v7 C/P/T=79.38/88.25/94.75%，false other=2.50%、Meal=79.41%，P2=80/80、高置信错误0、普通有效null0。另有6个P0/P1退款关联漏检。**Phase 3 NOT CLOSED**，禁止再按v7调参。完整统计与Top confusion见 final96/failure_analysis.md，机器可读综合结果见 final96/final_summary.json。

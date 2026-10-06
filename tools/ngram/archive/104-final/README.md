# 本地层级统计分类工具

当前生产只有 `NgramClassifier` / `NgramModel` 的 **hierarchical-lr** 后端和 `assets/knowledge/ngram.bin`。A flat routing与C pooled production implementation已经移除。名称ngram保留，共享字符特征仍是主体；训练/分析完全位于本目录，不依赖App中的Python或native ML。

本轮按A→B→C执行；A完整dev category=76.26%，B=78.79%，C=79.45%。C相对B+0.66pp未达+2pp并有历史回退，按规定选择B；不能以模型自身85.43%替代完整流水线准确率。具体指标、分解和限制见 `selection_summary.json`、`stage_*_dev.json`、`stages/*/summary.json` 与 [算法文档](../../docs/RECOGNITION_ALGORITHM.md)。v7仅最终冻结后首次运行，结果不参与训练/阈值选择。

## 冻结数据与一致性

仅使用 `data/ngram_training_corpus_v2.jsonl`、`ngram_train_v2.jsonl`、`ngram_dev_v2.jsonl` 和审核报告，train=38,539/dev=4,832，104类。既有splitGroup划分不变、交集为零；hash见 `stage_b_training.json`。不生成、补充或重标训练样本，不加入任何holdout。

`train.py`仅保存load/normalize contract；Dart `NgramClassifier.normalize`使用同样的ASCII/fullwidth/CJK规则和2048 codepoint截断。模型是binary sparse ngram presence。`export_pipeline.dart`调用真实LocalRecognizer（禁用模型）导出deterministic permission、type和既有evidence特征；不复制parser。无金额文本仅补固定37以便生产门禁可评估，原始semantic/type标签不变；这属于dev诊断输入合同，不是新训练样本。生成的train/dev pipeline JSONL不提交，重现时重新导出。`taxonomy.json`是seed关系的生成产物；模型metadata和active-category映射均不手写。

## 重现（独立checkout，勿覆盖已封存结果）

离线环境安装 `requirements.txt` 的固定numpy/scipy/sklearn。Stage C实验额外使用已存在的PyTorch 2.5.1；CPU、seed=17，非生产依赖，未升级依赖。

```bash
dart tools/ngram/export_pipeline.dart
python tools/ngram/train_hierarchical.py
python tools/ngram/reference.py
dart tools/ngram/evaluate.dart
dart tools/ngram/evaluate_pipeline.dart experiment
```

B训练比较8192/16384、C=0.5/2.0、text-only/既有structured features。dev category优先，提升≤0.3pp选择较小候选。选出16384+1056、C=2.0；Parent LR + 多子类parent-specific LR，单子类无头。int8每类scale；二类log-odds对称展开。对同一稀疏特征集合只提取一次。

`select_routing.py`仅用于train/dev模型选择；Stage A冻结posterior实验已归档，禁止在曝光的历史报告上重调。路由选择最大完整dev模拟category accuracy，统计接受准确率≥90%，同分取覆盖率。模拟与真实production gate有差异（默认type须parent≥0.85才校正），最终事实来源是 `stage_*_pipeline_dev.json`，不用模拟分数宣称产品效果。

`reference.py`独立解码导出int8参数，不重新拟合；parity vectors比较全部104概率，evaluate.dart对全量4832 dev检查top label/probability。`train_pooled.py`只导出实验候选到tools，32/64维char/structured embedding mean pooling + parent/child heads；完整pure Dart候选仅存在于 `archive/pooled/candidate.dart`，用于机制审查后的dev对照和parity；不进入lib、providers或App assets。`train_meal.py`仅分析已有餐段标签作为prepared-meal proxy；在现有安全边界下无完整pipeline增益，不集成、不覆盖生产资产。

## 资产与权限

LLNG v2 JSON metadata + feature-major int8 heads，shared vocabulary、21父类、104 children及parentByChild。Dart只接受最终v2 LR格式，不保留v1/v3 production decoder。只保留一份App资产：2,384,289 bytes，全部runtime知识资产合计2,784,671 bytes。

EvidenceFusion统一Level0强证据保护、Level1同父重排、Level2弱语义层级路由；无法得到合法分类则复用other.general warning。B参数parent≥0.25、parent margin≥0、conditional child≥0.55、child margin≥0.05；同父也要求parent mass≥0.25。只有强统计parent≥0.85和弱默认type才允许既有reconcile校正，confidence≤0.69；强方向与退款安全始终优先。

## 回归和冻结

```bash
python tools/ngram/regress_stage.py <new-stage-name>
dart tools/benchmark/benchmark_recognition.dart
dart format .
flutter analyze
flutter test
git diff --check
```

regress_stage.py先记录生产hash，再跑original190/v2/v3/v4/v5/v6，不读取v7；封存报告不覆盖。历史P2 safe=100%，高置信错误=0；v6没有P2，不能把其runner输出0解释为安全失败。warm完整dev p50/p95/p99=0.463/0.935/1.193ms，host测量，不是API26设备结果。

旧flat训练及原始报告移至 `archive/flat`，旧regression目录保留历史；stage报告与hash供审计。历史分数、模型独立dev、完整pipeline dev和最终独立blind的含义必须区分。C硬停止后若验收未达门槛，记录Phase3未收口；不能继续加模型或扩大数据。

初始训练export hash保留于stage_b_training.json；A2机制审查后的最终header/asset hash见stage_b_audit.json、selection_summary.json及final_freeze.json，learned weight payload完全相同。首次v7调用仅schema validation，无预测；13个red_packet命名转换需要确认后才在评估副本应用。

各阶段完整report以json.gz无损归档，原始JSON字节SHA256与gzip hash在stages/report_index.json；summary.json可直接阅读。解码示例：`json.loads(gzip.decompress(Path(report).read_bytes()))`，压缩未改变任何报告字节或指标。

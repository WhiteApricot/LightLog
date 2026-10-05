# 离线字符分类器

生产 App 只打包 `assets/knowledge/ngram.bin`，通过唯一 `LocalRecognizer` 使用纯 Dart `NgramClassifier`；Python、numpy、scipy、sklearn 只用于离线训练，不是 App 依赖。

四份用户提供的 v2 文件原样归档在 `data/`。train=38,539、dev=4,832、corpus=43,371，104类；训练检查 splitGroup 不交叉。review report 保留 provenance、逐条审核与数据限制。保留 corpus/train/dev 的重复内容是为了来源可追溯，没有把 corpus 重新混入训练。

从仓库根目录复现（本轮Python 3.12.3；依赖版本见 requirements.txt）：

```powershell
python -m pip install -r tools/ngram/requirements.txt
$env:OPENBLAS_NUM_THREADS = '1'
python tools/ngram/train.py
dart tools/ngram/evaluate.dart
powershell -NoProfile -File tools/ngram/regression.ps1
```

训练只读取 train/dev；八组 multinomial Logistic Regression 用固定seed=17、SAGA、max_iter=180、tol=0.002，比较2–3/2–4 gram、8192/16384特征、C=0.5/2.0。最高 dev macro F1 胜出，平分保留首次配置；binary sparse feature、min_df=2、按频率限制显式 vocabulary。最终2–3 gram、16384特征、C=2.0。在量化后的概率上选择阈值：top-1/top-2 margin固定0.15；threshold候选0.45/0.60/0.75/0.85，在接受精度至少95%下选最大覆盖，最终0.60。未使用历史 holdout 选择任何配置。

完整 normalization/input 契约和安全融合见 [算法文档](../../docs/RECOGNITION_ALGORITHM.md)。训练与推理都直接使用原始全文，不依赖时间或字段提取。全量 dev label/probability 在 evaluate.dart 校验；parity_vectors.json 覆盖全部类别概率及空输入/全角/emoji，单元测试验证概率误差≤1e-10。零有效feature必须拒识，不能用bias猜类别。

资产格式：ASCII `LLNG` magic、uint32 little-endian UTF-8 JSON header长度、header（版本/normalization/gram范围/vocabulary/labels/bias/每类scale/threshold/margin）、feature-major int8权重。每类scale=max(abs(weight))/127；Dart先累加稀疏激活feature的int8权重，再乘scale加bias、softmax。loader显式拒绝版本、维度、有限值和长度错误；不引入复杂压缩格式。资产1,882,814 bytes（1.796 MiB），未量化的同维度float32矩阵本身约6.5MiB。

文件职责：train.py是唯一trainer/exporter；training_report.json记录选择、dev overall/macro/per-class指标、版本与SHA-256；dev_predictions.json供全量跨语言校验；runtime_report.json记录dev一致性与p50/p95/p99；freeze.json记录模型/生产代码冻结。regression/包含五套原始oracle的before/after完整评测；evaluation_summary.json合并指标；benchmark_report.json保留既有10000次warm benchmark。没有实验模型、临时代码或训练runtime依赖进入App。

freeze在本轮历史评测前建立，冻结后不得根据失败重训/调参。复现训练须在独立checkout比较产物hash，不覆盖既有冻结报告。冻结后仅修复评测工具的退役分类历史崩溃，并记录于freeze：只过滤已知退役history、未知ID报错，不重标oracle，不改模型/生产逻辑。旧corpus有已退役标签；before是当前104类pipeline关闭ngram，不能与旧taxonomy历史分数直接比较。

性能均为Windows host Dart VM warm结果，不是Android实机数据；API26设备性能仍待后期兼容性验证。严格弱fallback带来的历史分类收益有限；完整正餐优先级、无语义other.general fallback、OCR与进一步新盲测均不属于本任务。

本轮收尾验证：dart format . 无新增改动，flutter analyze 无问题，flutter test 105项通过，git diff --check通过；全量dev跨语言校验、五套前后regression和既有10000次benchmark均完成。freeze源码hash对应当时工作区字节，跨平台checkout须注意文本换行；二进制模型hash不受换行影响。

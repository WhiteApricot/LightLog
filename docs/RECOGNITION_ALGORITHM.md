# 本地语义识别算法（最终 96 类）

当前 taxonomy 与边界的唯一规范见 [REQUIREMENTS.md](REQUIREMENTS.md)。104 类算法、历史报告和初始源码保留在 [历史算法](archive/phase3/PHASE3_104_RECOGNITION_ALGORITHM.md) 与 tools/ngram/archive/104-final；历史分数不代表本轮验收。

## 唯一生产流水线

LocalRecognizer → field/status/time extraction → deterministic evidence → ONE NgramModel/NgramClassifier → semantic arbitration → prepared-meal routing → CategoryResolver → safety/confidence。没有新增 production classifier、tokenizer、native runtime 或网络。共享字符 2–3 gram sparse features 与既有 source/role/specificity/family/semantic/parent 证据；不使用 preliminary type/default direction 特征。训练导出和 runtime 调用同一 structuredFeatures，收集全部已有语义 evidence，不仅 winning evidence；普通知识不再 hard lock 父类。

单资产 LLNG v2 包含 int8 Parent LR、parent-specific Child LR、class-balanced Direction LR 和可选 masked PreparedMeal LR；单子类 parent 直接路由。各头共享 normalization/vocabulary，PreparedMeal 仅用同一特征提取函数对屏蔽餐段/时刻后的文本提取；无有效特征拒识，不用 bias 猜语义。模型 metadata 校验辅助头、维度、每父阈值及 finite 参数。

Direction 仅纠正 default/null/low-confidence type，明确方向和所有安全状态优先。TransactionStatusDetector 独立检测通用退款短语；退款分类可预填，但始终保持 refund 类型和 relatedTransactionRequired，不能作为普通收入提交。failed/cancelled/nontransaction/multi/amount missing 不被模型和 fallback 绕过。

TypeInference 的明确收入字段也识别“收益紧跟金额”的通用字段语法；金额 +/- 仍先处理，收益结算手续费等没有该收入字段结构的支付保持支出。该字段规则不是特定投资类别 veto，不进入 Direction/Parent/Child 训练特征。

## train/dev 与有界方案探索

仅 tools/ngram/data 的现有 38,539 train / 4,832 dev；保留 text、splitGroup、source、difficulty 和 pattern/provenance。标签按 taxonomy contract 迁移，exact/NFKC-whitespace normalized dedup、label conflict、group leakage 均为零，96/96 覆盖。未生成新训练文本、未用 holdout 补训练。初始模型和数据 SHA256 见 archive/104-final/baseline.json，迁移记录见 final_dataset_migration.json。

比较 8192/16384、C=.5/2、structured on/off；发现 winning-only evidence 丢失信息后改为所有已有证据；运动服鞋与器材混合知识列表按 term 分开，再完成必要重训。最终候选和逐次报告均保留，完整 dev Category 第一、Parent 第二、较小资产第三。

F0 为 96 类迁移后的原融合基线；F1 普通知识取消 veto，F2 使用有界 deterministic parent support，F3 statistical semantic primary。完整 dev 未达到提前停止条件时执行至 F3。每 parent 一组 child threshold/margin，只决定 warning 程度；弱 child 不抛弃 parent。配置与选型见 tools/ngram/final96/corrected/selection.json。最终统计输出 ceiling=.69，不能 confident auto-confirm。

PreparedMeal 只从 food train/dev 的现有餐段标签获得 positive，其余 food 为 negative；先 mask 时间/餐段再训练，precision≥97% 下最大 recall。显式非正餐 veto 优先；判断正餐后才调用统一 meal windows 和既有 NaturalTimeParser。完整 dev meal on/off 消融保留，不保留无实际增益的模块。

## 验证与 blind protocol

独立 Python int8 reference 与 Dart 对全部 dev 的语义、Direction、PreparedMeal 概率 parity（1e-10），另测无特征/全角/emoji。schema v4→v5 使用真实临时 SQLite 升级，检查 FK、软删除、金额/时间/offset、历史计数和活动默认类别唯一性。

v7 只做 naming/96-oracle contract migration 后 hash seal；封存到 freeze 不读取/搜索内容，不据预测改 oracle。全量 format/analyze/test/diff、taxonomy/dataset/migration/parity/benchmark 完成后记录 production/model/dataset/config SHA256。冻结后 original190/v2/v3/v4/v5/v6 只作 regression；最后 v7 immutable first-run，之后禁止模型、规则、阈值和训练数据修改。工程报告均为 Windows host warm Dart VM，API26 实机性能未验证。

最终不可覆盖报告、SHA256、check退出码和综合结果维护于 tools/ngram/final96。

补充静态审查见 [仲裁审查](../tools/ngram/final96/failure_analysis_review.md)：普通 deterministic veto 已解除，但弱 Direction 输出仍作为 Parent 类型 mask。34个v7弱方向错误受到该约束；未记录未过滤 Parent posterior，无法定量隔离潜在收益。主瓶颈包括语体/表示差异及该残余 fusion 限制。Meal未触发的2例也不能仅凭first-run报告断言为PreparedMeal Head低分。

## 最终冻结与验收结论（2026-10-06）

**Phase 3 NOT CLOSED**。全部强制阶段已执行；保留完整dev最优的F3，不按v7继续修改模型、规则、threshold或训练数据。未恢复Stage C，未增加synthetic/Transformer/LLM。v7原始报告SHA256：`2958ca2c1b4d6690558285918c4bc2a3e310961bb7f193e2d8b5b5e504af5d4c`。

| Set | Category | Parent | Type | false other.general | Meal |
|---|---:|---:|---:|---:|---:|
| Dev (4832) | 90.91% | 94.18% | 97.60% | 0.52% | 100.00% |
| original190 | 88.95% | 95.79% | 97.37% | 2.11% | 94.74% |
| v2 | 84.74% | 91.58% | 96.84% | 3.16% | 90.00% |
| v3 | 82.00% | 95.00% | 96.00% | 1.50% | 100.00% |
| v4 | 70.33% | 82.67% | 96.33% | 4.67% | 80.00% |
| v5 | 76.00% | 87.00% | 93.75% | 3.75% | 100.00% |
| v6 | 81.25% | 88.50% | 95.25% | 3.25% | 88.00% |
| v7 first-run (800) | 79.38% | 88.25% | 94.75% | 2.50% | 79.41% |

Dev门槛全部达到；v7 Category/Parent/Type/Meal 未达85/90/97/90%。v7 P2 safe=80/80，高置信错误=0，普通有效category=null=0。**另有6个P0/P1退款关联拒答漏检**，不能用P2 100%宣称全局安全。六套历史高置信错误均0，含P2的五套均100%；v6无P2，raw的0是空分母，解释为N/A。

Direction模型独立dev=99.96%，threshold=0.5，class balancing；完整type指标包括字段/status hard locks，不能用头指标代替pipeline。PreparedMeal precision=98.58%、recall=92.05%；完整dev on/off为100%/84.11%，保留该头。

模型=2,347,908 bytes (2.239 MiB)，共享同一normalization/vocabulary/extractor。121项test、analyze、format、diff、96 taxonomy/dataset/FK migration/parity通过。10,000次host warm p50/p95/p99=0.210/0.486/0.607ms；v7完整warm为0.453/1.064/1.501ms。API26实机未验证，不把host数字称为Android结果。

productionSourceSha256=`5851e66c20f16b7a5b61ae1d2d5be8aa780afe81083710fb1dd0625b5d8df1d0`；modelSha256=`40c84bac8f5fc0653beb2e595bc424c8219cc16e9a2523b4c00d48d73ce9de16`；configSha256=`4764e21bcdc2b8526ef21603fc7b2e9f694888c1e9135c7c1bd044b4fdc83428`。冻结后再次核对全部production/dataset/oracle字节未变。

失败分析见 [详细报告](../tools/ngram/final96/failure_analysis.md)：type42（income→expense36，refund→普通6），wrong parent94，同父错child71，false other20，meal7（检测2/时间解释5），跨priority safety6。主瓶颈是训练/dev的模板语体与真实省略表达的分布差异、sparse全文/无序evidence表示对action/actor/negation作用域的不足；其次是child用途边界、口语时间和隐式退款覆盖。taxonomy保持96，fusion取消普通veto已经完成。

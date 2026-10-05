# 本地语义识别算法

本文描述生产结构。当前实现见“分级统计兜底”，文末“Character n-gram 弱 fallback”为已取代历史版本，此前未实现状态、旧 taxonomy 分数与冻结记录保留为历史。隐私、Candidate 与确认边界见 [RECOGNITION.md](RECOGNITION.md)，数据字段见 [DATABASE.md](DATABASE.md)。

## 2026-10-06 分级统计兜底（当前生产）

按A→B→C顺序完成。只复用冻结train=38,539/dev=4,832，104类、splitGroup leakage=0；语料和标签未修改、未补充任何训练数据。v6仅在各阶段源码封存后回归，v7最终生产冻结前不读取。

| 完整生产dev | Category | Parent | Type | specific coverage | false fallback |
| --- | --- | --- | --- | --- | --- |
| A：冻结104-way posterior | 76.26% | 83.59% | 97.16% | 90.31% | 7.60% |
| B：Parent/conditional Child LR | 78.79% | 85.87% | 97.27% | 90.83% | 7.04% |
| C：32维subword平均池化 | 79.45% | 86.03% | 97.33% | 91.06% | 6.79% |

A低于85/88%的继续门槛，故进入B；B完整pipeline仍低于85%，故进入C。C比B仅提高0.66pp（未达+2pp），且original190明显回退，因此按既定规则回退B，停止模型层。B完整dev改善2.52pp，但仍未达门槛；保留B符合C拒绝后的指定回退规则，不是全局最优证明。

唯一LocalRecognizer → deterministic evidence → 唯一NgramClassifier（名称保留，backend=hierarchical-lr） → EvidenceFusion → TypeInference.reconcile → CategoryResolver → Candidate安全/确认。A的flat/top-1后端和C的embedding生产实现均已删除；仅训练实验与封存报告保留。App只加载一份ngram.bin。

Shared features只提取一次：binary char 2–3 gram 16,384 vocabulary + 1,056个既有production evidence特征（preliminary type、direction-default、winning evidence source/role/family/semantic parent）。21-way Parent LR及多子类parent-specific Child LR共用该集合；单子类parent不训练头。二类LR对称展开log-odds。所有头int8、每类scale、feature-major。训练metadata直接从seed生成，运行路由从活动分类关系生成，不维护第二份手写taxonomy。

EvidenceFusion.statisticalLevel统一权限：0=无冲突且可靠的具体/history/composition或明确正餐，保留；1=具体父类anchor或非冲突的具体/merchant/venue父类，只同父重排；2=只有general family/product或弱/缺失语义，父类再子类路由。统计拒答且无合法deterministic分类时，复用other.general warning兜底；存在可靠父类anchor时保留warning，不无条件抛弃parent。B在dev固定parent probability≥0.25、parent margin≥0、conditional child≥0.55、child margin≥0.05；同父路由也要求parent mass≥0.25。

统计Parent≥0.85且preliminary type是弱默认时才调用既有reconcile校正方向，type/category上限0.69。强方向、type conflict与refund status/semantics优先；统计退款语义不采用，未关联退款仍阻断。不改amount/time/status/content/确认/写库；模型不能独立提供餐段。

B模型独立dev Category=85.43%、Parent=93.85%，完整pipeline显著更低。受保护的deterministic错误、taxonomy/方向/餐段门禁共同限制收益，不能把独立模型分数当产品准确率。完整dev错误分解：false other=340、wrong parent=683、同父错child=342、wrong type=132、meal detection miss=24，类别/类型错误可重叠。taxonomy ambiguity未重新裁决，不编造计数。各阶段flat/hierarchical、接受率、同父/跨父、child conditional和failure分解见[selection summary](../tools/ngram/selection_summary.json)及stage_*_dev.json。

PreparedMeal仅用现有早餐/午餐/晚餐标签作为positive proxy；未改标签。dev precision=100%、recall=71.52%，overall=99.11%受类别不平衡影响，不代表正餐泛化达到目标。理论union recall=99.34%，但23个新增positive都落入受保护具体食材证据；不改变安全边界时完整dev无增益，故不集成生产头/模块。见[meal dev](../tools/ngram/meal_dev.json)。该目标需要独立审核prepared-food标注与deterministic边界；本次不擅自扩充/重标数据，也不把全部误差归咎于训练覆盖。

模型2,384,289 bytes（2.274MiB），全部五个runtime assets 2,784,671 bytes（2.656MiB）。host warm完整dev p50/p95/p99=0.463/0.935/1.193ms；10,000次benchmark=0.194/0.419/0.506ms。以上为Windows Dart VM，API26实机未验证。117项测试、analyze、104-label metadata与4,832条dev概率parity通过。六套历史高置信错误=0，历史P2 safe=100%；original190/v2=94.74/91.05%（原95.26/90.00%，无明显回退）。

收尾规范审查修正了general family/product被错误锁父的问题（A2要求其进入Level2），只在train/dev重新校准B/C阈值，未重训、改语料或读取任何v7预测；初始结果/旧freeze保留于archive/preflight和各阶段报告。此前v7调用在oracle命名校验即退出，无预测/指标；13个red_packet命名差异等待用户确认，仅评估副本规范化，原始语料不改。实验C的float32训练预览与double解码存在微小舍入差异，parity reference已按实际导出int8/scale独立解码修正，校验容差仍1e-10。

独立v7验收待最终冻结后填入。C为本任务硬停止点，无论结果如何不再调规则、阈值或加入更重模型。

## 唯一生产入口

App、evaluation、benchmark、generator review 与业务测试均调用 LocalRecognizer。domain 为纯 Dart，同步执行；历史、活动分类和本地时间由调用方注入。识别只产生 RecognitionCandidate，不写账。

流水线：Normalize → Entity/Lexicon/Family match → SpanConflictResolver → FieldExtractor 与 preliminary type → History/Context evidence → parent-first EvidenceFusion → TypeInference.reconcile → CategoryResolver → confidence 与安全门禁。

FamilyMatcher 合并原有两个 matcher 的职责：字符串只匹配一次，随后仅处理命中的 spans；同时产生 standalone prior 与组合 evidence。按首字符索引 term、按 left family 索引 rule，不扫描全部规则，也不对整个知识库做笛卡尔积。没有 old/new 双路径。

已删除独立 LexicalFamilyMatcher、CompositionalMatcher、concept-only suppression helper、未使用的 Recognizer interface。ContextEvidenceBuilder 不再重复显式餐食词典；TypeInference 不再维护收入来源与支出商品名词的另一套 routing。保留 amount/time/status、退款安全、history、merchant KB 与 CategoryResolver。

## Family schema 与默认语义

family source schema v2 包含 id、kind、terms、policy，以及可选的 prior（单个 semanticKey/score）。policy 为 standalone 或 contextualOnly；模型以 prior 是否存在表达同一约束，单个 family 不支持多个竞争默认值。requiresAdjacentFamily 只约束单字匹配；组合 allowOverlap 显式声明可嵌入的上下文关系，算法不再硬编码具体 family 对。

104 类迁移后为 193 families、2107 normalized unique terms、311 composition rules，没有新增词或规则。114 standalone / 79 contextual-only；prior 覆盖 73 children，composition 覆盖 87；联合覆盖 21 parents / 89 children。

仅稳定概念具有默认值；宽泛设备、动作、平台、人物等依然可以只有上下文能力。Prior score 按概念稳定性取 0.70–0.78，不能产生高置信自动确认。Composition 是更高优先级的精化或覆盖，明确商品/action/service lexicon 也高于弱 prior；prior 没有成为另一套全文商品词典。

## 非破坏性 span 处理

所有 concept matches 保留到语义处理阶段。概念长度本身不能删除 semantic evidence。SpanConflictResolver 只比较实际输出的正 semantic evidence；negative 或无 span evidence 保留。

更长完整概念已有 prior 时，可以替换其内部的假 substring；更长、同义且不更弱的 evidence 可以去重；不同语义需更高或相同 specificity/score 的实际替代 evidence。Composition 可覆盖其包含的默认值，但单纯 contextual-only concept 不会清空已有分类。

## Parent-first fusion

EvidenceFusion 是唯一融合实现。先按 semantic/family 去相关，每个 child 使用最强证据的 priority/score 和有限独立支持形成 anchor。当前两级 semantic taxonomy 的 parent 是 type.domain。Parent 以最强 child anchor 加有上限的独立支持聚合，避免子类数量或重复别名制造优势；选择 parent 后只在该 parent 内排名 children。Parent 竞争和 child 竞争分别参与 ambiguity/confidence 门禁。

优先级依次为有效 personal history、composition、specific product/action/service、specific entity、general product/action/service、family prior、merchant default、venue/context/platform。负面 evidence 降低对应输出 confidence；fuzzy、宽泛实体、平台、仅商户、仅 prior 和时间推断均有 confidence ceiling。没有新 ontology、hierarchy engine、embedding 或模型。

## 两阶段 type reconciliation

TypeInference.inferPreliminary 读取交易状态、显式金额正负号、入账/付款字段及动作；金额与内容只产生标记为 isDefault 的弱 expense。类别融合前不再按这个初步类型删除 semantic evidence。

TypeInference.reconcile 根据获胜语义修正弱默认或无强方向的类型。显式方向与强语义相反时保留方向并产生 typeConflict；退款状态不能被改回普通交易。income.refund.* 语义也恢复 refund 类型，并统一加入 relatedTransactionRequired，未关联原账目始终 blocked。

## 稳定字段与确认安全

Normalize 保留 raw/display/matching 视图。FieldExtractor 区分日期、订单号、数量、型号和金额；AmountCandidate 保留 role、feature、reason、score，并对接近的不同金额报告 ambiguity。NaturalTimeParser 使用注入的设备本地 now，明确交易日期优先于乘车/有效期等其他日期。

PersonalHistory 只按 normalized content 查询，净支持、纠正次数和最近使用共同限制分数。CategoryResolver 将稳定 semantic 映射到活动两级分类，不能伪造不存在的映射。

amount/type/category/time/content 分别计算 confidence。warning 保留 top-1 并要求人工确认；失败、取消、非交易、多交易、无合法金额和未关联退款保留 blocked 门禁。没有修改 OCR structured extraction。

## Generator quality gates

单一 compositionQuality 检查 id、归一化 term、跨 family 危险共享词、引用、taxonomy、距离、重复 pair/rule、prior policy/score、跨 type prior、两个稳定 object prior 的矛盾和 contextual orphan。只有明确 contextual operand 可以覆盖稳定 object 默认值。Prior 最大 0.79，composition 最小 0.80。

报告 standaloneFamilyCount、contextualFamilyCount、familiesWithSemanticPrior、priorSemanticCoverage、compositionSemanticCoverage、parentCoverage、childCoverage、orphanFamilies、unusedRules，以及 term/kind/rule/domain/conflict 分布。unusedRules 是结构有效性报告，不宣称 106 条 review samples 已覆盖全部 311 rules。family 的机械数量门槛已删除；原 lexicon/entity 质量门禁保留。当前无无效引用、taxonomy、重复 rule、危险共享冲突或 orphan；review 105/106。

四份 runtime 资产共同参与 knowledgeHash：merchants、category_lexicon、lexical_families、composition_rules。下文历史冻结所用 FNV-1a hash 为 288a37c0；此次四资产迁移后已变化，不能作为现行资产 fingerprint。

## 冻结与 blind protocol

设计、schema、代码、synthetic mechanism tests、原 190 regression 和 benchmark 完成前未读取任何 v2/v3/v4/v5 corpus。98 tests、analyze、format、generator、diff check 通过后记录 pre-holdout tree aebe9b65694f9c1bceb61c0c1c4d76f14ec72edd。四资产 SHA-256 与 frozenAt 保存在 [freeze](../tools/knowledge/review/phase3_semantic_routing_freeze.json)。旧 regression 完成且生产未变后再次记录 [v5 freeze](../tools/knowledge/review/phase3_semantic_routing_v5_freeze.json)。

v5 首次运行立即保存 [initial report](../tools/evaluation/phase3_semantic_routing_v5_initial.json) 和 [initial analysis](../tools/evaluation/phase3_semantic_routing_v5_initial_analysis.md)，工具拒绝覆盖。之后仅做一次通用退款 reconciliation/安全门禁修复；没有新增任何 term、family 或 composition rule。99 tests 与原 regression/benchmark 再次通过，final tree 68cf26d20640d9a9c91f8acd1fe69d037a4c7e6f，见 [final freeze](../tools/knowledge/review/phase3_semantic_routing_final_freeze.json)。[Final report](../tools/evaluation/phase3_semantic_routing_v5_final.json) 已保存，此后停止调 v5。

## 最终 evaluation

| Corpus | Category | Type | High-confidence wrong | P2 safe |
|---|---:|---:|---:|---:|
| 原 190 | 96.32% | 100% | 0 | 100% |
| v2 regression | 90.53% | 100% | 0 | 100% |
| v3 regression | 97.50% | 98% | 0 | 100% |
| v4 regression | 67.67% | 97.33% | 0 | 100% |
| v5 initial | 75.50% | 94.50% | 0 | 100% |
| v5 final | 75.50% | 96.50% | 0 | 100% |

v3 的最终 type 比修复前 99% 低 1pp：通用 refund 语义现在统一要求退款类型和关联门禁，旧 corpus 部分 income/refund oracle 存在差异；没有为旧 oracle 增加例外。

v5 为 400 cases，覆盖全部 118 child semantics；56 semantics 的分类全部正确。Parent accuracy 81.25%，child accuracy 75.50%。Initial/final category=null 均为 47，非空 wrong-category 均为 51。98 个 category failures 中：43 无 semantic output，另外 4 有 semantic 但无 category mapping，28 非空 parent 错，23 parent 对但 child 错。Type failures 22 → 14，与 category failures 可以重叠，不应相加。

P0/P1/P2 分类分别为 84.75%/71.43%/100%。全量 group、semantic、confidence/confirmation 和失败分布保留在 reports。Final warm evaluation p50/p95/p99 为 0.256/0.689/1.141 ms；10,000 次 benchmark 为 0.145/0.403/0.495 ms。

Recognition domain 20 → 19 文件，2900 → 2891 行；generator 728 → 643 行，重复 validation 合并到 compositionQuality，新增机制与 schema tests。候选与旧中间 knowledge review 归档；各次有历史价值的 blind initial/final 保留，根目录无测试 JSON。

Frozen source snapshots are reachable through commits 776afbb6bee24d8323f557f4448f20a3f8d0a0ee (pre-blind) and b3af88ec355140c15d86ab2d98a9ff5287720138 (single generic repair). Trees were recorded before evaluation; snapshot commits were materialized during archival.

## v5 final group category accuracy

| Group | Cases | Category | Parent | Type |
|---|---:|---:|---:|---:|
| fallback | 2 | 100.00% | 100.00% | 100.00% |
| family_pet_core | 30 | 86.67% | 86.67% | 93.33% |
| finance_core | 18 | 44.44% | 44.44% | 88.89% |
| hierarchy_digital | 4 | 50.00% | 100.00% | 100.00% |
| hierarchy_education | 2 | 100.00% | 100.00% | 100.00% |
| hierarchy_food | 4 | 75.00% | 100.00% | 100.00% |
| hierarchy_housing | 4 | 75.00% | 75.00% | 100.00% |
| hierarchy_medical | 4 | 100.00% | 100.00% | 100.00% |
| hierarchy_social | 2 | 50.00% | 50.00% | 50.00% |
| hierarchy_sports | 3 | 100.00% | 100.00% | 100.00% |
| hierarchy_subscription | 3 | 66.67% | 66.67% | 100.00% |
| hierarchy_transport | 4 | 25.00% | 25.00% | 100.00% |
| hierarchy_travel | 2 | 50.00% | 50.00% | 100.00% |
| income_core | 78 | 73.08% | 83.33% | 89.74% |
| semantic_core | 195 | 80.00% | 85.13% | 99.49% |
| span_routing | 6 | 100.00% | 100.00% | 100.00% |
| travel_social_core | 33 | 63.64% | 69.70% | 100.00% |
| type_reconcile | 6 | 66.67% | 66.67% | 100.00% |

## 决策与下一步

Phase 3 classification **未达到 freeze 条件**。v5 < 80%，结论为 **deterministic semantic routing insufficient**。不继续扩 family/composition，不继续调 v5。下一项独立算法工作应评估 character 2–4 gram + lightweight linear classifier / Naive Bayes 作为低置信 fallback evidence，保持相同 LocalRecognizer 和 safety gates；本轮未实现 n-gram。Phase 4 OCR structured extraction 仍单独维护，不能用 OCR 内容提取掩盖分类泛化不足。

## 104 类知识迁移契约

完整标签和正餐最高优先级原则见 [需求契约](REQUIREMENTS.md)。删除 takeout、全部 travel/family 支出及 lost/unexpected；按真实用途迁移已有词、实体、prior 和规则，收入差旅报销不变。无分类时的支出/收入 other.general fallback 及完整正餐时间优先级尚待独立 pipeline 任务，本次不调识别参数。后续 n-gram 只能使用 104 个标签，本轮未实现。

Generator 强制 secondLevelTaxonomyCount=104，所有知识输出必须引用合法二级语义，obsoleteRuntimeSemanticReferenceCount=0。逐项审核记录在 tools/knowledge/review/v01_taxonomy_migration.json（相对仓库根）；旧 semantic 仅作为历史审核来源，不参与 runtime generation。移除 36 条不稳定词条语义、4 个无输出的 contextual family 和 5 条无明确用途规则。

本文此前的 corpus 分数、freeze hash 和 blind 记录属于旧 taxonomy 历史结果，不是迁移后验收。本轮仅运行生成、格式化、分析、单元测试和 diff 检查，未读取或运行任何 holdout。

## Character n-gram 弱 fallback（2026-10-05）

本节取代此前“尚未实现 n-gram”的状态。唯一 LocalRecognizer 在确定性 Fusion 后有条件请求 NgramClassifier，EvidenceFusion.withWeakEvidence 决定是否采用；App Provider 从 AssetBundle 注入 NgramModel，CLI/evaluation 注入相同资产。Domain 仅依赖 Dart 标准库，无训练环境、native ML runtime、tokenizer、embedding、ONNX、Transformer 或网络。

train=38,539、dev=4,832、104类，splitGroup 不交叉。八组 Logistic Regression（multinomial SAGA、seed=17）比较2–3/2–4 gram、8192/16384特征、C=0.5/2.0，以量化后的dev macro F1选型。最终2–3 gram、16384显式vocabulary特征、binary sparse presence、C=2.0；4-gram未胜出。每类scale的int8 feature-major权重，softmax输出semanticKey scores；资产1,882,814 bytes（1.796 MiB），小于2MiB。配置、每类precision/recall/F1/support和hash见 [training report](../tools/ngram/archive/flat/training_report.json)。

训练与生产直接使用原始全文，共享ascii-cjk-space-v1规则：最多前2048 Unicode codepoints；全角ASCII转半角，ASCII A–Z转小写；保留a–z及U+3400–U+9FFF，其余变空格，合并空格并trim；不调用content/字段/时间解析。连续字符窗口，重复feature只计一次；模块支持2–4，最终资产选择2–3。无有效feature时scores全零且拒识，不能用bias猜类。全部4832条dev核对离线/Dart top-1 label/probability，容差1e-10；额外测试全部类别概率、空/数字/全角/emoji输入。

量化dev accuracy=83.2368%，macro recall/accuracy=84.1494%，macro F1=82.7556%。dev比较threshold=0.45/0.60/0.75/0.85，top-1/top-2 margin固定≥0.15，在accepted accuracy≥95%下选择最大覆盖，最终threshold=0.60（coverage=56.95%，accepted accuracy约97.46%）。模型概率不等于自动确认confidence。

只在无semantic，或deterministic confidence<0.70且winning evidence无priority≥80的specific/history/composition时请求弱证据。即使强证据margin小也保持确定性结果；该保守策略不解决所有ambiguity。推理还要求合法金额、普通success/unknown、非多交易、非退款。采用的模型类别必须匹配已确定type且不能是refund semantic。TypeInference始终读取原deterministic fusion，ngram不改变type/amount/content/time/status。弱evidence ceiling=0.69，保留ambiguity及全部危险门禁；取得新分类证据时仅替代categoryLowConfidence。模型单独永远不能confident/自动确认。

[freeze](../tools/ngram/archive/flat/freeze.json) 在本轮历史corpus评测前记录模型、配置及生产源码hash；之后未训练、调参或增加规则。唯一冻结后修复是评测工具对退役history的过滤并显式记录：原190的H003 takeout已不属于当前合法语义，处理与Repository一致。历史corpus oracle原样保留，没有重标任何失败case。before是当前104类pipeline仅关闭ngram；不能与旧taxonomy历史分数直接比较。

| Corpus | Category before → after | Type before → after | category=null before → after | High-confidence wrong | P2 safe |
|---|---:|---:|---:|---:|---:|
| 原190 | 94.21% → 94.21% | 100% → 100% | 12 → 12 | 0 | 100% |
| v2 | 89.47% → 89.47% | 100% → 100% | 19 → 19 | 0 | 100% |
| v3 | 84.00% → 84.00% | 98% → 98% | 5 → 5 | 0 | 100% |
| v4 | 62.67% → 64.33% | 97.33% → 97.33% | 55 → 49 | 0 | 100% |
| v5 | 67.75% → 69.00% | 96.50% → 96.50% | 54 → 48 | 0 | 100% |

本机Dart VM warm dev ngram p50/p95/p99=0.019/0.032/0.044ms，完整LocalRecognizer=0.521/1.119/1.390ms；既有10000次warm benchmark p95=0.517ms。完整指标与逐类/分组结果见 [summary](../tools/ngram/archive/flat/evaluation_summary.json)、[runtime report](../tools/ngram/archive/flat/runtime_report.json) 和regression目录。以上为host CPU，不宣称Android/API26实机性能。

模块已冻结，分类收益有限，整个Phase3泛化收口尚未达到历史阈值；不继续调历史holdout。完整正餐时间优先级、无语义other.general fallback、OCR和新未见corpus仍是独立任务。复现命令、数据归档、依赖与资产格式见 [训练工具](../tools/ngram/README.md)。

## 104-class oracle与产品规则冻结（2026-10-06）

本节取代上一轮fallback/正餐优先级“待实现”的状态。没有重训、改动n-gram input/weights/threshold/margin、扩充实体/词典/family/composition或调整其优先级。模型仍为char2–3、16384维Logistic Regression、int8、confidence ceiling=0.69；资产SHA256仍为`4e161509b937b9125cf66676bca0a2ae5d2c17d04390ef1af44e1f6f76c2a818`。

先单独审核旧oracle，逐条按实际食品/住宿/交通/娱乐/用品/教育/医疗/护理用途迁移退役分类，不使用识别预测；原190/v2/v3/v4/v5分别迁移6/3/28/26/48条，共111条，原始输入和所有合法标签以及type/status/amount/time/issues不变。H003的旧平台history改为无确定用途的other.general。原始文件及逐条理由在tools/evaluation/archive/legacy_taxonomy；新文件命名为*_104class.json。全部非空expected semantic和history引用通过104-class校验，SHA256与封存时刻见 [oracle freeze](../tools/evaluation/oracle_migration_freeze.json)。封存后到production freeze期间没有重新打开、搜索、解析或统计新corpus及审核明细；v6直到最终验收前保持未读。

other.general发生在deterministic、冻结ngram及活动分类映射均尝试后：普通expense/income、正合法金额、没有Candidate统一危险门禁、最终没有合法分类时，再由原CategoryResolver尝试`type.other.general`。若other.general本身停用/无父子映射则继续不完整，不伪造ID。实际兜底证据标记otherGeneralFallback、category confidence=0.55并保留warning/复核；不改变type/amount/time/content，不绕过失败、取消、非交易、多笔、缺金额或需关联退款。

ContextEvidenceBuilder复用已解析的当地发生时刻和现有食品正证据，识别明确正餐/熟食主食结构；不建立第二套pipeline，不修改知识数据。明确文本时刻由NaturalTimeParser优先提取，否则使用occurredAtLocal；只有日期不算显式餐段。集中时窗：早餐[05:00,10:00)，午餐[10:00,17:00)，晚餐[17:00,次日05:00)，无空档。EvidenceFusion.withMealEvidence仅在食品用途内让明确正餐与时刻优先于其他food subtype，非食品目的保持原融合。饮品/零食/食材、外卖渠道本身不能产生正餐路由；保留原有“餐饮商户+显式交易时刻”的弱上下文，并在出现具体非正餐食品时禁止该商户推断。路由confidence为显式时刻0.79、发生时刻0.74，均要求确认。ngram-only的breakfast/lunch/dinner不被采用，不能猜餐段。

独立机制测试覆盖24小时和分钟边界、正文时刻优先、日期不含时刻、主食、饮品/零食/食材、无映射/停用映射、统一危险门禁及模型不得独立猜餐段。全量format/analyze/test、既有warm benchmark完成后，记录 [production freeze](../tools/evaluation/phase3_product_contract_production_freeze.json)，包含生产源码、评测工具、全部锁定模型/知识/训练输入hash和聚合productionSha256。冻结后禁止修改识别代码。

最终评测一次运行所有migrated-104及v6 first-run。meal accuracy分母预先固定为全部expected早餐/午餐/晚餐case（包括未命中），另记路由应用数；otherGeneralFallbackCount只计实际兜底，不把词典或模型本来预测other.general计入。P2 expected reject必须blocked且不能quick-confirm，同时报告全P2 blocked rate。v6 initial报告不可覆盖；首次结束后只分析失败、维护文档和归档。结果与Phase3收口建议见下表，流程见 [evaluation README](../tools/evaluation/README.md)。

最终冻结评测；无结果驱动的算法变更。

| Corpus | Category | Parent | Type | null | fallback | Meal | P2 safe | p50/p95/p99 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| original190_104class_final | 95.26% | 96.84% | 100.00% | 5 | 6 | 89.47% (19例) | 100% | 0.264/0.922/1.236 |
| v2_104class_final | 90.00% | 93.68% | 100.00% | 6 | 13 | 90.00% (10例) | 100% | 0.267/0.850/1.053 |
| v3_104class_final | 94.00% | 96.00% | 98.00% | 0 | 5 | 100.00% (1例) | 100% | 0.251/0.495/0.874 |
| v4_104class_final | 70.67% | 78.33% | 97.33% | 0 | 48 | 80.00% (5例) | 100% | 0.269/0.625/0.801 |
| v5_104class_final | 78.75% | 84.25% | 96.50% | 0 | 48 | 100.00% (12例) | 100% | 0.264/0.660/0.832 |
| v6_first_run_initial | 76.00% | 82.00% | 96.25% | 0 | 66 | 76.00% (25例) | N/A (0例) | 0.288/0.692/0.889 |

所有报告high-confidence wrong=0。v6无P2样本，原始report的空分母数值0必须解释为N/A。v6首次报告保持原字节，不覆盖。

v6分类错误96例，其中错父类72、父类正确但子类错误24；type错误15例。餐段19/25，失败集中在正餐证据缺失与已吃食品/食材边界；仅分析记录，不增加规则。

format、analyze、113项test及diff检查通过。10000次warm benchmark p50/p95/p99=0.148/0.405/0.472ms；冻结n-gram既有p95=0.032ms。均为本机Dart VM，非Android实机。

本轮实现任务完成；不建议Phase 3整体收口：v5、v6分类仍低于80%，v6 P1为72.66%，且缺少P2覆盖。

完整结果与SHA256见 [验收归档](../tools/evaluation/phase3_product_contract_artifacts.json)。productionSha256=`91de03c89c5b170af8f8b62901697ee46b12b9d59c4fb71728f257f02dab1996`，最终评测后再次验证全部生产hash未变。

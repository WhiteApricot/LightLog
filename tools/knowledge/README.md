# 本地知识资产维护

当前字符模型已经实现：训练、配置、冻结与报告见 [tools/ngram](../ngram/README.md)。唯一 LocalRecognizer 通过 EvidenceFusion 使用弱证据，confidence ceiling=0.69，不更改实体/词典/family/composition generation。运行资产新增 ngram.bin 并参与 knowledgeHash。下文“未实现”和旧 taxonomy 分数为历史状态；当前前后评测见 [算法记录](../../docs/RECOGNITION_ALGORITHM.md)。

Active knowledge source 为 merchants_source、mainland_entities_source、category_lexicon_source、lexicon_expansion_source、lexical_families_source 与 composition_rules_source JSON。assets/knowledge 的 compact JSON 与 ngram.bin 是 runtime 资产；quality_report.json 记录知识生成的质量检查，字符模型报告独立维护。

从仓库根目录运行 dart tools/knowledge/generate_knowledge.dart。实体、alias、semantic lexicon 的已有审核、冲突、分布、106 个 LocalRecognizer review samples、抽查和 2 MiB 包体门禁保留。Runtime 不抓取网络，也不保存用户消费数据到远端。

## Family schema v2

104 类迁移后为 193 个 flat families / 2107 normalized unique terms / 311 rules。Family 包含 id、kind、terms、policy 和可选单个 prior（semanticKey/score）。114 standalone / 79 contextual families；prior 覆盖 73 children、composition 覆盖 87，联合覆盖 21 parents / 89 children。未增加词或规则。

requiresAdjacentFamily 限制单字匹配；rule 的 allowOverlap 显式声明嵌入上下文。Matcher 只扫描 family terms 一次，随后按命中的 family 索引规则。Prior 是默认值；明确 semantic lexicon 和 composition 可以覆盖，不建立 family hierarchy。

单一 compositionQuality 检查 prior policy、唯一默认语义、score、taxonomy、跨 type 风险、prior/composition 矛盾、空词、normalized duplicates、危险共享词、无效 family refs、重复 rule/pair、距离、contextual orphan 和规则结构有效性。Family 数量不再作为质量 gate。Report 包含 standalone/contextual count、familiesWithSemanticPrior、prior/composition semantic coverage、parent/child coverage、orphan/unused、term/kind/rule/domain/conflict 分布。unusedRules 是结构检查结果，不能解读为 review samples 对全部规则的覆盖率。

四个 runtime 文件 merchants.json、category_lexicon.json、lexical_families.json、composition_rules.json 共同参与 evaluation knowledgeHash；历史冻结值为 288a37c0；此次资产迁移后已变化。任何 family/rule 改动都会改变 fingerprint。原语义词典仍是 447 entities / 1307 aliases / 7450 positive / 354 negative terms。

## 生成与验证

生成后执行 dart format .、flutter analyze、flutter test、git diff --check，并运行 tools/evaluation/evaluate_recognition.dart 的原 190 corpus 与 tools/benchmark/benchmark_recognition.dart。生产、generator review、evaluation、benchmark 共享 LocalRecognizer，没有独立测试识别器。

当前 review 105/106，保留换锁芯住房维修/生活服务 taxonomy 分歧；99 tests 通过。原 category 96.32% / type 100%；v2/v3/v4 category 90.53% / 97.50% / 67.67%。v5 immutable initial/final category 75.50% / 75.50%，type 94.50% / 96.50%；high-confidence wrong 0、P2 safe 100%，warm benchmark p95 0.403 ms。

严格 blind freeze 与四资产 SHA-256 见 review/phase3_semantic_routing_freeze.json、review/phase3_semantic_routing_v5_freeze.json 和 review/phase3_semantic_routing_final_freeze.json。v5 initial 不能覆盖；唯一一次修复是通用退款 semantic/type 安全门禁，没有增加词或规则。

## 来源归档与停止条件

原始 high-recall family candidate、筛选脚本、family_candidate_review 和旧 family freeze/final 摘要保存在 archive/phase3，不参与 generation。此前候选为 399 families / 5761 unique terms；保留候选词 1819、过滤 3942。语义词典候选的 prepare/merge 工具仍供人工审核使用，原候选及 provenance 已归档；不要把候选当标准答案，也不要重新跑旧 family migration 脚本覆盖现有源。

所有有历史价值的 blind initial/final reports 保留于 tools/evaluation（此前归档文件仍按历史路径保留）。本轮 v5 corpus 已移出根目录。完整 group/semantic metrics、失败分布及最终算法见 [算法记录](../../docs/RECOGNITION_ALGORITHM.md)。

Phase 3 classification 未达到 freeze 门槛：v5 < 80%，deterministic semantic routing insufficient。停止扩 family/composition 和调 v5；下一独立任务评估 character 2–4 gram + linear classifier / Naive Bayes 的低置信 fallback，本轮没有实现。Phase 4 OCR structured extraction 保持独立范围。

## 104 类知识迁移契约

完整标签和正餐最高优先级原则见 [需求契约](../../docs/REQUIREMENTS.md)。删除 takeout、全部 travel/family 支出及 lost/unexpected；按真实用途迁移已有词、实体、prior 和规则，收入差旅报销不变。无分类时的支出/收入 other.general fallback 及完整正餐时间优先级尚待独立 pipeline 任务，本次不调识别参数。后续 n-gram 只能使用 104 个标签，本轮未实现。

Generator 强制 secondLevelTaxonomyCount=104，所有知识输出必须引用合法二级语义，obsoleteRuntimeSemanticReferenceCount=0。逐项审核记录在 tools/knowledge/review/v01_taxonomy_migration.json（相对仓库根）；旧 semantic 仅作为历史审核来源，不参与 runtime generation。移除 36 条不稳定词条语义、4 个无输出的 contextual family 和 5 条无明确用途规则。

本文此前的 corpus 分数、freeze hash 和 blind 记录属于旧 taxonomy 历史结果，不是迁移后验收。本轮仅运行生成、格式化、分析、单元测试和 diff 检查，未读取或运行任何 holdout。

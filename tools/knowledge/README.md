# 本地知识资产维护

Active source 为 merchants_source、mainland_entities_source、category_lexicon_source、lexicon_expansion_source、lexical_families_source 与 composition_rules_source JSON。assets/knowledge 的 compact JSON 是唯一 runtime 资产；quality_report.json 记录每次生成的质量检查。

从仓库根目录运行 dart tools/knowledge/generate_knowledge.dart。实体、alias、semantic lexicon 的已有审核、冲突、分布、106 个 LocalRecognizer review samples、抽查和 2 MiB 包体门禁保留。Runtime 不抓取网络，也不保存用户消费数据到远端。

## Family schema v2

197 个 flat families / 2145 normalized unique terms / 316 rules 保持不变。Family 包含 id、kind、terms、policy，以及可选单个 prior（semanticKey/score）。没有 prior 就是 contextualOnly，存在合法 prior 才能是 standalone。117 standalone / 80 contextual families；prior score 为 0.70–0.78，prior 输出覆盖 78 children，composition 输出覆盖 95；联合覆盖 22 parents / 100 children。

requiresAdjacentFamily 限制单字匹配；rule 的 allowOverlap 显式声明嵌入上下文。Matcher 只扫描 family terms 一次，随后按命中的 family 索引规则。Prior 是默认值；明确 semantic lexicon 和 composition 可以覆盖，不建立 family hierarchy。

单一 compositionQuality 检查 prior policy、唯一默认语义、score、taxonomy、跨 type 风险、prior/composition 矛盾、空词、normalized duplicates、危险共享词、无效 family refs、重复 rule/pair、距离、contextual orphan 和规则结构有效性。Family 数量不再作为质量 gate。Report 包含 standalone/contextual count、familiesWithSemanticPrior、prior/composition semantic coverage、parent/child coverage、orphan/unused、term/kind/rule/domain/conflict 分布。unusedRules 是结构检查结果，不能解读为 review samples 对全部规则的覆盖率。

四个 runtime 文件 merchants.json、category_lexicon.json、lexical_families.json、composition_rules.json 共同参与 evaluation knowledgeHash；最终为 288a37c0。任何 family/rule 改动都会改变 fingerprint。原语义词典仍是 447 entities / 1307 aliases / 7486 positive / 355 negative terms。

## 生成与验证

生成后执行 dart format .、flutter analyze、flutter test、git diff --check，并运行 tools/evaluation/evaluate_recognition.dart 的原 190 corpus 与 tools/benchmark/benchmark_recognition.dart。生产、generator review、evaluation、benchmark 共享 LocalRecognizer，没有独立测试识别器。

当前 review 105/106，保留换锁芯住房维修/生活服务 taxonomy 分歧；99 tests 通过。原 category 96.32% / type 100%；v2/v3/v4 category 90.53% / 97.50% / 67.67%。v5 immutable initial/final category 75.50% / 75.50%，type 94.50% / 96.50%；high-confidence wrong 0、P2 safe 100%，warm benchmark p95 0.403 ms。

严格 blind freeze 与四资产 SHA-256 见 review/phase3_semantic_routing_freeze.json、review/phase3_semantic_routing_v5_freeze.json 和 review/phase3_semantic_routing_final_freeze.json。v5 initial 不能覆盖；唯一一次修复是通用退款 semantic/type 安全门禁，没有增加词或规则。

## 来源归档与停止条件

原始 high-recall family candidate、筛选脚本、family_candidate_review 和旧 family freeze/final 摘要保存在 archive/phase3，不参与 generation。此前候选为 399 families / 5761 unique terms；保留候选词 1819、过滤 3942。语义词典候选的 prepare/merge 工具仍供人工审核使用，原候选及 provenance 已归档；不要把候选当标准答案，也不要重新跑旧 family migration 脚本覆盖现有源。

所有有历史价值的 blind initial/final reports 保留于 tools/evaluation（此前归档文件仍按历史路径保留）。本轮 v5 corpus 已移出根目录。完整 group/semantic metrics、失败分布及最终算法见 [算法记录](../../docs/RECOGNITION_ALGORITHM.md)。

Phase 3 classification 未达到 freeze 门槛：v5 < 80%，deterministic semantic routing insufficient。停止扩 family/composition 和调 v5；下一独立任务评估 character 2–4 gram + linear classifier / Naive Bayes 的低置信 fallback，本轮没有实现。Phase 4 OCR structured extraction 保持独立范围。

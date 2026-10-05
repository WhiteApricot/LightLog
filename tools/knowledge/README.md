# 本地知识资产维护

`merchants_source.json`、`mainland_entities_source.json`、`category_lexicon_source.json`、`lexicon_expansion_source.json`、`lexical_families_source.json` 与 `composition_rules_source.json` 是 active 可审查源清单；`assets/knowledge/*.json` 是应用打包使用的 compact 生成物，`quality_report.json` 是每次生成的质量报告。

人工清单覆盖经审核的大陆日常 merchant/platform/service/product brand。Phase 3 曾使用的 Wikidata 影视/游戏快照与抓取脚本已移入 `archive/phase3/`，不再参与 active pipeline；其中 1600 条记录从未进入 runtime。数据不包含地图 POI、用户评论、地址全集或受限平台批量数据。不得批量抓取地图、点评平台或公共 Nominatim。

从仓库根目录执行：

```bash
dart tools/knowledge/prepare_lexicon_candidates.dart --candidate <candidate.json> --report tools/knowledge/review/lexicon_candidate_report.json --review tools/knowledge/review/lexicon_candidate_review.json
dart tools/knowledge/merge_lexicon_candidates.dart --review tools/knowledge/review/lexicon_candidate_review.json --target tools/knowledge/lexicon_expansion_source.json
dart tools/knowledge/generate_knowledge.dart
```

Phase 3 候选原件归档在 `archive/phase3/lightlog_lexicon_candidate.json`。prepare 工具复用 production normalization，输出逐词接受/拒绝原因；merge 只消费已审核 review，并以 `sourceId` 保证重复执行不会叠加。候选的巨量 `negativeTerms` 不进入 runtime，只有显式 conflict 信息参与筛选。

脚本与运行时复用同一 alias 规范化口径，并检查 taxonomy、受控 kind/role/breadth、alias match policy、重复/冲突、score/confidence、实体分布、每个高频 semanticKey 的真实语言覆盖、106 条 production matcher/fusion review samples、50 个实体与 100 个词条抽查清单、review status 和运行时包体。实体、alias、正负词规模未达到 300/800/1800/250，未解决冲突，抽样准确率低于 98%，或资产达到 2 MiB 都会阻断生成。质量优先，达到下限后不以继续堆数量作为优化目标。生成后必须提交源清单、抽样清单、质量报告和 compact JSON，并运行识别测试与性能基准。

## Phase 3 family 精炼（2026-10-05）

原始候选 `archive/phase3/lexical_family_candidates.json` 只作为来源归档，不参与 generation。一次性初稿筛选脚本同目录归档，最终审核事实以 active JSON 和 `review/family_candidate_review.json` 为准；不要在最终源上重跑归档脚本。候选 399 个 family、5761 个唯一词，最终保留候选词 1819 个、过滤 3942 个；合并相近概念，剔除机械包装、单字和多义词，不信任候选 semantic 提示。

最终 197 个 flat family、2145 个 normalized 唯一词、316 条 rule，组合输出覆盖 95 个 semanticKey。generator 在写 runtime 前验证 family kind、共享词 owner、单字限制与覆盖门槛 120/900/100/50；报告包含 `familyTermsByFamily`、`familyKindDistribution`、`unusedFamilies`、`rulesPerFamily`、`rulesPerSemantic`、`compositionSemanticCoverage`、`duplicateFamilyTerms`、`crossFamilyAmbiguousTerms`、`shortHighRiskFamilyTerms`、`compositionDomainDistribution`。无无效引用、无效 semantic、重复规则或未解决危险共享词；医院/门诊显式允许 venue/action 跨角色共享。“换”只可紧邻已审核部件，不匹配换整机或远距文本。

四个 runtime 文件共同参与 evaluation FNV-1a `knowledgeHash`，最终 `40b6b94c`。冻结记录为 `review/phase3_family_freeze.json` 和 `review/phase3_family_v4_freeze.json`；v4 initial 不可覆盖。原 regression 96.32%、v2 88.95%、v3 97.50%；v4 initial/final 59.33%/62.00%，final high-confidence wrong 0、P2 safe 100%、warm benchmark p95 0.436 ms。最终 generator review 为 105/106（99.06%），唯一分歧是换锁芯的住房维修/生活服务归属。

详细分组、118 语义评测和剩余 failure families 见 [算法记录](../../docs/RECOGNITION_ALGORITHM.md#phase-3-family-generalization-v4)。本轮没有达到分类收口条件，不以规模门槛代替泛化正确率，不继续基于已见 v4 扩库，不引入 n-gram。

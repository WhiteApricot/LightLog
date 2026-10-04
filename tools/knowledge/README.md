# 本地知识资产维护

`merchants_source.json`、`mainland_entities_source.json`、`category_lexicon_source.json` 与 `lexicon_expansion_source.json` 是 active 可审查源清单；`assets/knowledge/*.json` 是应用打包使用的 compact 生成物，`quality_report.json` 是每次生成的质量报告。

人工清单覆盖经审核的大陆日常 merchant/platform/service/product brand。Phase 3 曾使用的 Wikidata 影视/游戏快照与抓取脚本已移入 `archive/phase3/`，不再参与 active pipeline；其中 1600 条记录从未进入 runtime。数据不包含地图 POI、用户评论、地址全集或受限平台批量数据。不得批量抓取地图、点评平台或公共 Nominatim。

从仓库根目录执行：

```bash
dart tools/knowledge/generate_knowledge.dart
```

脚本与运行时复用同一 alias 规范化口径，并检查 taxonomy、受控 kind/role/breadth、alias match policy、重复/冲突、score/confidence、实体分布、每个高频 semanticKey 的真实语言覆盖、106 条 production matcher/fusion review samples、50 个实体与 100 个词条抽查清单、review status 和运行时包体。实体、alias、正负词规模未达到 300/800/1800/250，未解决冲突，抽样准确率低于 98%，或资产达到 2 MiB 都会阻断生成。质量优先，达到下限后不以继续堆数量作为优化目标。生成后必须提交源清单、抽样清单、质量报告和 compact JSON，并运行识别测试与性能基准。

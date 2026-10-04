# 本地知识资产维护

`merchants_source.json`、`category_lexicon_source.json` 与 `source_data/wikidata_entities.json` 是可审查源清单；`assets/knowledge/*.json` 是应用打包使用的 compact 生成物，`quality_report.json` 是每次生成的质量报告。

人工清单覆盖经审核的大陆日常 merchant/platform/service/product brand。Wikidata 影视/游戏结构化快照保留 source URL、source type、license 和 verifiedAt，但其 1600 条记录当前均为 `snapshotOnly`，不经人工审核不进入 runtime。数据不包含地图 POI、用户评论、地址全集或受限平台批量数据。不得批量抓取地图、点评平台或公共 Nominatim。

需要显式刷新公开快照时执行（普通算法构建不联网）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/knowledge/fetch_wikimedia_entities.ps1
```

从仓库根目录执行：

```bash
dart tools/knowledge/generate_knowledge.dart
```

脚本与运行时复用同一 alias 规范化口径，并检查 taxonomy、受控 kind/role/breadth、alias match policy、重复/冲突、score/confidence、场景语义覆盖、固定 review samples、review status 和运行时包体。质量优先且允许实体数量下降，不再设置数量下限；未解决冲突、抽样失败或资产达到 2 MiB 会阻断生成。生成后必须提交源清单、抽样清单、质量报告和 compact JSON，并运行识别测试与性能基准。

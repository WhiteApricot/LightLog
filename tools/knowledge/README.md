# 本地知识资产维护

`merchants_source.json` 与 `category_lexicon_source.json` 是可审查源清单；`assets/knowledge/*.json` 是应用打包使用的 compact 生成物。

当前商户名称和别名是对公开品牌名称事实的小规模人工整理，不包含地图 POI、用户评论、地址全集或受限平台批量数据。新增记录时应优先使用 Wikidata 等许可清晰的结构化来源或品牌官网核验名称，并在评审说明中记录来源；不得批量抓取地图、点评平台或公共 Nominatim。

从仓库根目录执行：

```bash
dart tools/knowledge/generate_knowledge.dart
```

脚本与运行时复用同一 alias 规范化口径，并检查 taxonomy、重复/冲突 alias、词典冲突和 score/confidence 范围。生成后必须提交源清单和对应 compact JSON，并运行识别测试与性能基准。

# Phase 3 产品规则验收

本轮只迁移旧oracle并实现other.general fallback与完整正餐时间路由；n-gram、训练数据、threshold/margin、特征维度和知识资产/源文件完全冻结。

`migrate_104class_oracles.py`是一次性离线审核迁移：仅对退役expected类别逐条按真实用途迁移，所有原有合法类别以及input/type/status/amount/time/issues不变。111条改动及一条退役history引用，覆盖原190/v2/v3/v4/v5共1280条。原始文件移至archive/legacy_taxonomy，逐条理由在其oracle_migration_review.json。新文件位于corpora/phase3_104class，文件名以_104class.json结尾。oracle_migration_freeze.json记录104-class校验、原始与迁移后SHA256及封存时刻；迁移脚本拒绝再次运行。

封存后到production freeze之间，不打开/解析/搜索/统计新corpus或审核明细，也不读取v6；开发仅用需求、现有源码/知识和独立机制测试。phase3_product_contract_locked_inputs.json记录n-gram及全部知识与训练输入初始hash。生产完成全部检查及benchmark后，phase3_product_contract_production_freeze.json记录源码hash与聚合productionSha256；从此禁止修改识别代码。

仅在生产完全冻结后从仓库根执行一次：

```powershell
powershell -NoProfile -File tools/evaluation/evaluate_product_contract.ps1
```

runner先核对production hash、封存oracle hash，再统一评测五套历史数据并首次打开根目录v6。v6_first_run_initial.json不可覆盖；runner拒绝第二次运行，evaluator也在读取corpus之前拒绝覆盖initial报告。首次v6评测结束后再将v6原样归档至corpora/phase3_104class，不改expected。

报告包含category/parent/type accuracy、category=null、实际otherGeneralFallbackCount、其他分类总数、mealRoutingAccuracy及其样本数、应用路由数量、high-confidence wrong、P2 safe/blocked及warm p50/p95/p99。meal准确率分母固定为所有expected breakfast/lunch/dinner，包括未命中项，不只统计成功路由。对expected reject的P2，safe要求blocked且不能quick-confirm；同时报告全P2 blocked rate。正常历史null oracle仍维持“该字段不考核”的既有评测口径。任何失败只分析记录，不重标oracle、不调模型/规则。

旧taxonomy及旧n-gram轮报告保留历史意义；旧工具引用的历史文件如今在archive，复现旧轮请使用其对应commit，不用当前production覆盖历史报告。性能为host Dart VM warm，不宣称API26实机结果。

最终验收已完成；v6原文件已按原字节归档到corpora/phase3_104class。报告、分析与summary在reports/phase3_product_contract，文件hash在phase3_product_contract_artifacts.json。v6 P2样本数为0，raw report空分母的0应解释为N/A；summary明确保存null。全部识别源码/模型/知识hash在评测后保持冻结。

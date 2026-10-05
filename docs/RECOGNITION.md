# 智能识别设计

当前 Phase 2 文字 Parser 的逐阶段实现、证据权重、已知缺陷和实验路线维护在 [RECOGNITION_ALGORITHM.md](RECOGNITION_ALGORITHM.md)。本文只维护识别系统的稳定边界与总体设计。

## 总原则

Phase 3 本地识别器按五层证据组织：

```text
0. Field-aware Extraction
1. Normalization
2. Personal History
3. Local Entity Knowledge Base
4. Category Lexicon
5. Character n-gram classifier（尚未实现，当前也不保留空接口）
→ Evidence Fusion / Confidence
```

当前已实现字段/span、Normalization、Personal History、审核制 Entity Knowledge Base、Category Lexicon、独立 TypeInference 和 Evidence Fusion。Character n-gram 尚未实现；只有当结构性重构后的正式 P1 明显低于 75% 且失败分析证明规则收益耗尽时，才单独决策。全部在本机运行，App 运行时不联网。Web Search 和 LLM 不属于 V0.1。

任何识别来源都只能生成 `RecognitionCandidate`：

```text
OCR != Transaction
Parser != Transaction
LLM != Transaction
```

Candidate 经用户确认或高置信自动确认策略后，才可由 Repository 写成 `Transaction`。高置信自动入账必须同时提示并支持撤销；低置信或冲突结果必须确认。

## 文字识别流水线

```text
Raw Text
→ raw/display/matching 双轨 Normalize
→ Transaction status / Natural Time / protected numeric spans
→ Amount candidates / Content span / Preliminary type evidence
→ indexed History / Local Entity KB / role-aware Category Lexicon
→ FamilyMatcher (concept / optional prior / composition) / SpanConflictResolver
→ parent-first EvidenceFusion / TypeInference.reconcile
→ semanticKey / CategoryResolver
→ Candidate
```

各阶段职责：

- Normalize：保留 raw/display，另建 matching/index 视图；大小写、全半角、空白和标点处理不得破坏展示内容或 span。
- Field Extractor：区分金额、日期、订单号、数量、型号、标题数字等角色；金额按字段上下文评分，冲突必须标记。
- Transaction Status：失败、取消、非交易页阻断普通候选；退款与多交易显式报告。
- Time Parser：识别显式时间和“昨晚”等相对时间；未给出时使用当前设备本地时间。
- Content Parser：提取内容/商户候选，不凭空补全具体商户。
- Evidence Layers：按 key 查询的个人历史、实体 exact/substring/fuzzy 和带 role/negative 的词典统一输出结构化 evidence。
- Fusion / Resolver：specific product/action/service 高于 platform/broad entity，merchant 默认语义只作 fallback；个人历史需满足净支持门禁；先输出稳定消费语义，再映射当前活动分类。
- Candidate：汇总字段、语义、当前分类映射、每项证据、冲突、缺失项和 confidence。

具体实现、数据规模、阈值和生成命令见 [RECOGNITION_ALGORITHM.md](RECOGNITION_ALGORITHM.md)。

Family 保持平面概念模型；稳定概念可以产生弱 standalone prior，contextual-only 概念必须等待上下文。Composition 对已命中 spans 精化/覆盖；没有实际 replacement evidence 的概念不能删除词典语义。Fusion 先选 parent，再排 child；语义可以校正弱默认类型，强类型冲突仍需确认，退款语义仍要求关联原账目。v5 initial/final category 均为 75.50%，Phase 3 classification 尚未收口；停止调 v5 和扩 family/rule，下一独立算法任务评估轻量字符分类 fallback，本轮没有实现 n-gram。

示例输入：

```text
二食堂 15
星巴克32
打车 19.8
工资 +5000
昨晚麦当劳 28
```

当前规则分别生成餐饮、饮品、交通、工资收入及带自然时间的候选。识别器不使用分类名称或 ID 作为知识输出；数据库缺少目标 `semanticKey` 的活动分类映射时 Candidate 标记为不完整，不能提交。

## 时间分类

时间是上下文信号，而不是商户事实。餐食词可结合发生小时提供弱分类 evidence，但不得覆盖个人历史或精确商户知识。自然时间始终基于注入的 `now`；daypart 默认与周/月边界规则以算法文档为准，显式时刻优先。

## OCR 流水线

```text
Image
→ OcrService
→ OCR text blocks
→ Transaction field extraction
→ RuleEngine
→ RecognitionCandidate
```

`OcrService` 隔离 Google ML Kit Text Recognition，业务测试使用 `MockOcrService`。字段提取尽量识别：

- 金额
- 商户
- 时间
- 交易号/订单号
- 商品或订单详情
- 支付平台

OCR 文本和坐标可用于当次字段提取，但不得直接写账。默认不保存原始支付截图；识别失败或退出流程时也不应留下持久副本。临时文件清理策略在 Phase 4 OCR 实现阶段确定。

## Confidence

Phase 3 分别计算 amount/type/category/time/content confidence，再由 gating 得到 overall confidence。个人历史可覆盖通用知识；具体商品、行为和服务高于平台与宽泛实体；同向独立来源只小幅增分；fuzzy、platform、broad-only 和强冲突均有上限；低于最低分类证据阈值时返回不确定。金额、内容、类型和时间证据仍随 Candidate 保留，但不能把无分类证据“加成”为高置信分类。当前回归失败子集的 high-confidence wrong 为 0。

当前不启用自动入账：用户必须主动识别并确认或修改。低置信冲突可以展示当前最优分类供复核；缺少金额、内容、分类语义或当前分类映射会阻止直接保存。

## 用户反馈学习

Phase 3 的 Personal History 已处理确认和修改反馈：

```text
Candidate
→ 用户确认/修改
→ 记录 recognition event
→ 更新 recognition rule
```

后续相似输入：

```text
历史证据 + 当前证据
→ confidence
→ 高置信自动写入并提供撤销 / 低置信要求确认
```

不得把“第一次确认、第二次自动”机械写死为次数规则。用户纠正会增加原预测的 correction 并强化最终语义；命中、纠正和最近使用共同形成基础证据。撤销反馈、复杂衰减和规则合并仍为 **TBD**，留待 hardening。

## 重复检测

优先比较订单号/交易号；没有稳定 ID 时，使用规范化商户、`amountMinor`、时间窗口和 `source` 评估 fingerprint。时间窗口和相似阈值为 **TBD**。疑似重复时提示用户，不静默覆盖、跳过或创建重复账目。

## 防幻觉要求

明确禁止：

- 无证据猜出具体商户并静默保存。
- OCR 失败时编造金额、商户、时间或订单号。
- 金额冲突时自行选择且不提示。
- 以时间规则无条件覆盖更明确证据。
- 将低置信 Candidate 直接写入正式账本。
- Future 接入 LLM 后让其直接拥有数据库写权限。
- 将原始支付截图持久化或上传。

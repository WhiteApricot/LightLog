# 智能识别设计

当前 Phase 2 文字 Parser 的逐阶段实现、证据权重、已知缺陷和实验路线维护在 [RECOGNITION_ALGORITHM.md](RECOGNITION_ALGORITHM.md)。本文只维护识别系统的稳定边界与总体设计。

## 总原则

自动识别的优先级为：

```text
个人历史规则
>
确定性解析
>
上下文规则
>
未来商户知识库
>
未来 Web Search
>
未来 LLM
```

V0.1 只实现前三项，全部在本机运行。商户知识库、Web Search 和 LLM 仅属于 Future。

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
→ Normalize
→ Amount Parser
→ Time Parser
→ Content Parser
→ Keyword Matching
→ Candidate
```

各阶段职责：

- Normalize：清理空白、全半角和常见货币符号，不丢失原始输入。
- Amount Parser：识别整数、小数、正负号和货币提示，输出整数 `amountMinor`；金额冲突必须标记。
- Time Parser：识别显式时间和“昨晚”等相对时间；未给出时使用当前设备本地时间。
- Content Parser：提取内容/商户候选，不凭空补全具体商户。
- Keyword Matching：用确定性关键词推断账务类型和分类。
- Candidate：汇总字段、每项证据、冲突、缺失项和 confidence。

Phase 2 只实现到确定性 Candidate；`History Rules` 留到 Phase 4，不参与当前评分。

示例输入：

```text
二食堂 15
星巴克32
打车 19.8
工资 +5000
昨晚麦当劳 28
```

当前确定性规则分别生成餐饮、饮品/餐饮、交通、工资收入及带相对时间的餐饮候选。分类名称由规则匹配，但对应 ID 必须从数据库分类中查找；数据库缺少目标分类时 Candidate 标记为不完整，不能提交。

## 时间分类

时间是上下文信号，而不是事实。例如午间可增加“午餐”的权重，但不得无条件覆盖明确的商户规则或关键词。跨午夜的“昨晚”等相对表达基于解析时设备本地日期计算，并保留解析时 UTC offset；`昨晚` 默认前一天 20:00、`今早` 默认当天 08:00、`今晚` 默认当天 20:00，输入中的 `HH:mm` 优先覆盖默认时刻。未输入时间时使用解析时的本地日期和分钟。

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

OCR 文本和坐标可用于当次字段提取，但不得直接写账。默认不保存原始支付截图；识别失败或退出流程时也不应留下持久副本。临时文件清理策略在 OCR 实现阶段确定。

## Confidence

Phase 2 采用相加后限制在 `0..1` 的简单可解释评分：

- 唯一且有效的金额：`0.35`。
- 存在金额、时间之外的内容：`0.15`。
- 明确正负号或收入关键词确定类型：`0.15`；无收入证据时默认支出：`0.05`。
- 分类关键词命中：`0.25`；回退到“其他支出/其他收入”：`0.05`。
- 明确日期或时间表达：`0.10`。

评分结果同时携带逐项证据说明。缺少金额/内容、出现多个金额或数据库分类缺失会使 Candidate 不完整。Phase 2 不设置自动确认门槛：所有文字候选都必须进入编辑页，由用户确认或修改后再通过现有 Repository 写入正式 `Transaction`。

## 用户反馈学习

首次或不确定识别：

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

不得把“第一次确认、第二次自动”机械写死为次数规则。用户纠正必须降低或修正规则权重；自动入账后的撤销也应作为负反馈信号，具体更新策略为 **TBD**。

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

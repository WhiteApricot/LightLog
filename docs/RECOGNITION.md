# 智能识别设计

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
→ History Rules
→ Candidate
```

各阶段职责：

- Normalize：清理空白、全半角和常见货币符号，不丢失原始输入。
- Amount Parser：识别整数、小数、正负号和货币提示，输出整数 `amountMinor`；金额冲突必须标记。
- Time Parser：识别显式时间和“昨晚”等相对时间；未给出时使用当前设备本地时间。
- Content Parser：提取内容/商户候选，不凭空补全具体商户。
- Keyword Matching：用确定性关键词推断账务类型和分类。
- History Rules：匹配本地 `recognition_rules`，提供个性化证据。
- Candidate：汇总字段、每项证据、冲突、缺失项和 confidence。

示例输入：

```text
二食堂 15
星巴克32
打车 19.8
工资 +5000
昨晚麦当劳 28
```

期望解析方向分别为餐饮候选、饮品/餐饮候选、交通候选、收入候选及带相对时间的餐饮候选；实际分类仍受个人历史规则和置信度约束。

## 时间分类

时间是上下文信号，而不是事实。例如午间可增加“午餐”的权重，但不得无条件覆盖明确的商户规则、关键词或稳定的个人历史规则。跨午夜的“昨晚”等相对表达必须基于设备本地时间解析，并保留解析依据。

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

V0.1 采用简单、可解释的规则评分：

- 精确个人历史规则命中：高权重。
- 明确金额、账务类型或分类关键词：中高权重。
- 多个独立证据一致：提高置信度。
- 仅时间推断：低权重。
- 缺少关键字段、金额冲突或多规则冲突：降低置信度或阻止自动确认。

具体权重、阈值和自动确认门槛为 **TBD**，在实现阶段通过 unit test 和样例调优。评分结果必须可说明主要证据，不能只返回不透明数字。

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

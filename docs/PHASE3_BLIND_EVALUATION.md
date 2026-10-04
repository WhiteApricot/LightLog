# Phase 3 Blind Evaluation

首次 blind corpus 解封发生在知识门禁、`flutter analyze` 和全量基础测试通过之后。
评测 runner 为 `tools/evaluation/evaluate_recognition.dart`，原始报告为
`tools/evaluation/phase3_blind_initial.json`。本文件不复制 corpus 内容。

## 首次结果

| 指标 | 结果 |
|---|---:|
| P0 accuracy | 27/41 = 65.85% |
| P1 accuracy | 45/134 = 33.58% |
| P2 exact accuracy | 2/15 = 13.33% |
| P2 safe-rejection rate | 14/15 = 93.33% |
| amount accuracy | 94.21% |
| type accuracy | 78.42% |
| category accuracy | 64.74% |
| time accuracy | 96.84% |
| complete candidate accuracy | 38.95% |
| high-confidence wrong predictions | 14 |
| average latency | 507.1 µs |
| p95 latency | 1101 µs |
| max latency | 16190 µs |

严格 complete accuracy 包含 expected status、非空字段、content、issue code 与分类/时间。
英文 display content 被 normalization 转为小写会计入 content mismatch；但即使忽略这一项，P0、P1、
category accuracy 和高置信错误仍明显不达标，因此结论不受该严格口径影响。

## 失败分布

一个 case 可同时有多个原因：

| 原因 | 数量 |
|---|---:|
| category / fusion | 67 |
| content extraction | 60 |
| status（complete/partial/reject 不符） | 55 |
| type inference | 41 |
| amount extraction | 11 |
| safe-rejection issue | 11 |
| time parsing | 6 |

失败最多的 group 为 real-world edge 15、merchant KB 14、time parser 10、numeric ambiguity 10、
OCR-like 10、category lexicon 10；全部 8 个 fusion-conflict case 均未完整通过。

## 结构性原因

1. 词典达到规模门禁，但由 taxonomy 名称派生的通用词形不等价于真实语言覆盖。大量高频短语、商品词、
   服务动作和领域同义词仍缺失，说明“term 数量/semantic coverage”门禁不能替代语义质量抽检。
2. Content extraction 仍主要是从规范化全文删时间/选中金额，没有稳定的 merchant/product span 选择；
   OCR 标签、自然语言冗余、数量词和大小写因此进入 display content。
3. Entity 与上下文 Fusion 的粒度不足。品牌默认语义会压过餐时、维修等更具体行为；平台与商品冲突也仍有
   高置信错误，当前 confidence 没有被结构性冲突充分校准。
4. 未命中语义时 type 跟随 semanticKey 为空，导致大量本应是普通支出的样例从 complete 退化为 partial。
   这不是简单降低阈值即可解决，需要把“交易方向证据”和“分类证据”分开建模。
5. Amount 与 time 基础正确率较高，但中文口语金额、品牌内连字符数字、多金额 OCR 语义仍有系统性缺口。
6. Local Entity KB 的 1600 条公开标题显著提高规模，却没有补足大陆日常商户/服务实体；当前实体分布与
   真实记账场景不平衡。

## 结论与停止条件

结果符合任务定义的“整体完全不可接受”：P0 大量失败、P1 远低于 90%，并存在 14 个高置信错误。
因此没有查看失败后继续修改 Parser/Fusion/词典，也没有进行 test-specific hardcode；首次报告同时是本轮
最终报告，不存在 after-fix 指标。

## 建议的下一步（等待人工审核）

- 先重做 field extractor 的 span/label 模型，将 transaction、merchant、product、amount、time 分段，
  保留 raw display text 与 normalized matching text 的双轨结果。
- 用人工审核的场景词表替换 taxonomy 自动词形扩展；为每个高频 semanticKey 维护 product/action/
  merchantType/negative 的真实短语，并增加抽样质量门禁。
- 将 Fusion 改为“具体行为覆盖实体默认语义”，对平台、宽泛品牌、餐时覆盖和 negative evidence 做显式规则，
  并用离线 calibration 约束高置信阈值。
- 扩展大陆日常 merchant/service KB；若 alias 规模继续增长，改用 Trie/Aho-Corasick，并为 fuzzy 建立独立候选索引。
- 在确定性层稳定后再评估第五层 char n-gram；当前失败尚不能证明纯规则方案已达能力上限。

## 后续重构状态

上述内容是不可变的首次基线结论。后续已按
[`PHASE3_RECOGNITION_REFACTOR_PLAN.md`](PHASE3_RECOGNITION_REFACTOR_PLAN.md) 完成单一生产内核重构；
新的失败子集报告位于 `tools/evaluation/phase3_refactor_failure_subset.json`，分析摘要位于
`tools/evaluation/phase3_refactor_failure_analysis.md`。仓库未保存首次评测中 74 条通过项的原始输入，
因此后续数字明确标记为 116 条失败子集实测或基于旧通过项未回退的重建值，不覆盖本页首次报告。

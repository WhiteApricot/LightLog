# Phase 3 NOT CLOSED：冻结后 v7 失败分析

800 cases：category errors=165，parent wrong=94，同父错 child=71，type wrong=42，false other=20。P2 safe=80/80；高置信错误=0，普通有效 category=null=0。

**P2 的100%不能代表全部安全通过**：另外6个P0/P1退款 oracle 要求关联原交易并 reject，但实际返回 warning/可复核确认。该跨priority拒答漏检保持原报告，不按v7补规则。

## 分维度统计（允许重叠）

| 维度 | 数量 |
|---|---:|
| correct parent / wrong child | 71 |
| meal error | 7 |
| taxonomy-boundary residual (pair proxy) | 65 |
| unseen expected entity/product (vocabulary proxy) | 98 |
| wrong parent | 94 |
| false other.general | 20 |
| multi-clause/context interference | 41 |
| wrong direction/type | 42 |
| safety failure (all priorities) | 6 |
| merchant/platform noise | 25 |
| meal detection miss | 2 |

Counts overlap; taxonomy/unseen/context are explicitly identified static report/vocabulary proxies, not human adjudication or a second prediction run. Safety checks all priorities, unlike built-in P2-only failureDecomposition.safety.

## Top confused parent pairs

| Expected | Actual | Count |
|---|---|---:|
| income-investment | expense-finance | 9 |
| expense-food | expense-other | 6 |
| income-other | expense-social | 5 |
| income-refund | income-other | 4 |
| expense-shopping | expense-daily | 3 |
| expense-digital | expense-education | 3 |
| expense-other | expense-social | 3 |
| income-salary | expense-other | 3 |
| income-other | expense-finance | 3 |
| expense-other | expense-finance | 3 |
| income-other | expense-other | 3 |
| expense-shopping | expense-sports | 2 |
| expense-daily | expense-shopping | 2 |
| expense-digital | expense-shopping | 2 |
| income-reimbursement | income-other | 2 |

## Top confused child pairs

| Expected | Actual | Count |
|---|---|---:|
| expense.entertainment.performance | expense.entertainment.media | 7 |
| expense.digital.computer | expense.digital.repair | 7 |
| expense.daily.cleaning | expense.daily.service | 5 |
| expense.food.other | expense.other.general | 4 |
| expense.housing.gas | expense.housing.utilities | 4 |
| expense.entertainment.activity | expense.entertainment.media | 4 |
| income.investment.interest | expense.finance.interest | 4 |
| expense.food.other | expense.food.snack | 3 |
| expense.shopping.home | expense.daily.cleaning | 3 |
| expense.digital.computer | expense.education.stationery | 3 |
| expense.other.general | expense.social.donation | 3 |
| income.reimbursement.other | income.reimbursement.work | 3 |
| income.investment.other | expense.finance.investment | 3 |
| income.refund.service | income.refund.shopping | 3 |
| expense.other.general | expense.finance.investment | 3 |

## 错误最多的 semanticKey

- expense.digital.computer: 10
- expense.food.other: 8
- expense.entertainment.performance: 8
- expense.other.general: 7
- income.other.reward: 7
- income.other.general: 7
- expense.daily.cleaning: 5
- income.refund.service: 5
- expense.food.breakfast: 4
- expense.housing.gas: 4
- expense.entertainment.activity: 4
- expense.social.gift: 4
- expense.sports.equipment: 4
- income.investment.interest: 4
- income.investment.other: 4

## 高频失败语言模式（静态 report tags，重叠）

- implicit income predicates / settlement / credit: 30
- return/deposit/tax with intervening modifiers: 6
- receipt headings / merchant-platform wrapper: 25
- time inference from scene or ambiguous clock: 7
- maintenance / upgrade / accessory action: 4

## 瓶颈与下一阶段

36个 income→expense，其中34个 type confidence=.69，说明是弱方向被统计头错误校正；另2个=.94，说明普通“消费”等词在返现场景被当成强支付方向。Direction dev≈99.96%与v7的差距不能用头容量解释，训练/dev共享记账模板而真实语言省略“收到/收入/到账”；如平台周结、结息、发奖金、二手出掉。应先审计真实语言与现有模板的方向标注/分布，再在下一独立任务改善非循环action/actor/negation作用域表示；本轮不补synthetic或holdout训练。

同父错child71例，最突出performance→media、computer→repair各7，cleaning→service5，gas→utilities4：买商品、人工操作、维修/升级、现场演出/数字内容的语义作用域仍未被binary全文char/无序evidence presence充分表达。96类契约本身不再扩缩。普通soft evidence解除veto后，主瓶颈转为表示与数据的真实语体覆盖，而非继续叠加classifier。

Meal为27/34：2个prepared检测失败，5个餐段/时间解释失败；上班前/午休未提供明确小时，设备参考时刻落在晚餐窗口；“午休一点钟”“加班到九点”等需要更好的时间语言作用域。部分场景本身存在早班/晚班歧义，应明确其输入/默认时间合同而非用v7定向补词。

6个关联退款漏检来自退服务费、押金到账、退回+中间修饰词；P2全部安全不消除这些P0/P1风险。下一阶段优先审计通用退款状态/关联门禁覆盖，再用新的独立未见验收，而非重新运行或调本次v7。

统计优先F3及本轮模型保持冻结。没有v7驱动的模型、规则、threshold、训练数据变更；未上Stage C/Transformer/LLM。

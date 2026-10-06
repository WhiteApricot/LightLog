# 冻结后静态仲裁审查

本补充只审查已冻结代码和唯一 first-run 报告，不再次预测 v7，不修改算法、参数或数据。完整计数、Top confusion 和语言模式见 [失败分析](failure_analysis.md)。

除了语料/表示的真实语体覆盖不足，**fusion 仍有一个残余限制**：LocalRecognizer 把 Direction Head 对弱方向的输出传给 hierarchicalEvidence 的 `direction`，后者按类型过滤 Parent。v7 的36个 income→expense 中，34个最终 type confidence=.69，说明来自统计弱方向；这些 case 的 income Parent 被类型 mask 排除。另2个=.94，属于“消费”等词在返现场景被当作强方向。首跑没有记录未过滤的 Parent posterior，不能宣称解除 mask 后会修复全部34例，也不能据此调整本轮生产。

因此主瓶颈应表述为：**训练/dev的模板语体分布与真实省略表达不一致，加上弱 Direction 与 Parent 的硬约束耦合**。普通 deterministic semantic veto 已解除；这不意味着所有仲裁限制都已消失。下一独立任务应只在 train/dev 审查弱方向的 soft prior / 联合 head 仲裁、action/actor/negation作用域及真实语言分布，并使用新的独立验收。保持96 taxonomy；本轮不再调整。

Meal 27/34：5个餐段/时间解释错误，2个正餐路由未触发。first-run 没有保存 PreparedMeal posterior，后2例不能从现有报告区分“head低分”与“food-parent eligibility门禁”，不能把两例都断言为 head 本身漏检。上班前存在班次歧义；午休/晚餐与一点、九点的组合更多是时间语义作用域覆盖缺口。

P2 safe=80/80，但6个P0/P1退款 oracle 要求 reject/关联原交易，实际 warning 且可复核确认。这是已知跨priority安全漏检，保持 NOT CLOSED。禁止按此次v7补规则、补训练或重跑模型评估。

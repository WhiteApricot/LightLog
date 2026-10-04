# Recognition failure analysis

- Corpus: LightLog Phase 3 Stress Holdout Corpus v2
- Recognizer: v2
- Knowledge hash: `64390c59`
- Failures: 84/190
- High-confidence wrong: 3

## By priority

| Key | Count |
|---|---:|
| P1 | 58 |
| P2 | 20 |
| P0 | 6 |

## By failure reason

| Key | Count |
|---|---:|
| content_span_error | 42 |
| category_or_fusion | 35 |
| status | 16 |
| safe_rejection_issue | 12 |
| type_inference | 5 |
| display_formatting_mismatch | 1 |

## By group

| Key | Count |
|---|---:|
| ocr_noise | 27 |
| semantic_ambiguity | 17 |
| rare_daily | 14 |
| numeric_boundary | 14 |
| income_edge | 9 |
| time_precedence | 3 |

## High-confidence wrong predictions

- `S066` `微信支付
支付成功
收款方：麦当劳
订单号 2026100512345678
原价 ¥36.00
优惠 ¥6.00
实付 ¥30.00
交易时间 2026-10-05 12:18:32`: confidence=0.8799999999999999
- `S090` `微信支付
交易成功
收款方：猫咪医院
项目：绝育
宠物年龄 2岁
检查费 80
手术费 720
实付800`: confidence=0.93
- `S094` `支付成功
商户：眼科门诊
挂号 20
验光 50
本次实付70`: confidence=0.93

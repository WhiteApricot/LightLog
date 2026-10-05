# Recognition failure analysis

- Corpus: LightLog Phase 3 Semantic Routing Holdout Corpus v5
- Recognizer: v3
- Knowledge hash: `288a37c0`
- Failures: 106/400
- High-confidence wrong: 0

Routing failures: {noSemanticOutput: 43, noCategoryOutput: 47, wrongParent: 28, correctParentWrongChild: 23, wrongType: 22}
Parent accuracy: 0.8125; child: 0.755; category null: 47

## By priority

| Key | Count |
|---|---:|
| P1 | 85 |
| P0 | 21 |

## By failure reason

| Key | Count |
|---|---:|
| category_or_fusion | 98 |
| status | 56 |
| type_inference | 22 |
| safe_rejection_issue | 11 |

## By group

| Key | Count |
|---|---:|
| semantic_core | 39 |
| income_core | 29 |
| travel_social_core | 12 |
| finance_core | 10 |
| family_pet_core | 4 |
| hierarchy_transport | 3 |
| hierarchy_digital | 2 |
| type_reconcile | 2 |
| hierarchy_housing | 1 |
| hierarchy_food | 1 |
| hierarchy_travel | 1 |
| hierarchy_social | 1 |
| hierarchy_subscription | 1 |

# Recognition failure analysis

- Corpus: LightLog Phase 3 Local Recognition Test Corpus v1
- Recognizer: v2
- Knowledge hash: `c34a316f`
- Failures: 57/190
- High-confidence wrong: 1

## By priority

| Key | Count |
|---|---:|
| P1 | 36 |
| P2 | 14 |
| P0 | 7 |

## By failure reason

| Key | Count |
|---|---:|
| status | 28 |
| content_span_error | 25 |
| category_or_fusion | 21 |
| type_inference | 12 |
| safe_rejection_issue | 10 |
| time_parsing | 4 |
| display_formatting_mismatch | 2 |

## By group

| Key | Count |
|---|---:|
| numeric_ambiguity | 9 |
| ocr_ambiguous | 8 |
| ocr_like | 6 |
| time_parser | 5 |
| redundant_natural_language | 4 |
| ambiguity | 4 |
| category_lexicon | 3 |
| invalid | 3 |
| basic | 2 |
| merchant_kb | 2 |
| income | 2 |
| invalid_input | 2 |
| normalization_stress | 2 |
| real_world_edge | 2 |
| personal_history | 1 |
| amount_format | 1 |
| unsupported_format | 1 |

## High-confidence wrong predictions

- `R001` `今天中午在学校二食堂吃饭，一共花了15块钱`: confidence=0.8200000000000001

# Recognition failure analysis

- Corpus: LightLog Phase 3 Local Recognition Test Corpus baseline failure subset v1
- Recognizer: v2
- Knowledge hash: `6d2841ec`
- Failures: 35/116
- High-confidence wrong: 0

## By priority

| Key | Count |
|---|---:|
| P1 | 23 |
| P2 | 10 |
| P0 | 2 |

## By failure reason

| Key | Count |
|---|---:|
| content_span_error | 14 |
| status | 13 |
| category_or_fusion | 12 |
| safe_rejection_issue | 10 |
| type_inference | 8 |
| time_parsing | 4 |
| display_formatting_mismatch | 2 |

## By group

| Key | Count |
|---|---:|
| ocr_like | 6 |
| ocr_ambiguous | 6 |
| numeric_ambiguity | 4 |
| redundant_natural_language | 4 |
| invalid | 3 |
| ambiguity | 2 |
| normalization_stress | 2 |
| merchant_kb | 1 |
| category_lexicon | 1 |
| fusion_conflict | 1 |
| personal_history | 1 |
| time_parser | 1 |
| amount_format | 1 |
| unsupported_format | 1 |
| real_world_edge | 1 |

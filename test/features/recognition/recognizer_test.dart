import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/application/recognition_result_mapper.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

import 'recognition_test_fixture.dart';

void main() {
  test('production recognizer parses a canteen expense', () {
    final result = recognizeForTest('二食堂 15');

    expect(
      result.isComplete,
      isTrue,
      reason:
          'issues=${result.issueCodes}, semantic=${result.semanticKey}, '
          'content=${result.draft.content}',
    );
    expect(result.draft.type, RecognitionTransactionType.expense);
    expect(result.draft.amountMinor, 1500);
    expect(result.draft.content, '二食堂');
    expect(result.categoryName, '餐饮');
    expect(result.subcategoryName, '午餐');
  });

  test(
    'display content preserves user casing while matching is normalized',
    () {
      final result = recognizeForTest('Steam 198');

      expect(result.draft.content, 'Steam');
      expect(result.draft.normalizedContent, 'steam');
      expect(result.draft.amountMinor, 19800);
    },
  );

  test('explicit income evidence is independent from category inference', () {
    final result = recognizeForTest('工资 +5000');

    expect(result.draft.type, RecognitionTransactionType.income);
    expect(result.draft.amountMinor, 500000);
    expect(result.semanticKey, 'income.salary.monthly');
    final transactionDraft = RecognitionResultMapper.toTransactionDraft(
      result: result,
      accountId: 'account-bank-card',
    );
    expect(transactionDraft.source, 'text');
  });

  test('explicit meal action outranks merchant default semantics', () {
    final result = recognizeForTest('晚饭麦当劳 25');

    expect(result.draft.content, '麦当劳');
    expect(result.semanticKey, 'expense.food.dinner');
  });

  test('platform is removed when a specific product remains', () {
    final result = recognizeForTest('淘宝 iPhone手机壳 49.9');

    expect(result.draft.content, 'iPhone手机壳');
    expect(result.semanticKey, 'expense.digital.accessory');
  });

  test('personal history wins only after repeated net-positive feedback', () {
    final now = DateTime(2026, 10, 4, 12, 30);
    final result = recognizeForTest(
      '星巴克 28',
      now: now,
      history: [
        PersonalHistoryRecord(
          normalizedContent: '星巴克',
          semanticKey: 'expense.food.dinner',
          hitCount: 4,
          correctionCount: 0,
          lastUsedAt: now.millisecondsSinceEpoch,
        ),
      ],
    );

    expect(result.semanticKey, 'expense.food.dinner');
    expect(
      result.evidence.map((item) => item.source),
      contains(RecognitionEvidenceSource.personalHistory),
    );
  });

  test(
    'unknown category can still retain independently inferred expense type',
    () {
      final result = recognizeForTest('老王 88');

      expect(result.draft.type, RecognitionTransactionType.expense);
      expect(result.semanticKey, isNull);
      expect(result.resultStatus, RecognitionResultStatus.partial);
    },
  );

  test('strong category conflicts cannot be high confidence', () {
    final result = recognizeForTest('酒店火车票 100');

    expect(result.confidence, lessThan(0.8));
  });
}

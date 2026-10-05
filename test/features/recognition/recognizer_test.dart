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

  test('meal scenes use daypart without reclassifying beverage merchants', () {
    expect(recognizeForTest('中午在园区食堂吃饭 16').semanticKey, 'expense.food.lunch');
    expect(recognizeForTest('今早星巴克 28').semanticKey, 'expense.food.drink');
  });

  test('a transaction clock gives only warning-level meal context', () {
    final result = recognizeForTest('麦当劳 2026-10-05 12:18:32 实付30');

    expect(result.semanticKey, 'expense.food.lunch');
    expect(result.confirmationLevel, ConfirmationLevel.warning);
  });

  test('attached amount does not prevent latin or Chinese entity matching', () {
    final latin = recognizeForTest('kfc15');
    final chinese = recognizeForTest('麦当劳25');

    expect(latin.draft.amountMinor, 1500);
    expect(latin.semanticKey, 'expense.food.other');
    expect(chinese.draft.amountMinor, 2500);
    expect(chinese.semanticKey, 'expense.food.other');
  });

  test(
    'short exact aliases remain matchable before common attached labels',
    () {
      final member = recognizeForTest('KFC会员 15');
      final package = recognizeForTest('KFC套餐 25');
      final order = recognizeForTest('KFC订单A123 35');

      for (final result in [member, package, order]) {
        expect(
          result.evidence.where(
            (item) =>
                item.source == RecognitionEvidenceSource.entityKnowledge &&
                item.description.contains('肯德基'),
          ),
          isNotEmpty,
        );
      }
    },
  );

  test('platform is removed when a specific product remains', () {
    final result = recognizeForTest('淘宝 iPhone手机壳 49.9');

    expect(result.draft.content, 'iPhone手机壳');
    expect(result.semanticKey, 'expense.digital.accessory');
  });

  test('modifier plus action produces specific pet and vehicle semantics', () {
    expect(recognizeForTest('宠物美容 80').semanticKey, 'expense.pets.grooming');
    expect(
      recognizeForTest('车辆保养 600').semanticKey,
      'expense.transport.maintenance',
    );
    expect(recognizeForTest('猫咪医院绝育 800').semanticKey, 'expense.pets.medical');
  });

  test(
    'data-driven composition prefers a nearby action over a bare object',
    () {
      expect(
        recognizeForTest('空调加氟 200').semanticKey,
        'expense.housing.repair',
      );
      expect(
        recognizeForTest('相机清灰 150').semanticKey,
        'expense.digital.repair',
      );
      expect(
        recognizeForTest('羽绒服干洗 80').semanticKey,
        'expense.daily.cleaning',
      );
      expect(recognizeForTest('鞋子补底 35').semanticKey, 'expense.daily.service');
      expect(
        recognizeForTest('孩子看病 100').semanticKey,
        'expense.medical.clinic',
      );
    },
  );

  test('longer containing lexicon span suppresses an internal substring', () {
    final result = recognizeForTest('电动车 2999');

    expect(result.semanticKey, isNot('expense.transport.rail'));
    expect(
      result.evidence.where(
        (item) =>
            item.semanticKey == 'expense.transport.rail' &&
            item.matchedText == '动车',
      ),
      isEmpty,
    );
  });

  test('eye clinic language follows the oral and eye taxonomy boundary', () {
    expect(recognizeForTest('眼科门诊验光 70').semanticKey, 'expense.medical.dental');
  });

  test('warning retains top prediction and remains manually confirmable', () {
    final result = recognizeForTest('淘宝 49');

    expect(result.semanticKey, 'expense.shopping.other');
    expect(result.subcategoryId, isNotNull);
    expect(result.confirmationLevel, ConfirmationLevel.warning);
    expect(result.canQuickConfirm, isTrue);
  });

  test('recoverable amount ambiguity retains the top amount', () {
    final result = recognizeForTest('麦当劳 26元 30元');

    expect(result.draft.amountMinor, 3000);
    expect(
      result.issueCodes,
      contains(RecognitionIssueCode.ambiguousAmount),
      reason: result.amountCandidates
          .map((item) => '${item.raw}:${item.role.name}:${item.score}')
          .join(', '),
    );
    expect(result.confirmationLevel, ConfirmationLevel.warning);
    expect(result.canQuickConfirm, isTrue);
  });

  test(
    'failed transaction is blocked while extracted fields remain visible',
    () {
      final result = recognizeForTest('支付失败 麦当劳 25');

      expect(result.draft.amountMinor, 2500);
      expect(result.draft.content, isNotNull);
      expect(result.semanticKey, 'expense.food.other');
      expect(result.confirmationLevel, ConfirmationLevel.blocked);
      expect(result.canQuickConfirm, isFalse);
    },
  );

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
      expect(result.semanticKey, 'expense.other.general');
      expect(result.resultStatus, RecognitionResultStatus.complete);
      expect(result.confirmationLevel, ConfirmationLevel.warning);
    },
  );

  test('strong category conflicts cannot be high confidence', () {
    final result = recognizeForTest('酒店火车票 100');

    expect(result.confidence, lessThan(0.8));
  });
}

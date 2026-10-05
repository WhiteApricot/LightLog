import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/context_evidence.dart';
import 'package:light_log/features/recognition/domain/knowledge_models.dart';
import 'package:light_log/features/recognition/domain/ngram_classifier.dart';
import 'package:light_log/features/recognition/domain/ngram_model.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/recognizer.dart';

import 'recognition_test_fixture.dart';

void main() {
  test('meal windows cover every hour and all minute boundaries', () {
    for (final (hour, expected) in [
      (0, 'dinner'),
      (4, 'dinner'),
      (5, 'breakfast'),
      (9, 'breakfast'),
      (10, 'lunch'),
      (16, 'lunch'),
      (17, 'dinner'),
      (23, 'dinner'),
    ]) {
      for (final minute in [0, 59]) {
        final result = recognizeForTest(
          '牛肉面 23元',
          now: DateTime(2026, 2, 9, hour, minute),
        );
        expect(result.semanticKey, 'expense.food.$expected');
        expect(result.draft.occurredAtLocal!.hour, hour);
        expect(result.fieldConfidence.category, lessThan(.80));
      }
    }
    for (var hour = 0; hour < 24; hour++) {
      expect(
        ContextEvidenceBuilder.mealForHour(hour),
        isIn(ContextEvidenceBuilder.mealSemantics),
      );
    }
  });
  test('clear main dishes route by local occurrence, not model daypart', () {
    for (final dish in ['牛肉面', '炒饭', '汉堡', '火锅']) {
      final result = recognizeForTest(
        '$dish 23元',
        now: DateTime(2026, 2, 9, 18, 40),
      );
      expect(result.semanticKey, 'expense.food.dinner', reason: dish);
      expect(
        result.evidence.any((e) => e.family == 'mealByOccurredAt'),
        isTrue,
      );
    }
  });
  test('explicit text time and meal names outrank injected device time', () {
    for (final (text, expected) in [
      ('中午点外卖盖饭 23元', 'lunch'),
      ('晚上外卖炒粉 23元', 'dinner'),
      ('07:20 汉堡 23元', 'breakfast'),
      ('晚上7点炒饭 23元', 'dinner'),
      ('午间牛肉面 23元', 'lunch'),
      ('中饭牛肉面 23元', 'lunch'),
      ('晚间7点炒饭 23元', 'dinner'),
      ('清晨火锅 23元', 'breakfast'),
      ('晚餐火锅 23元', 'dinner'),
      ('午饭炒饭奶茶 23元', 'lunch'),
    ]) {
      final result = recognizeForTest(text, now: DateTime(2026, 2, 9, 8));
      expect(result.semanticKey, 'expense.food.$expected', reason: text);
      expect(
        result.evidence.any((e) => e.family == 'mealByExplicitTime'),
        isTrue,
      );
      expect(result.confirmationLevel, isNot(ConfirmationLevel.confident));
    }
    final dateOnly = recognizeForTest(
      '2026-02-08 牛肉面 23元',
      now: DateTime(2026, 2, 9, 18),
    );
    expect(dateOnly.semanticKey, 'expense.food.dinner');
    expect(
      dateOnly.evidence.any((e) => e.family == 'mealByOccurredAt'),
      isTrue,
    );
  });
  test('channel, drinks, snacks and ingredients do not imply main meals', () {
    for (final (text, expected) in [
      ('晚上外卖奶茶 23元', 'expense.food.drink'),
      ('中午外卖零食 23元', 'expense.food.snack'),
      ('食堂奶茶 23元', 'expense.food.drink'),
      ('下午吃了零食 23元', 'expense.food.snack'),
      ('晚上超市买大米 23元', 'expense.food.groceries'),
    ]) {
      final result = recognizeForTest(text, now: DateTime(2026, 2, 9, 12));
      expect(result.semanticKey, expected, reason: text);
      expect(
        result.evidence.any((e) => e.family?.startsWith('mealBy') ?? false),
        isFalse,
      );
    }
    expect(
      recognizeForTest('外卖 23元').evidence
          .any((e) => e.family?.startsWith('mealBy') ?? false),
      isFalse,
    );
  });

  final emptyKnowledge = KnowledgeCatalog(
    entities: const [],
    lexicon: const [],
  );
  final emptyRecognizer = LocalRecognizer(knowledge: emptyKnowledge);
  RecognitionResult recognize(
    String text, {
    LocalRecognizer? recognizer,
    List<RecognitionCategory>? categories,
  }) => (recognizer ?? emptyRecognizer).recognize(
    RecognitionInput(
      rawText: text,
      nowLocal: DateTime(2026, 2, 9, 12),
      timezoneOffsetMinutes: 480,
      activeCategories: categories ?? testRecognitionCategories,
    ),
  );
  test('ordinary expense and explicit income resolve general with warning', () {
    for (final (text, key) in [
      ('锆岫 23元', 'expense.other.general'),
      ('收款 锆岫 23元', 'income.other.general'),
    ]) {
      final result = recognize(text);
      expect(result.semanticKey, key);
      expect(
        result.evidence.any((e) => e.family == 'otherGeneralFallback'),
        isTrue,
      );
      expect(result.hasRequiredFields, isTrue);
      expect(result.confirmationLevel, ConfirmationLevel.warning);
      expect(result.fieldConfidence.category, .55);
      expect(result.canQuickConfirm, isTrue);
    }
  });
  test(
    'unmapped semantic resolves general but unavailable general stays missing',
    () {
      final unmapped = LocalRecognizer(
        knowledge: KnowledgeCatalog(
          entities: const [],
          lexicon: const [
            LexiconKnowledge(
              term: '锆岫',
              semanticKey: 'expense.synthetic.unmapped',
              score: .94,
              negativeTerms: [],
              role: EvidenceRole.product,
              specificity: EvidenceSpecificity.specific,
            ),
          ],
        ),
      );
      final result = recognize('锆岫 23元', recognizer: unmapped);
      expect(result.semanticKey, 'expense.other.general');
      expect(
        result.issueCodes,
        isNot(contains(RecognitionIssueCode.categoryMappingMissing)),
      );
      final missing = recognize('锆岫 23元', recognizer: unmapped, categories: []);
      expect(missing.categoryId, isNull);
      expect(
        missing.issueCodes,
        contains(RecognitionIssueCode.categoryMappingMissing),
      );
      expect(missing.canQuickConfirm, isFalse);
    },
  );
  test('fallback does not change required danger blocking', () {
    for (final text in [
      '支付失败 锆岫 23元',
      '交易取消 锆岫 23元',
      '账户余额 23元',
      '退款成功 锆岫 23元',
      '锆岫',
      '',
      '锆岫 0元',
      '支付成功 锆岫 23元\n支付成功 钛屿 31元',
    ]) {
      final result = recognize(text);
      expect(result.confirmationLevel, ConfirmationLevel.blocked, reason: text);
      expect(result.canQuickConfirm, isFalse);
      expect(
        result.evidence.any((e) => e.family == 'otherGeneralFallback'),
        isFalse,
      );
    }
  });
  test(
    'frozen classifier cannot supply a daypart without definite meal evidence',
    () {
      final header = utf8.encode(
        jsonEncode({
          'version': 1,
          'normalization': 'ascii-cjk-space-v1',
          'grams': [2, 3],
          'labels': ['expense.food.lunch', 'expense.digital.phone'],
          'vocabulary': ['锆岫'],
          'scales': [1, 1],
          'bias': [0, 0],
          'threshold': .6,
          'margin': .15,
        }),
      );
      final bytes = Uint8List(8 + header.length + 2);
      bytes.setRange(0, 4, ascii.encode('LLNG'));
      ByteData.sublistView(bytes).setUint32(4, header.length, Endian.little);
      bytes.setRange(8, 8 + header.length, header);
      bytes[bytes.length - 2] = 10;
      final classifier = NgramClassifier(NgramModel.decode(bytes));
      expect(classifier.evidence('锆岫 23元')!.semanticKey, 'expense.food.lunch');
      final result = recognize(
        '锆岫 23元',
        recognizer: LocalRecognizer(
          knowledge: emptyKnowledge,
          ngram: classifier,
        ),
      );
      expect(result.semanticKey, 'expense.other.general');
      expect(result.confirmationLevel, ConfirmationLevel.warning);
    },
  );
}

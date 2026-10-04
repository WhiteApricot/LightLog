import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';
import 'package:light_log/features/recognition/domain/knowledge_catalog.dart';
import 'package:light_log/features/recognition/domain/personal_history.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/text_entry_parser.dart';

void main() {
  final parser = TextEntryParser(
    knowledge: KnowledgeCatalog.fromJsonStrings(
      merchantsJson: File('assets/knowledge/merchants.json').readAsStringSync(),
      lexiconJson: File('assets/knowledge/category_lexicon.json')
          .readAsStringSync(),
    ),
  );
  final categories = [
    for (final seed in defaultCategories)
      Category(
        id: seed.id,
        parentId: seed.parentId,
        name: seed.name,
        type: seed.type,
        iconAsset: seed.iconAsset,
        sortOrder: seed.sortOrder,
        isActive: true,
        semanticKey: seed.semanticKey,
        isSystem: true,
        createdAt: 0,
        updatedAt: 0,
      ),
  ];
  final now = DateTime(2026, 10, 4, 12, 30);

  test('parses canteen expense and derives lunch from wall-clock hour', () {
    final result = parser.parse(
      rawText: '二食堂 15',
      categories: categories,
      now: now,
    );

    expect(result.isComplete, isTrue);
    expect(result.draft.type, LedgerTransactionType.expense);
    expect(result.draft.amountMinor, 1500);
    expect(result.draft.content, '二食堂');
    expect(result.categoryName, '餐饮');
    expect(result.subcategoryName, '午餐');
    expect(result.confidence, closeTo(0.68, 0.001));
  });

  test('parses adjacent decimal amount and drink keyword', () {
    final result = parser.parse(
      rawText: '星巴克32',
      categories: categories,
      now: now,
    );

    expect(result.draft.amountMinor, 3200);
    expect(result.draft.content, '星巴克');
    expect(result.subcategoryName, '饮品');

    final taxi = parser.parse(
      rawText: '打车 19.8',
      categories: categories,
      now: now,
    );
    expect(taxi.draft.amountMinor, 1980);
    expect(taxi.categoryName, '交通');
    expect(taxi.subcategoryName, '打车');
  });

  test('plus sign and salary keyword produce an income candidate', () {
    final result = parser.parse(
      rawText: '工资 +5000',
      categories: categories,
      now: now,
    );

    expect(result.draft.type, LedgerTransactionType.income);
    expect(result.draft.amountMinor, 500000);
    expect(result.categoryName, '工资奖金');
    expect(result.subcategoryName, '基本工资');
    final transactionDraft = result.toTransactionDraft(
      accountId: 'account-bank-card',
    );
    expect(transactionDraft.source, 'text');
    expect(transactionDraft.confidence, result.confidence);
  });

  test('last night resolves to previous wall-clock day at 20:00', () {
    final result = parser.parse(
      rawText: '昨晚麦当劳 28',
      categories: categories,
      now: now,
    );

    expect(result.draft.occurredAtLocal, DateTime(2026, 10, 3, 20));
    expect(result.draft.content, '麦当劳');
    expect(result.subcategoryName, '其他餐饮');
    expect(result.evidence.map((item) => item.field), contains('time'));
  });

  test('explicit clock overrides a relative period default', () {
    final result = parser.parse(
      rawText: '昨晚 21:35 麦当劳 28',
      categories: categories,
      now: now,
    );

    expect(result.draft.occurredAtLocal, DateTime(2026, 10, 3, 21, 35));
    expect(result.draft.amountMinor, 2800);
  });

  test('normalizes full-width input and whitespace', () {
    expect(TextEntryParser.normalize('  星巴克　３２．５  '), '星巴克 32.5');
    final result = parser.parse(
      rawText: '  星巴克　３２．５  ',
      categories: categories,
      now: now,
    );
    expect(result.draft.amountMinor, 3250);
  });

  test('incomplete or ambiguous amounts stay as editable candidates', () {
    final missing = parser.parse(
      rawText: '二食堂',
      categories: categories,
      now: now,
    );
    final multiple = parser.parse(
      rawText: '早餐 10 午餐 20',
      categories: categories,
      now: now,
    );

    expect(missing.isComplete, isFalse);
    expect(missing.issues, contains('未识别到金额'));
    expect(multiple.isComplete, isFalse);
    expect(multiple.issues, contains('识别到多个金额，请手动确认'));
  });

  test('known brands, aliases and store suffixes use merchant knowledge', () {
    final cases = {
      '汉堡王 32': '其他餐饮',
      '瑞幸咖啡 19.9': '饮品',
      'STARBUCKS（国贸店） 28': '饮品',
      '滴滴 21': '打车',
    };
    for (final entry in cases.entries) {
      final result = parser.parse(
        rawText: entry.key,
        categories: categories,
        now: now,
      );
      expect(result.isComplete, isTrue, reason: entry.key);
      expect(result.subcategoryName, entry.value, reason: entry.key);
      expect(
        result.evidence.map((item) => item.source),
        contains(RecognitionEvidenceSource.merchantKnowledge),
      );
    }
  });

  test('unknown merchants use category lexicon without inventing a brand', () {
    final hotpot = parser.parse(
      rawText: '老王火锅 88',
      categories: categories,
      now: now,
    );
    final pharmacy = parser.parse(
      rawText: '幸福大药房 36',
      categories: categories,
      now: now,
    );

    expect(hotpot.draft.content, '老王火锅');
    expect(hotpot.categoryName, '餐饮');
    expect(hotpot.subcategoryName, '其他餐饮');
    expect(pharmacy.categoryName, '医疗');
    expect(pharmacy.subcategoryName, '药品');
  });

  test('personal history overrides general merchant knowledge', () {
    final result = parser.parse(
      rawText: '星巴克 28',
      categories: categories,
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

    expect(result.subcategoryName, '晚餐');
    expect(result.confidence, greaterThan(0.90));
    expect(
      result.evidence.map((item) => item.source),
      contains(RecognitionEvidenceSource.personalHistory),
    );
  });

  test(
    'conflicting lexicon evidence lowers confidence and remains reviewable',
    () {
      final result = parser.parse(
        rawText: '酒店火车票 100',
        categories: categories,
        now: now,
      );

      expect(result.isComplete, isTrue);
      expect(result.confidence, lessThanOrEqualTo(0.55));
      expect(result.issues, contains('分类证据冲突，请确认分类'));
    },
  );

  test(
    'insufficient evidence remains uncertain instead of forcing category',
    () {
      final result = parser.parse(
        rawText: '老王 88',
        categories: categories,
        now: now,
      );

      expect(result.isComplete, isFalse);
      expect(result.semanticKey, isNull);
      expect(result.issues, contains('无法可靠判断分类'));
    },
  );

  test(
    'ordinary parsing remains far below half a second at repeated scale',
    () {
      parser.parse(rawText: '瑞幸咖啡 19.9', categories: categories, now: now);
      final stopwatch = Stopwatch()..start();
      for (var index = 0; index < 500; index++) {
        final result = parser.parse(
          rawText: '上周五中午麦当劳 25',
          categories: categories,
          now: now,
        );
        expect(result.isComplete, isTrue);
      }
      stopwatch.stop();

      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: '500 次解析耗时 ${stopwatch.elapsedMilliseconds}ms',
      );
    },
  );
}

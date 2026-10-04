import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/domain/knowledge_catalog.dart';
import 'package:light_log/features/recognition/domain/text_entry_parser.dart';

void main() {
  test('10,000 representative local parses stay below 0.5 seconds each', () {
    final knowledge = KnowledgeCatalog.fromJsonStrings(
      merchantsJson: File('assets/knowledge/merchants.json').readAsStringSync(),
      lexiconJson: File('assets/knowledge/category_lexicon.json')
          .readAsStringSync(),
    );
    final parser = TextEntryParser(knowledge: knowledge);
    final categories = [
      for (final seed in defaultCategories)
        Category(
          id: seed.id,
          parentId: seed.parentId,
          name: seed.name,
          type: seed.type,
          iconAsset: seed.iconAsset,
          semanticKey: seed.semanticKey,
          isSystem: true,
          sortOrder: seed.sortOrder,
          isActive: true,
          createdAt: 0,
          updatedAt: 0,
        ),
    ];
    final inputs = [
      '汉堡王 32',
      '瑞幸咖啡 19.9',
      '老王火锅 88',
      '上周五中午麦当劳 25',
      '幸福大药房 36',
    ];
    final now = DateTime(2026, 10, 4, 12, 30);
    for (final input in inputs) {
      parser.parse(rawText: input, categories: categories, now: now);
    }

    const iterations = 10000;
    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < iterations; index++) {
      parser.parse(
        rawText: inputs[index % inputs.length],
        categories: categories,
        now: now,
      );
    }
    stopwatch.stop();
    final microsecondsPerParse =
        stopwatch.elapsedMicroseconds / iterations.toDouble();
    // ignore: avoid_print
    print(
      '$iterations parses in ${stopwatch.elapsedMilliseconds} ms; '
      '${microsecondsPerParse.toStringAsFixed(1)} µs/parse',
    );
    expect(microsecondsPerParse, lessThan(500000));
  });
}

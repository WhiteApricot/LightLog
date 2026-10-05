import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/data/knowledge_decoder.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/recognizer.dart';

final testRecognizer = LocalRecognizer(
  knowledge: const KnowledgeDecoder().decode(
    entitiesJson: File('assets/knowledge/merchants.json').readAsStringSync(),
    lexiconJson: File('assets/knowledge/category_lexicon.json')
        .readAsStringSync(),
    lexicalFamiliesJson: File('assets/knowledge/lexical_families.json')
        .readAsStringSync(),
    compositionRulesJson: File('assets/knowledge/composition_rules.json')
        .readAsStringSync(),
  ),
);

final testRecognitionCategories = [
  for (final seed in defaultCategories)
    RecognitionCategory(
      id: seed.id,
      parentId: seed.parentId,
      name: seed.name,
      type: RecognitionTransactionType.values.firstWhere(
        (type) => type.value == seed.type,
      ),
      semanticKey: seed.semanticKey,
      isSystem: true,
      sortOrder: seed.sortOrder,
      isActive: true,
    ),
];

RecognitionResult recognizeForTest(
  String rawText, {
  DateTime? now,
  List<PersonalHistoryRecord> history = const [],
}) {
  final localNow = now ?? DateTime(2026, 10, 4, 12, 30);
  return testRecognizer.recognize(
    RecognitionInput(
      rawText: rawText,
      nowLocal: localNow,
      timezoneOffsetMinutes: localNow.timeZoneOffset.inMinutes,
      activeCategories: testRecognitionCategories,
      personalHistory: history,
    ),
  );
}

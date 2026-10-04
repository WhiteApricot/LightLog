import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/data/knowledge_decoder.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/recognizer.dart';

class RecognitionToolHarness {
  RecognitionToolHarness()
    : recognizer = LocalRecognizer(
        knowledge: const KnowledgeDecoder().decode(
          entitiesJson: File('assets/knowledge/merchants.json')
              .readAsStringSync(),
          lexiconJson: File('assets/knowledge/category_lexicon.json')
              .readAsStringSync(),
        ),
      );

  final LocalRecognizer recognizer;

  static final categories = [
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

  RecognitionResult recognize(
    String rawText, {
    required DateTime now,
    List<PersonalHistoryRecord> history = const [],
  }) => recognizer.recognize(
    RecognitionInput(
      rawText: rawText,
      nowLocal: now,
      timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
      activeCategories: categories,
      personalHistory: history,
    ),
  );
}

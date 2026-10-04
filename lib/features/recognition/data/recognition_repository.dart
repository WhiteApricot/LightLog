import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../data/database/database.dart';
import '../domain/normalization.dart';
import '../domain/personal_history.dart';

abstract interface class RecognitionRepository {
  Future<List<PersonalHistoryRecord>> loadHistory();

  Future<void> recordFeedback({
    required String normalizedContent,
    required String? predictedSemanticKey,
    required String finalCategoryId,
  });
}

class LocalRecognitionRepository implements RecognitionRepository {
  LocalRecognitionRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  @override
  Future<List<PersonalHistoryRecord>> loadHistory() async {
    final rows = await (_database.select(
      _database.recognitionRules,
    )..orderBy([(table) => OrderingTerm.desc(table.lastUsedAt)])).get();
    return [
      for (final row in rows)
        PersonalHistoryRecord(
          normalizedContent: row.normalizedContent,
          semanticKey: row.semanticKey,
          hitCount: row.hitCount,
          correctionCount: row.correctionCount,
          lastUsedAt: row.lastUsedAt,
        ),
    ];
  }

  @override
  Future<void> recordFeedback({
    required String normalizedContent,
    required String? predictedSemanticKey,
    required String finalCategoryId,
  }) async {
    final key = RecognitionNormalizer.indexKey(normalizedContent);
    if (key.isEmpty) return;
    final category = await (_database.select(
      _database.categories,
    )..where((table) => table.id.equals(finalCategoryId))).getSingleOrNull();
    final finalSemanticKey = category?.semanticKey;
    if (finalSemanticKey == null || finalSemanticKey.isEmpty) return;
    await _database.transaction(() async {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      if (predictedSemanticKey != null &&
          predictedSemanticKey != finalSemanticKey) {
        await _increment(
          normalizedContent: key,
          semanticKey: predictedSemanticKey,
          now: now,
          correction: true,
        );
      }
      await _increment(
        normalizedContent: key,
        semanticKey: finalSemanticKey,
        now: now,
        correction: false,
      );
    });
  }

  Future<void> _increment({
    required String normalizedContent,
    required String semanticKey,
    required int now,
    required bool correction,
  }) async {
    final existing =
        await (_database.select(_database.recognitionRules)..where(
              (table) =>
                  table.normalizedContent.equals(normalizedContent) &
                  table.semanticKey.equals(semanticKey),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await _database
          .into(_database.recognitionRules)
          .insert(
            RecognitionRulesCompanion.insert(
              id: _uuid.v4(),
              normalizedContent: normalizedContent,
              semanticKey: semanticKey,
              hitCount: Value(correction ? 0 : 1),
              correctionCount: Value(correction ? 1 : 0),
              lastUsedAt: now,
              createdAt: now,
              updatedAt: now,
            ),
          );
      return;
    }
    await (_database.update(
      _database.recognitionRules,
    )..where((table) => table.id.equals(existing.id))).write(
      RecognitionRulesCompanion(
        hitCount: Value(existing.hitCount + (correction ? 0 : 1)),
        correctionCount: Value(existing.correctionCount + (correction ? 1 : 0)),
        lastUsedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }
}

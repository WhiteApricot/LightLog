import '../../../data/database/database.dart';
import '../data/recognition_repository.dart';
import '../domain/recognition_models.dart';
import '../domain/recognizer.dart';

class RecognitionCoordinator {
  const RecognitionCoordinator(this._recognizer, this._repository);

  final LocalRecognizer _recognizer;
  final RecognitionRepository _repository;

  Future<RecognitionResult> recognize({
    required String rawText,
    required List<Category> categories,
    required DateTime now,
  }) async {
    final key = _recognizer.historyLookupKey(rawText);
    final history = await _repository.loadHistoryForKey(key);
    return _recognizer.recognize(
      RecognitionInput(
        rawText: rawText,
        nowLocal: now,
        timezoneOffsetMinutes: now.timeZoneOffset.inMinutes,
        activeCategories: categories.map(_category).toList(growable: false),
        personalHistory: history,
      ),
    );
  }

  Future<void> recordFeedback({
    required RecognitionResult candidate,
    required String finalCategoryId,
    DateTime? now,
  }) {
    return _repository.recordFeedback(
      normalizedContent:
          candidate.draft.normalizedMerchant ?? candidate.draft.content ?? '',
      predictedSemanticKey: candidate.semanticKey,
      finalCategoryId: finalCategoryId,
      recordedAtUtcMilliseconds: (now ?? DateTime.now())
          .toUtc()
          .millisecondsSinceEpoch,
    );
  }

  static RecognitionCategory _category(Category category) =>
      RecognitionCategory(
        id: category.id,
        parentId: category.parentId,
        name: category.name,
        type: RecognitionTransactionType.values.firstWhere(
          (type) => type.value == category.type,
        ),
        semanticKey: category.semanticKey,
        isSystem: category.isSystem,
        sortOrder: category.sortOrder,
        isActive: category.isActive,
      );
}

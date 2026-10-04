import '../../ledger/domain/ledger_models.dart';

class EntryDraft {
  const EntryDraft({
    required this.rawText,
    required this.normalizedText,
    this.type,
    this.amountMinor,
    this.content,
    this.occurredAtLocal,
    this.timezoneOffsetMinutes,
  });

  final String rawText;
  final String normalizedText;
  final LedgerTransactionType? type;
  final int? amountMinor;
  final String? content;
  final DateTime? occurredAtLocal;
  final int? timezoneOffsetMinutes;
}

class RecognitionEvidence {
  const RecognitionEvidence({
    required this.field,
    required this.description,
    required this.weight,
  });

  final String field;
  final String description;
  final double weight;
}

class RecognitionCandidate {
  const RecognitionCandidate({
    required this.draft,
    required this.categoryId,
    required this.subcategoryId,
    required this.categoryName,
    required this.subcategoryName,
    required this.evidence,
    required this.issues,
  });

  final EntryDraft draft;
  final String? categoryId;
  final String? subcategoryId;
  final String? categoryName;
  final String? subcategoryName;
  final List<RecognitionEvidence> evidence;
  final List<String> issues;

  double get confidence => evidence
      .fold<double>(0, (total, item) => total + item.weight)
      .clamp(0, 1);

  bool get isComplete =>
      draft.type != null &&
      draft.amountMinor != null &&
      draft.content != null &&
      draft.occurredAtLocal != null &&
      draft.timezoneOffsetMinutes != null &&
      categoryId != null &&
      subcategoryId != null &&
      issues.isEmpty;

  TransactionDraft toTransactionDraft({required String accountId}) {
    if (!isComplete) {
      throw StateError('识别候选不完整，不能写入账本');
    }
    return TransactionDraft(
      type: draft.type!,
      categoryId: categoryId!,
      subcategoryId: subcategoryId!,
      content: draft.content!,
      amountMinor: draft.amountMinor!,
      occurredAtLocal: draft.occurredAtLocal!,
      timezoneOffsetMinutes: draft.timezoneOffsetMinutes!,
      accountId: accountId,
      source: 'text',
      confidence: confidence,
    );
  }
}

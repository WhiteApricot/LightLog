import '../../ledger/domain/ledger_models.dart';

class EntryDraft {
  const EntryDraft({
    required this.rawText,
    required this.normalizedText,
    this.type,
    this.amountMinor,
    this.content,
    this.normalizedContent,
    this.normalizedMerchant,
    this.occurredAtLocal,
    this.timezoneOffsetMinutes,
  });

  final String rawText;
  final String normalizedText;
  final LedgerTransactionType? type;
  final int? amountMinor;
  final String? content;
  final String? normalizedContent;
  final String? normalizedMerchant;
  final DateTime? occurredAtLocal;
  final int? timezoneOffsetMinutes;
}

enum RecognitionEvidenceSource {
  parser,
  personalHistory,
  merchantKnowledge,
  categoryLexicon,
  ngram,
  context,
}

class RecognitionEvidence {
  const RecognitionEvidence({
    required this.field,
    required this.description,
    required this.score,
    this.source = RecognitionEvidenceSource.parser,
    this.semanticKey,
    this.negative = false,
  });

  final String field;
  final String description;
  final double score;
  final RecognitionEvidenceSource source;
  final String? semanticKey;
  final bool negative;

  double get weight => score;
}

class RecognitionCandidate {
  const RecognitionCandidate({
    required this.draft,
    required this.categoryId,
    required this.subcategoryId,
    required this.categoryName,
    required this.subcategoryName,
    required this.semanticKey,
    required this.confidence,
    required this.evidence,
    required this.issues,
    this.blockingIssues = const [],
  });

  final EntryDraft draft;
  final String? categoryId;
  final String? subcategoryId;
  final String? categoryName;
  final String? subcategoryName;
  final String? semanticKey;
  final List<RecognitionEvidence> evidence;
  final List<String> issues;
  final List<String> blockingIssues;
  final double confidence;

  bool get isComplete =>
      draft.type != null &&
      draft.amountMinor != null &&
      draft.content != null &&
      draft.occurredAtLocal != null &&
      draft.timezoneOffsetMinutes != null &&
      categoryId != null &&
      subcategoryId != null &&
      blockingIssues.isEmpty;

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

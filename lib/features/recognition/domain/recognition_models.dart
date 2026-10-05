enum RecognitionTransactionType {
  expense('expense'),
  income('income'),
  transfer('transfer'),
  refund('refund');

  const RecognitionTransactionType(this.value);
  final String value;
}

enum RecognitionEvidenceSource {
  parser,
  personalHistory,
  entityKnowledge,
  categoryLexicon,
  composition,
  context,
}

enum EvidenceRole {
  product,
  action,
  service,
  merchantType,
  venue,
  platform,
  context,
}

enum EvidenceSpecificity { broad, general, specific }

enum TransactionStatus {
  success,
  failed,
  cancelled,
  refund,
  nonTransaction,
  unknown,
}

enum RecognitionResultStatus { complete, partial, rejected }

enum ConfirmationLevel { confident, warning, blocked }

enum RecognitionIssueCode {
  emptyInput,
  amountUnrecognized,
  ambiguousAmount,
  contentUnrecognized,
  typeLowConfidence,
  typeConflict,
  categoryLowConfidence,
  categoryAmbiguous,
  categoryMappingMissing,
  ambiguousWeekday,
  transactionNotCompleted,
  transactionCancelled,
  noTransactionEvidence,
  relatedTransactionRequired,
  multipleTransactionsDetected,
}

enum NumericRole {
  amount,
  dateTime,
  orderId,
  quantity,
  modelVersion,
  titleNumber,
  phoneNumber,
  distanceDuration,
  other,
}

class TextSpanRange {
  const TextSpanRange({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start;
  bool containsOffset(int offset) => offset >= start && offset < end;
  bool overlaps(TextSpanRange other) => start < other.end && other.start < end;
}

class RecognizedSpan {
  const RecognizedSpan({
    required this.range,
    required this.kind,
    required this.text,
    this.protected = false,
    this.score = 1,
  });

  final TextSpanRange range;
  final String kind;
  final String text;
  final bool protected;
  final double score;
}

class RecognitionCategory {
  const RecognitionCategory({
    required this.id,
    required this.parentId,
    required this.name,
    required this.type,
    required this.semanticKey,
    required this.isSystem,
    required this.sortOrder,
    required this.isActive,
  });

  final String id;
  final String? parentId;
  final String name;
  final RecognitionTransactionType type;
  final String? semanticKey;
  final bool isSystem;
  final int sortOrder;
  final bool isActive;
}

class PersonalHistoryRecord {
  const PersonalHistoryRecord({
    required this.normalizedContent,
    required this.semanticKey,
    required this.hitCount,
    required this.correctionCount,
    required this.lastUsedAt,
  });

  final String normalizedContent;
  final String semanticKey;
  final int hitCount;
  final int correctionCount;
  final int lastUsedAt;
}

class RecognitionInput {
  const RecognitionInput({
    required this.rawText,
    required this.nowLocal,
    required this.timezoneOffsetMinutes,
    required this.activeCategories,
    this.personalHistory = const [],
  });

  final String rawText;
  final DateTime nowLocal;
  final int timezoneOffsetMinutes;
  final List<RecognitionCategory> activeCategories;
  final List<PersonalHistoryRecord> personalHistory;
}

class AmountCandidate {
  const AmountCandidate({
    required this.raw,
    required this.amountMinor,
    required this.start,
    required this.end,
    required this.score,
    required this.role,
    required this.reason,
    this.features = const [],
  });

  final String raw;
  final int? amountMinor;
  final int start;
  final int end;
  final double score;
  final NumericRole role;
  final String reason;
  final List<String> features;

  TextSpanRange get range => TextSpanRange(start: start, end: end);
}

class RecognitionEvidence {
  const RecognitionEvidence({
    required this.field,
    required this.description,
    required this.score,
    this.source = RecognitionEvidenceSource.parser,
    this.semanticKey,
    this.negative = false,
    this.role = EvidenceRole.context,
    this.specificity = EvidenceSpecificity.general,
    this.matchedText,
    this.span,
    this.family,
  });

  final String field;
  final String description;
  final double score;
  final RecognitionEvidenceSource source;
  final String? semanticKey;
  final bool negative;
  final EvidenceRole role;
  final EvidenceSpecificity specificity;
  final String? matchedText;
  final TextSpanRange? span;
  final String? family;
}

class TypeDecision {
  const TypeDecision({
    required this.type,
    required this.confidence,
    required this.evidence,
    this.hasConflict = false,
  });

  final RecognitionTransactionType? type;
  final double confidence;
  final List<RecognitionEvidence> evidence;
  final bool hasConflict;
}

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
  final RecognitionTransactionType? type;
  final int? amountMinor;
  final String? content;
  final String? normalizedContent;
  final String? normalizedMerchant;
  final DateTime? occurredAtLocal;
  final int? timezoneOffsetMinutes;
}

class FieldConfidence {
  const FieldConfidence({
    required this.amount,
    required this.type,
    required this.category,
    required this.time,
    required this.content,
  });

  final double amount;
  final double type;
  final double category;
  final double time;
  final double content;
}

class RecognitionResult {
  const RecognitionResult({
    required this.draft,
    required this.categoryId,
    required this.subcategoryId,
    required this.categoryName,
    required this.subcategoryName,
    required this.semanticKey,
    required this.confidence,
    required this.fieldConfidence,
    required this.evidence,
    required this.issueCodes,
    required this.issues,
    this.status = TransactionStatus.unknown,
    this.amountCandidates = const [],
    this.spans = const [],
    this.multipleTransactionsDetected = false,
  });

  final EntryDraft draft;
  final String? categoryId;
  final String? subcategoryId;
  final String? categoryName;
  final String? subcategoryName;
  final String? semanticKey;
  final List<RecognitionEvidence> evidence;
  final Set<RecognitionIssueCode> issueCodes;
  final List<String> issues;
  final double confidence;
  final FieldConfidence fieldConfidence;
  final TransactionStatus status;
  final List<AmountCandidate> amountCandidates;
  final List<RecognizedSpan> spans;
  final bool multipleTransactionsDetected;

  List<String> get blockingIssues => [
    for (final code in issueCodes)
      if (_blockingIssueCodes.contains(code)) issueMessage(code),
  ];

  ConfirmationLevel get confirmationLevel {
    if (issueCodes.any(_dangerousIssueCodes.contains)) {
      return ConfirmationLevel.blocked;
    }
    if (issueCodes.isNotEmpty || confidence < 0.80 || !hasRequiredFields) {
      return ConfirmationLevel.warning;
    }
    return ConfirmationLevel.confident;
  }

  bool get hasRequiredFields =>
      draft.type != null &&
      draft.amountMinor != null &&
      draft.content != null &&
      draft.occurredAtLocal != null &&
      draft.timezoneOffsetMinutes != null &&
      categoryId != null &&
      subcategoryId != null;

  bool get canQuickConfirm =>
      confirmationLevel != ConfirmationLevel.blocked && hasRequiredFields;

  RecognitionResultStatus get resultStatus {
    if (confirmationLevel == ConfirmationLevel.blocked) {
      return RecognitionResultStatus.rejected;
    }
    return hasRequiredFields
        ? RecognitionResultStatus.complete
        : RecognitionResultStatus.partial;
  }

  bool get isComplete => hasRequiredFields;

  static const _dangerousIssueCodes = {
    RecognitionIssueCode.emptyInput,
    RecognitionIssueCode.amountUnrecognized,
    RecognitionIssueCode.transactionNotCompleted,
    RecognitionIssueCode.transactionCancelled,
    RecognitionIssueCode.noTransactionEvidence,
    RecognitionIssueCode.relatedTransactionRequired,
    RecognitionIssueCode.multipleTransactionsDetected,
  };

  static const _blockingIssueCodes = {..._dangerousIssueCodes};

  static String issueMessage(RecognitionIssueCode code) => switch (code) {
    RecognitionIssueCode.emptyInput => '请输入要识别的账目内容',
    RecognitionIssueCode.amountUnrecognized => '未识别到金额',
    RecognitionIssueCode.ambiguousAmount => '识别到多个金额，请手动确认',
    RecognitionIssueCode.contentUnrecognized => '未识别到内容或商户',
    RecognitionIssueCode.typeLowConfidence => '无法可靠判断账务类型',
    RecognitionIssueCode.typeConflict => '账务类型证据冲突，请确认',
    RecognitionIssueCode.categoryLowConfidence => '无法可靠判断分类',
    RecognitionIssueCode.categoryAmbiguous => '分类证据冲突，请确认分类',
    RecognitionIssueCode.categoryMappingMissing => '当前分类中没有可用语义映射',
    RecognitionIssueCode.ambiguousWeekday => '未指定“本周”或“上周”，请确认具体日期',
    RecognitionIssueCode.transactionNotCompleted => '当前文本不是已完成交易',
    RecognitionIssueCode.transactionCancelled => '交易已取消，不能入账',
    RecognitionIssueCode.noTransactionEvidence => '当前文本不是可入账交易',
    RecognitionIssueCode.relatedTransactionRequired => '退款候选必须关联原账目后才能保存',
    RecognitionIssueCode.multipleTransactionsDetected => '检测到多笔独立交易，不能合并入账',
  };
}

typedef RecognitionCandidate = RecognitionResult;

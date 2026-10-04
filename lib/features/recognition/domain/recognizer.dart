import 'category_resolver.dart';
import 'confidence_calibrator.dart';
import 'context_evidence.dart';
import 'entity_matcher.dart';
import 'evidence_fusion.dart';
import 'field_extractor.dart';
import 'knowledge_models.dart';
import 'lexicon_matcher.dart';
import 'normalization.dart';
import 'personal_history.dart';
import 'recognition_models.dart';
import 'type_inference.dart';

abstract interface class Recognizer {
  RecognitionResult recognize(RecognitionInput input);
}

class LocalRecognizer implements Recognizer {
  LocalRecognizer({required KnowledgeCatalog knowledge})
    : _entityMatcher = EntityMatcher(knowledge),
      _lexiconMatcher = LexiconMatcher(knowledge);

  final EntityMatcher _entityMatcher;
  final LexiconMatcher _lexiconMatcher;
  static const _normalizer = RecognitionNormalizer();
  static const _fieldExtractor = FieldExtractor();
  static const _typeInference = TypeInference();
  static const _historyMatcher = PersonalHistoryMatcher();
  static const _contextBuilder = ContextEvidenceBuilder();
  static const _fusion = EvidenceFusion();
  static const _resolver = CategoryResolver();
  static const _calibrator = ConfidenceCalibrator();

  String historyLookupKey(String rawText) {
    final display = RecognitionNormalizer.normalizeDisplay(rawText);
    final withoutFields = display
        .replaceAll(
          RegExp(
            r'(?:订单号|交易号|商户单号|流水号)\s*[:：]?\s*[a-z0-9_-]{6,}',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(
          RegExp(r'(?:￥|¥)?\s*[+-]?\d+(?:\.\d{1,2})?\s*(?:元|块)?\s*$'),
          ' ',
        )
        .replaceAll(RegExp(r'前天|昨晚|昨天|今早|今晚|今天|明天'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return RecognitionNormalizer.indexKey(withoutFields);
  }

  @override
  RecognitionResult recognize(RecognitionInput input) {
    final normalized = _normalizer.normalize(input.rawText);
    final entityMatches = _entityMatcher.match(normalized.matchingText);
    final entityEvidence = _entityMatcher.evidence(entityMatches);
    final lexiconEvidence = _lexiconMatcher.match(normalized.matchingText);
    final fields = _fieldExtractor.extract(
      displayText: normalized.displayText,
      matchingText: normalized.matchingText,
      nowLocal: input.nowLocal,
      entityMatches: entityMatches,
      lexiconEvidence: lexiconEvidence,
      entityProtectedSpans: _entityMatcher.protectedNumericSpans(entityMatches),
    );
    final typeDecision = _typeInference.infer(
      matchingText: normalized.matchingText,
      status: fields.status,
      amount: fields.selectedAmount,
      hasContent: fields.content != null,
    );
    final issueCodes = <RecognitionIssueCode>{...fields.issueCodes};
    if (typeDecision.type == null) {
      issueCodes.add(
        typeDecision.hasConflict
            ? RecognitionIssueCode.typeConflict
            : RecognitionIssueCode.typeLowConfidence,
      );
    }
    final content = fields.content;
    final contentKey = RecognitionNormalizer.indexKey(
      content?.matchingText ?? '',
    );
    final semanticEvidence = <RecognitionEvidence>[
      ..._historyMatcher.match(
        normalizedContent: contentKey,
        records: input.personalHistory,
        now: input.nowLocal,
      ),
      ...entityEvidence,
      ...lexiconEvidence,
      ..._contextBuilder.build(
        matchingText: normalized.matchingText,
        occurredHour: fields.time.value.hour,
        timeIsExplicit: fields.time.isExplicit,
        entityEvidence: entityEvidence,
      ),
    ];
    final conflictingTypeEvidence = typeDecision.type == null
        ? const <RecognitionEvidence>[]
        : semanticEvidence
              .where(
                (item) =>
                    item.semanticKey != null &&
                    !item.semanticKey!.startsWith(
                      '${typeDecision.type!.value}.',
                    ),
              )
              .toList();
    final eligibleEvidence = typeDecision.type == null
        ? semanticEvidence
        : semanticEvidence
              .where(
                (item) =>
                    item.semanticKey == null ||
                    item.semanticKey!.startsWith(
                      '${typeDecision.type!.value}.',
                    ),
              )
              .toList();
    if (conflictingTypeEvidence.any((item) => item.score >= 0.85)) {
      issueCodes.add(RecognitionIssueCode.typeConflict);
    }
    final fusion = _fusion.fuse(eligibleEvidence);
    issueCodes.addAll(fusion.issueCodes);
    final type = fields.status == TransactionStatus.refund
        ? RecognitionTransactionType.refund
        : typeDecision.type;
    final resolved = fusion.semanticKey == null || type == null
        ? null
        : _resolver.resolve(
            semanticKey: fusion.semanticKey!,
            type: type,
            categories: input.activeCategories,
          );
    if (fusion.semanticKey != null &&
        resolved == null &&
        fields.status != TransactionStatus.refund) {
      issueCodes.add(RecognitionIssueCode.categoryMappingMissing);
    }
    final amountConfidence = fields.selectedAmount == null
        ? 0.0
        : (fields.selectedAmount!.score / 135).clamp(0.35, 0.99);
    final fieldConfidence = FieldConfidence(
      amount: amountConfidence,
      type: typeDecision.confidence,
      category: fusion.confidence,
      time: fields.time.isExplicit ? 0.96 : 0.82,
      content: content?.confidence ?? 0,
    );
    final confidence = _calibrator.overall(
      fields: fieldConfidence,
      issues: issueCodes,
    );
    final issues = issueCodes
        .map(RecognitionResult.issueMessage)
        .toList(growable: false);
    return RecognitionResult(
      draft: EntryDraft(
        rawText: input.rawText,
        normalizedText: normalized.matchingText,
        type: type,
        amountMinor: fields.selectedAmount?.amountMinor,
        content: content?.displayText,
        normalizedContent: content?.matchingText,
        normalizedMerchant: contentKey,
        occurredAtLocal: fields.time.value,
        timezoneOffsetMinutes: input.timezoneOffsetMinutes,
      ),
      categoryId: resolved?.parent.id,
      subcategoryId: resolved?.child.id,
      categoryName: resolved?.parent.name,
      subcategoryName: resolved?.child.name,
      semanticKey: fusion.semanticKey,
      confidence: confidence,
      fieldConfidence: fieldConfidence,
      evidence: List.unmodifiable([
        ...typeDecision.evidence,
        ...eligibleEvidence,
      ]),
      issueCodes: Set.unmodifiable(issueCodes),
      issues: List.unmodifiable(issues),
      status: fields.status,
      amountCandidates: fields.amountCandidates,
      spans: fields.spans,
      multipleTransactionsDetected: fields.multipleTransactionsDetected,
    );
  }
}

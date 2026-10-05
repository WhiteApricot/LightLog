import 'category_resolver.dart';
import 'confidence_calibrator.dart';
import 'context_evidence.dart';
import 'entity_matcher.dart';
import 'evidence_fusion.dart';
import 'field_extractor.dart';
import 'knowledge_models.dart';
import 'lexicon_matcher.dart';
import 'family_matcher.dart';
import 'normalization.dart';
import 'ngram_classifier.dart';
import 'personal_history.dart';
import 'recognition_models.dart';
import 'span_conflict_resolver.dart';
import 'type_inference.dart';

class LocalRecognizer {
  LocalRecognizer({required KnowledgeCatalog knowledge, this.ngram})
    : _entityMatcher = EntityMatcher(knowledge),
      _lexiconMatcher = LexiconMatcher(knowledge),
      _familyMatcher = FamilyMatcher(knowledge);

  final NgramClassifier? ngram;

  final EntityMatcher _entityMatcher;
  final LexiconMatcher _lexiconMatcher;
  final FamilyMatcher _familyMatcher;
  static const _spanConflictResolver = SpanConflictResolver();
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

  RecognitionResult recognize(
    RecognitionInput input, {
    void Function(
      EvidenceFusionResult,
      TypeDecision,
      bool,
      RecognitionEvidence?,
    )?
    onSemanticDecision,
  }) {
    final normalized = _normalizer.normalize(input.rawText);
    final entityMatches = _entityMatcher.match(normalized.matchingText);
    final rawEntityEvidence = _entityMatcher.evidence(entityMatches);
    final rawLexiconEvidence = _lexiconMatcher.match(normalized.matchingText);
    final familyMatches = _familyMatcher.match(normalized.matchingText);
    final resolvedSemanticEvidence = _spanConflictResolver.resolveEvidence([
      ...rawEntityEvidence,
      ...rawLexiconEvidence,
      ..._familyMatcher.evidence(familyMatches),
    ]);
    final lexiconEvidence = resolvedSemanticEvidence
        .where((e) => e.source == RecognitionEvidenceSource.categoryLexicon)
        .toList();
    final fields = _fieldExtractor.extract(
      displayText: normalized.displayText,
      matchingText: normalized.matchingText,
      nowLocal: input.nowLocal,
      entityMatches: entityMatches,
      lexiconEvidence: lexiconEvidence,
      entityProtectedSpans: _entityMatcher.protectedNumericSpans(entityMatches),
    );
    final preliminaryType = _typeInference.inferPreliminary(
      matchingText: normalized.matchingText,
      status: fields.status,
      amount: fields.selectedAmount,
      hasContent: fields.content != null,
    );
    final issueCodes = <RecognitionIssueCode>{...fields.issueCodes};
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
      ...resolvedSemanticEvidence,
    ];
    final mealEvidence = _contextBuilder
        .build(
          matchingText: normalized.matchingText,
          occurredHour: fields.time.value.hour,
          timeIsExplicit: fields.time.isExplicit,
          entityEvidence: resolvedSemanticEvidence,
        )
        .firstOrNull;
    final deterministicFusion = _fusion.withMealEvidence(
      _fusion.fuse(semanticEvidence),
      mealEvidence,
    );
    if (mealEvidence != null) semanticEvidence.add(mealEvidence);
    var typeDecision = _typeInference.reconcile(
      preliminaryType,
      deterministicFusion.semanticKey,
      deterministicFusion.winningEvidence,
    );
    onSemanticDecision?.call(
      deterministicFusion,
      preliminaryType,
      !RecognitionResult.isSafetyBlocked(issueCodes) &&
          typeDecision.type != RecognitionTransactionType.refund,
      mealEvidence,
    );
    final routed =
        _fusion.needsWeakEvidence(deterministicFusion) &&
            (fields.status == TransactionStatus.success ||
                fields.status == TransactionStatus.unknown) &&
            !fields.multipleTransactionsDetected &&
            fields.selectedAmount != null &&
            typeDecision.type != RecognitionTransactionType.refund
        ? ngram?.hierarchicalEvidence(
            input.rawText,
            input.activeCategories,
            level: _fusion.statisticalLevel(deterministicFusion),
            anchor: deterministicFusion.semanticKey,
            structuredFeatures: NgramClassifier.structuredFeatures(
              preliminaryType,
              deterministicFusion.winningEvidence,
              ngram!.model.parentByChild,
            ),
          )
        : null;
    var weakEvidence = routed?.evidence;
    if (weakEvidence?.semanticKey?.startsWith('income.refund.') ?? false) {
      weakEvidence = null;
    }
    // A frozen model may suggest a meal label, but never determines daypart.
    if (mealEvidence == null &&
        ContextEvidenceBuilder.mealSemantics.contains(
          weakEvidence?.semanticKey,
        )) {
      weakEvidence = null;
    }
    if (weakEvidence != null &&
        preliminaryType.isDefault &&
        routed!.parentConfidence >= .85) {
      typeDecision = _typeInference.reconcile(
        preliminaryType,
        weakEvidence.semanticKey,
        [weakEvidence],
        statisticalParentConfidence: routed.parentConfidence,
      );
    }
    final fusion = _fusion.withWeakEvidence(
      deterministicFusion,
      weakEvidence,
      typeDecision.type,
    );
    if (weakEvidence != null) semanticEvidence.add(weakEvidence);
    if (typeDecision.hasConflict) {
      issueCodes.add(RecognitionIssueCode.typeConflict);
    }
    if (typeDecision.type == null) {
      issueCodes.add(RecognitionIssueCode.typeLowConfidence);
    }
    issueCodes.addAll(fusion.issueCodes);
    final type = fields.status == TransactionStatus.refund
        ? RecognitionTransactionType.refund
        : typeDecision.type;
    final resolverType = type == RecognitionTransactionType.refund
        ? RecognitionTransactionType.income
        : type;
    if (type == RecognitionTransactionType.refund) {
      issueCodes.add(RecognitionIssueCode.relatedTransactionRequired);
    }
    var semanticKey = fusion.semanticKey;
    var categoryConfidence = fusion.confidence;
    var resolved = semanticKey == null || resolverType == null
        ? null
        : _resolver.resolve(
            semanticKey: semanticKey,
            type: resolverType,
            categories: input.activeCategories,
          );
    // Final category resolution only: deterministic and n-gram had their chance.
    // Reuse the same dangerous-issue gate as Candidate confirmation.
    if (resolved == null &&
        (type == RecognitionTransactionType.expense ||
            type == RecognitionTransactionType.income) &&
        (fields.selectedAmount?.amountMinor ?? 0) > 0 &&
        !RecognitionResult.isSafetyBlocked(issueCodes)) {
      final fallbackKey = '${type!.value}.other.general';
      final fallback = _resolver.resolve(
        semanticKey: fallbackKey,
        type: type,
        categories: input.activeCategories,
      );
      if (fallback != null) {
        resolved = fallback;
        semanticKey = fallbackKey;
        categoryConfidence = .55;
        issueCodes.add(RecognitionIssueCode.categoryLowConfidence);
        semanticEvidence.add(
          RecognitionEvidence(
            field: 'category',
            description: '无合法分类，使用其他分类并要求确认',
            score: .55,
            source: RecognitionEvidenceSource.context,
            semanticKey: fallbackKey,
            family: 'otherGeneralFallback',
          ),
        );
      }
    }
    if (semanticKey != null &&
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
      category: categoryConfidence,
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
      semanticKey: semanticKey,
      confidence: confidence,
      fieldConfidence: fieldConfidence,
      evidence: List.unmodifiable([
        ...typeDecision.evidence,
        ...semanticEvidence,
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

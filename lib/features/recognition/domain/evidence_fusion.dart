import 'recognition_models.dart';

class EvidenceFusionResult {
  const EvidenceFusionResult({
    required this.semanticKey,
    required this.confidence,
    required this.issueCodes,
    required this.winningEvidence,
  });

  final String? semanticKey;
  final double confidence;
  final Set<RecognitionIssueCode> issueCodes;
  final List<RecognitionEvidence> winningEvidence;
}

class EvidenceFusion {
  const EvidenceFusion();

  /// Ordinary semantic evidence is a feature/prior. Only reliable personal
  /// history and explicit prepared-meal routing lock semantic arbitration.
  int statisticalLevel(EvidenceFusionResult result) {
    final locked = result.winningEvidence.any(
      (e) =>
          e.family == 'mealByExplicitTime' ||
          e.family == 'mealByOccurredAt' ||
          (e.source == RecognitionEvidenceSource.personalHistory &&
              e.score >= .70),
    );
    return locked &&
            !result.issueCodes.contains(RecognitionIssueCode.categoryAmbiguous)
        ? 0
        : 2;
  }

  /// Product contract: a definite meal and its parsed local time outrank food
  /// subtypes. Non-food purposes and all safety gates remain untouched.
  EvidenceFusionResult withMealEvidence(
    EvidenceFusionResult deterministic,
    RecognitionEvidence? meal,
  ) {
    if (meal == null ||
        (deterministic.semanticKey != null &&
            !deterministic.semanticKey!.startsWith('expense.food.'))) {
      return deterministic;
    }
    return EvidenceFusionResult(
      semanticKey: meal.semanticKey,
      confidence: meal.score.clamp(0, .79),
      issueCodes: {
        ...deterministic.issueCodes.where(
          (c) => c != RecognitionIssueCode.categoryLowConfidence,
        ),
      },
      winningEvidence: [meal],
    );
  }

  bool needsWeakEvidence(EvidenceFusionResult deterministic) =>
      statisticalLevel(deterministic) > 0;

  /// Statistical evidence respects the selected permission level and reconciled
  /// direction, never resolves a safety issue, and cannot create high confidence.
  EvidenceFusionResult withWeakEvidence(
    EvidenceFusionResult deterministic,
    RecognitionEvidence? weak,
    RecognitionTransactionType? type,
  ) {
    if (weak == null ||
        !needsWeakEvidence(deterministic) ||
        (statisticalLevel(deterministic) == 1 &&
            deterministic.semanticKey!.split('.').take(2).join('.') !=
                weak.semanticKey!.split('.').take(2).join('.')) ||
        type == null ||
        (type != RecognitionTransactionType.expense &&
            type != RecognitionTransactionType.income &&
            type != RecognitionTransactionType.refund) ||
        !weak.semanticKey!.startsWith(
          '${type == RecognitionTransactionType.refund ? 'income' : type.value}.',
        ) ||
        (weak.semanticKey!.startsWith('income.refund.') &&
            type != RecognitionTransactionType.refund)) {
      return deterministic;
    }
    return EvidenceFusionResult(
      semanticKey: weak.semanticKey,
      confidence: weak.score.clamp(0, .69),
      issueCodes: {
        ...deterministic.issueCodes.where(
          (c) => c != RecognitionIssueCode.categoryLowConfidence,
        ),
        if (weak.score < .58) RecognitionIssueCode.categoryLowConfidence,
      },
      winningEvidence: [weak],
    );
  }

  EvidenceFusionResult fuse(List<RecognitionEvidence> evidence) {
    final negatives = evidence.where((item) => item.negative).toList();
    final positive = _deduplicate(
      evidence.where(
        (item) =>
            !item.negative && item.semanticKey != null && item.score >= 0.40,
      ),
    );
    if (positive.isEmpty) {
      return const EvidenceFusionResult(
        semanticKey: null,
        confidence: 0,
        issueCodes: {RecognitionIssueCode.categoryLowConfidence},
        winningEvidence: [],
      );
    }

    final bySemantic = <String, List<RecognitionEvidence>>{};
    for (final item in positive) {
      bySemantic.putIfAbsent(item.semanticKey!, () => []).add(item);
    }
    final ranked = bySemantic.entries.map((entry) {
      entry.value.sort((a, b) {
        final priority = _priority(b).compareTo(_priority(a));
        return priority != 0 ? priority : b.score.compareTo(a.score);
      });
      final top = entry.value.first;
      final independentFamilies = entry.value
          .map((item) => item.family ?? '${item.source.name}:${item.role.name}')
          .toSet()
          .length;
      final rank =
          _priority(top) + top.score + (independentFamilies - 1) * 0.02;
      return (key: entry.key, evidence: entry.value, rank: rank);
    }).toList()..sort((a, b) => b.rank.compareTo(a.rank));

    final byParent =
        <
          String,
          List<({String key, List<RecognitionEvidence> evidence, double rank})>
        >{};
    for (final child in ranked) {
      final parent = child.key.split('.').take(2).join('.');
      byParent.putIfAbsent(parent, () => []).add(child);
    }
    final parents = byParent.entries.map((entry) {
      final children = entry.value;
      final families = children
          .expand((child) => child.evidence)
          .map((e) => e.family ?? '${e.source.name}:${e.role.name}')
          .toSet();
      // Maximum anchor plus bounded independent support; taxonomy size has no weight.
      final score =
          children.first.rank + (families.length - 1).clamp(0, 3) * .03;
      return (children: children, score: score);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));
    final relevantChildren = parents.first.children;
    final winner = relevantChildren.first;
    final top = winner.evidence.first;
    final hasSpecificSupport = winner.evidence.any(
      (item) => item.specificity == EvidenceSpecificity.specific,
    );
    if (top.source != RecognitionEvidenceSource.familyPrior &&
        !hasSpecificSupport &&
        (top.role == EvidenceRole.platform ||
            top.role == EvidenceRole.product ||
            (top.role == EvidenceRole.service &&
                top.source == RecognitionEvidenceSource.categoryLexicon))) {
      return EvidenceFusionResult(
        semanticKey: winner.key,
        confidence: top.score.clamp(0, 0.57),
        issueCodes: const {RecognitionIssueCode.categoryAmbiguous},
        winningEvidence: List.unmodifiable(winner.evidence),
      );
    }
    var confidence =
        top.score +
        ((winner.evidence.map((item) => item.source).toSet().length - 1).clamp(
              0,
              2,
            ) *
            0.025);
    final issues = <RecognitionIssueCode>{};
    final competitors = [
      if (relevantChildren.length > 1) relevantChildren[1],
      if (parents.length > 1) parents[1].children.first,
    ];
    for (final runnerUp in competitors) {
      final priorityGap = _priority(top) - _priority(runnerUp.evidence.first);
      if (priorityGap.abs() <= 8 || winner.rank - runnerUp.rank < 0.10) {
        confidence = confidence.clamp(0, 0.64);
        issues.add(RecognitionIssueCode.categoryAmbiguous);
      }
    }
    if (competitors.isNotEmpty && issues.isEmpty) confidence -= .06;
    for (final negative in negatives.where(
      (item) => item.semanticKey == winner.key,
    )) {
      confidence -= negative.score * 0.20;
    }
    if (top.source == RecognitionEvidenceSource.entityKnowledge &&
        top.specificity != EvidenceSpecificity.specific) {
      confidence = confidence.clamp(0, 0.72);
    }
    if (top.role == EvidenceRole.platform) {
      confidence = confidence.clamp(0, 0.62);
    }
    if (top.source == RecognitionEvidenceSource.entityKnowledge &&
        !winner.evidence.any(
          (item) =>
              item.source != RecognitionEvidenceSource.entityKnowledge &&
              item.specificity == EvidenceSpecificity.specific,
        )) {
      confidence = confidence.clamp(0, 0.79);
    }
    if (top.description.contains('fuzzy')) {
      confidence = confidence.clamp(0, 0.70);
    }
    if (top.family == 'mealDaypartClock') {
      confidence = confidence.clamp(0, 0.79);
    }
    if (top.source == RecognitionEvidenceSource.familyPrior) {
      confidence = confidence.clamp(0, .79);
    }
    confidence = confidence.clamp(0, 0.99);
    if (confidence < 0.58) {
      issues.add(RecognitionIssueCode.categoryLowConfidence);
      return EvidenceFusionResult(
        semanticKey: winner.key,
        confidence: confidence,
        issueCodes: Set.unmodifiable(issues),
        winningEvidence: List.unmodifiable(winner.evidence),
      );
    }
    return EvidenceFusionResult(
      semanticKey: winner.key,
      confidence: confidence,
      issueCodes: Set.unmodifiable(issues),
      winningEvidence: List.unmodifiable(winner.evidence),
    );
  }

  static List<RecognitionEvidence> _deduplicate(
    Iterable<RecognitionEvidence> evidence,
  ) {
    final byFamily = <String, RecognitionEvidence>{};
    for (final item in evidence) {
      final key =
          '${item.semanticKey}:${item.family ?? '${item.source.name}:${item.role.name}:${item.matchedText}'}';
      final previous = byFamily[key];
      if (previous == null || item.score > previous.score) byFamily[key] = item;
    }
    return byFamily.values.toList();
  }

  static int _priority(RecognitionEvidence evidence) {
    if (evidence.source == RecognitionEvidenceSource.ngram) return 30;
    if (evidence.source == RecognitionEvidenceSource.personalHistory) {
      return 100;
    }
    if (evidence.source == RecognitionEvidenceSource.composition) return 96;
    if (evidence.source == RecognitionEvidenceSource.familyPrior) return 68;
    if (evidence.role == EvidenceRole.platform) return 25;
    final specific = evidence.specificity == EvidenceSpecificity.specific;
    if (specific &&
        (evidence.role == EvidenceRole.product ||
            evidence.role == EvidenceRole.action ||
            evidence.role == EvidenceRole.service)) {
      return 90;
    }
    if (specific &&
        evidence.source == RecognitionEvidenceSource.entityKnowledge) {
      return 80;
    }
    if (evidence.role == EvidenceRole.product ||
        evidence.role == EvidenceRole.action ||
        evidence.role == EvidenceRole.service) {
      return 72;
    }
    if (evidence.role == EvidenceRole.merchantType) return 62;
    if (evidence.role == EvidenceRole.venue) return 52;
    if (evidence.source == RecognitionEvidenceSource.context) return 45;
    return 40;
  }
}

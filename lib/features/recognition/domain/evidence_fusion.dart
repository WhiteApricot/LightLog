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
      entry.value.sort((a, b) => _priority(b).compareTo(_priority(a)));
      final top = entry.value.first;
      final independentFamilies = entry.value
          .map((item) => item.family ?? '${item.source.name}:${item.role.name}')
          .toSet()
          .length;
      final rank =
          _priority(top) + top.score + (independentFamilies - 1) * 0.02;
      return (key: entry.key, evidence: entry.value, rank: rank);
    }).toList()..sort((a, b) => b.rank.compareTo(a.rank));

    final winner = ranked.first;
    final top = winner.evidence.first;
    final hasSpecificSupport = winner.evidence.any(
      (item) => item.specificity == EvidenceSpecificity.specific,
    );
    if (!hasSpecificSupport &&
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
    if (ranked.length > 1) {
      final runnerUp = ranked[1];
      final priorityGap = _priority(top) - _priority(runnerUp.evidence.first);
      if (priorityGap.abs() <= 8 || winner.rank - runnerUp.rank < 0.10) {
        confidence = confidence.clamp(0, 0.64);
        issues.add(RecognitionIssueCode.categoryAmbiguous);
      } else {
        confidence -= 0.06;
      }
    }
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
    if (evidence.source == RecognitionEvidenceSource.personalHistory) {
      return 100;
    }
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

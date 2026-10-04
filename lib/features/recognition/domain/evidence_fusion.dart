import 'recognition_models.dart';

class EvidenceFusionResult {
  const EvidenceFusionResult({
    required this.semanticKey,
    required this.confidence,
    required this.issues,
  });

  final String? semanticKey;
  final double confidence;
  final List<String> issues;
}

class EvidenceFusion {
  const EvidenceFusion();

  static const _minimumScore = 0.58;

  EvidenceFusionResult fuse(List<RecognitionEvidence> evidence) {
    final positive = evidence
        .where(
          (item) =>
              !item.negative && item.semanticKey != null && item.score >= 0.40,
        )
        .toList(growable: false);
    if (positive.isEmpty) {
      return const EvidenceFusionResult(
        semanticKey: null,
        confidence: 0,
        issues: ['没有足够的分类证据'],
      );
    }

    final history =
        positive
            .where(
              (item) =>
                  item.source == RecognitionEvidenceSource.personalHistory,
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    final ranked = [...positive]
      ..sort((a, b) {
        final priority = _priority(b.source).compareTo(_priority(a.source));
        return priority != 0 ? priority : b.score.compareTo(a.score);
      });
    final winner = history.isNotEmpty ? history.first : ranked.first;
    if (winner.score < _minimumScore) {
      return EvidenceFusionResult(
        semanticKey: null,
        confidence: winner.score,
        issues: const ['分类置信度不足，请手动选择'],
      );
    }
    final supportingSources = positive
        .where((item) => item.semanticKey == winner.semanticKey)
        .map((item) => item.source)
        .toSet();
    final conflicts =
        positive
            .where((item) => item.semanticKey != winner.semanticKey)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));

    var confidence =
        winner.score + ((supportingSources.length - 1).clamp(0, 2) * 0.025);
    final issues = <String>[];
    if (conflicts.isNotEmpty) {
      final strongest = conflicts.first;
      final gap = winner.score - strongest.score;
      if (winner.source == RecognitionEvidenceSource.personalHistory) {
        confidence -= 0.03;
      } else if (gap < 0.12) {
        confidence = confidence.clamp(0, 0.55);
        issues.add('分类证据冲突，请确认分类');
      } else {
        confidence -= 0.08;
      }
    }
    for (final negative in evidence.where(
      (item) => item.negative && item.semanticKey == winner.semanticKey,
    )) {
      confidence -= negative.score * 0.15;
    }
    confidence = confidence.clamp(0, 0.99);
    return EvidenceFusionResult(
      semanticKey: winner.semanticKey,
      confidence: confidence,
      issues: List.unmodifiable(issues),
    );
  }

  static int _priority(RecognitionEvidenceSource source) => switch (source) {
    RecognitionEvidenceSource.personalHistory => 5,
    RecognitionEvidenceSource.merchantKnowledge => 4,
    RecognitionEvidenceSource.categoryLexicon => 3,
    RecognitionEvidenceSource.context => 2,
    RecognitionEvidenceSource.ngram => 1,
    RecognitionEvidenceSource.parser => 0,
  };
}

import 'recognition_models.dart';

class SpanConflictResolver {
  const SpanConflictResolver();

  List<RecognitionEvidence> resolveEvidence(List<RecognitionEvidence> input) {
    return List.unmodifiable([
      for (final candidate in input)
        if (!_isShadowed(candidate, input)) candidate,
    ]);
  }

  static bool _isShadowed(
    RecognitionEvidence candidate,
    List<RecognitionEvidence> all,
  ) {
    final span = candidate.span;
    if (span == null || candidate.negative) return false;
    return all.any((other) {
      final otherSpan = other.span;
      if (identical(candidate, other) || otherSpan == null || other.negative) {
        return false;
      }
      if (!_strictlyContains(otherSpan, span)) return false;
      if (other.source == RecognitionEvidenceSource.familyPrior &&
          candidate.source != RecognitionEvidenceSource.composition &&
          otherSpan.length > span.length &&
          other.score >= .70) {
        return true;
      }
      if (other.semanticKey == candidate.semanticKey) {
        return other.score >= candidate.score;
      }
      return other.specificity.index >= candidate.specificity.index &&
          other.score >= candidate.score;
    });
  }

  static bool _strictlyContains(TextSpanRange outer, TextSpanRange inner) =>
      outer.start <= inner.start &&
      outer.end >= inner.end &&
      outer.length > inner.length;
}

import 'knowledge_models.dart';
import 'recognition_models.dart';

class SpanConflictResolver {
  const SpanConflictResolver();

  List<RecognitionEvidence> resolveEvidence(
    List<RecognitionEvidence> input, {
    List<LexicalFamilyMatch> familyMatches = const [],
  }) {
    return List.unmodifiable([
      for (final candidate in input)
        if (!_isShadowed(candidate, input, familyMatches)) candidate,
    ]);
  }

  List<LexicalFamilyMatch> resolveFamilyMatches(
    List<LexicalFamilyMatch> input,
  ) {
    return List.unmodifiable([
      for (final candidate in input)
        if (!input.any(
          (other) =>
              !identical(candidate, other) &&
              _strictlyContains(other.range, candidate.range) &&
              other.conceptFamily == candidate.conceptFamily,
        ))
          candidate,
    ]);
  }

  static bool _isShadowed(
    RecognitionEvidence candidate,
    List<RecognitionEvidence> all,
    List<LexicalFamilyMatch> familyMatches,
  ) {
    final span = candidate.span;
    if (span == null || candidate.negative) return false;
    if (familyMatches.any((match) => _strictlyContains(match.range, span))) {
      return true;
    }
    return all.any((other) {
      final otherSpan = other.span;
      if (identical(candidate, other) || otherSpan == null || other.negative) {
        return false;
      }
      if (!_strictlyContains(otherSpan, span)) return false;
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

import 'knowledge_models.dart';
import 'recognition_models.dart';

class CompositionalMatcher {
  const CompositionalMatcher(this.catalog);

  final KnowledgeCatalog catalog;

  List<RecognitionEvidence> match(List<LexicalFamilyMatch> matches) {
    final byFamily = <String, List<LexicalFamilyMatch>>{};
    for (final match in matches) {
      byFamily.putIfAbsent(match.conceptFamily, () => []).add(match);
    }
    final result = <RecognitionEvidence>[];
    for (final rule in catalog.compositionRules) {
      final left = byFamily[rule.leftFamily] ?? const [];
      final right = byFamily[rule.rightFamily] ?? const [];
      LexicalFamilyMatch? bestLeft;
      LexicalFamilyMatch? bestRight;
      var bestDistance = 1 << 30;
      for (final leftMatch in left) {
        for (final rightMatch in right) {
          // A single compound term is not two independent concept spans.
          if (leftMatch.range.overlaps(rightMatch.range) &&
              !_embeddedContext(rule, leftMatch, rightMatch)) {
            continue;
          }
          final distance = _distance(leftMatch.range, rightMatch.range);
          if (distance <= rule.maxDistance && distance < bestDistance) {
            bestLeft = leftMatch;
            bestRight = rightMatch;
            bestDistance = distance;
          }
        }
      }
      if (bestLeft == null || bestRight == null) continue;
      final start = bestLeft.range.start < bestRight.range.start
          ? bestLeft.range.start
          : bestRight.range.start;
      final end = bestLeft.range.end > bestRight.range.end
          ? bestLeft.range.end
          : bestRight.range.end;
      result.add(
        RecognitionEvidence(
          field: 'category',
          source: RecognitionEvidenceSource.composition,
          semanticKey: rule.semanticKey,
          description: '组合规则${rule.id}：${bestLeft.term} + ${bestRight.term}',
          score: rule.score,
          role: EvidenceRole.action,
          specificity: EvidenceSpecificity.specific,
          matchedText: '${bestLeft.term}+${bestRight.term}',
          span: TextSpanRange(start: start, end: end),
          family: 'composition:${rule.id}',
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static int _distance(TextSpanRange left, TextSpanRange right) {
    if (left.overlaps(right)) return 0;
    if (left.end <= right.start) return right.start - left.end;
    return left.start - right.end;
  }

  static bool _embeddedContext(
    CompositionRuleKnowledge rule,
    LexicalFamilyMatch left,
    LexicalFamilyMatch right,
  ) {
    // Contexts may be embedded in object names (摄影灯); animal prefixes
    // identify supplies (猫砂盆). Identical spans remain a single concept.
    if (left.range.start == right.range.start &&
        left.range.end == right.range.end) {
      return false;
    }
    final families = {rule.leftFamily, rule.rightFamily};
    return families.every((id) => id.startsWith('income.')) ||
        (families.any((id) => id.startsWith('context.')) &&
            families.any(
              (id) => id.startsWith('object.') || id.startsWith('income.'),
            )) ||
        (families.contains('object.pet') &&
            families.any(
              (id) => const {
                'object.petSupply',
                'object.petFood',
                'object.petMedicine',
              }.contains(id),
            ));
  }
}

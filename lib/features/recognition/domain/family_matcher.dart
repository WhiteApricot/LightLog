import 'knowledge_models.dart';
import 'normalization.dart';
import 'recognition_models.dart';

class FamilyMatcher {
  FamilyMatcher(KnowledgeCatalog catalog) {
    for (final rule in catalog.compositionRules) {
      _rulesByLeft.putIfAbsent(rule.leftFamily, () => []).add(rule);
    }
    for (final family in catalog.lexicalFamilies) {
      _familiesById[family.id] = family;
      for (final raw in family.terms) {
        final term = RecognitionNormalizer.indexKey(raw);
        if (term.isEmpty) continue;
        _byFirstCharacter.putIfAbsent(term[0], () => []).add((
          family: family.id,
          raw: raw,
          normalized: term,
        ));
      }
    }
  }

  final _familiesById = <String, LexicalFamilyKnowledge>{};
  final _rulesByLeft = <String, List<CompositionRuleKnowledge>>{};
  final _byFirstCharacter =
      <String, List<({String family, String raw, String normalized})>>{};

  List<LexicalFamilyMatch> match(String matchingText) {
    final result = <LexicalFamilyMatch>[];
    final seen = <String>{};
    for (final character in matchingText.split('').toSet()) {
      final entries = _byFirstCharacter[character];
      if (entries == null) continue;
      for (final entry in entries) {
        final term = entry.normalized;
        var start = matchingText.indexOf(term);
        while (start >= 0) {
          final key = '${entry.family}:$start:${start + term.length}';
          if (seen.add(key)) {
            result.add(
              LexicalFamilyMatch(
                conceptFamily: entry.family,
                term: entry.raw,
                range: TextSpanRange(start: start, end: start + term.length),
              ),
            );
          }
          start = matchingText.indexOf(term, start + 1);
        }
      }
    }
    result.removeWhere((match) {
      if (match.term.length != 1) return false;
      final family = _familiesById[match.conceptFamily]!;
      return family.requiresAdjacentFamily.isNotEmpty &&
          !result.any(
            (part) =>
                family.requiresAdjacentFamily.contains(part.conceptFamily) &&
                part.range.start == match.range.end,
          );
    });
    result.sort((a, b) => b.range.length.compareTo(a.range.length));
    return List.unmodifiable(result);
  }

  List<RecognitionEvidence> evidence(List<LexicalFamilyMatch> matches) {
    final byFamily = <String, List<LexicalFamilyMatch>>{};
    for (final match in matches) {
      byFamily.putIfAbsent(match.conceptFamily, () => []).add(match);
    }
    final result = <RecognitionEvidence>[];
    for (final match in matches) {
      final prior = _familiesById[match.conceptFamily]?.prior;
      if (prior == null || match.term.runes.length < 2) continue;
      result.add(
        RecognitionEvidence(
          field: 'category',
          description: '概念默认语义：${match.conceptFamily}',
          source: RecognitionEvidenceSource.familyPrior,
          semanticKey: prior.semanticKey,
          score: prior.score,
          role: EvidenceRole.product,
          specificity: EvidenceSpecificity.general,
          matchedText: match.term,
          span: match.range,
          family: 'family:${match.conceptFamily}',
        ),
      );
    }
    for (final rule in byFamily.keys.expand(
      (id) => _rulesByLeft[id] ?? const <CompositionRuleKnowledge>[],
    )) {
      final left = byFamily[rule.leftFamily] ?? const [];
      final right = byFamily[rule.rightFamily] ?? const [];
      LexicalFamilyMatch? bestLeft;
      LexicalFamilyMatch? bestRight;
      var bestDistance = 1 << 30;
      for (final leftMatch in left) {
        for (final rightMatch in right) {
          // A single compound term is not two independent concept spans.
          if (leftMatch.range.overlaps(rightMatch.range) &&
              !(rule.allowOverlap &&
                  (leftMatch.range.start != rightMatch.range.start ||
                      leftMatch.range.end != rightMatch.range.end))) {
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
}

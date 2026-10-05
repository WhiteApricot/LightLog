import 'knowledge_models.dart';
import 'normalization.dart';
import 'recognition_models.dart';

class LexicalFamilyMatcher {
  LexicalFamilyMatcher(this.catalog) {
    for (final family in catalog.lexicalFamilies) {
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

  final KnowledgeCatalog catalog;
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
    result.removeWhere(
      (match) =>
          match.conceptFamily == 'action.replacePart' &&
          match.term == '换' &&
          !result.any(
            (part) =>
                const {
                  'object.vehicleComponent',
                  'object.digitalComponent',
                  'object.fixtureComponent',
                }.contains(part.conceptFamily) &&
                part.range.start == match.range.end,
          ),
    );
    result.sort((a, b) => b.range.length.compareTo(a.range.length));
    return List.unmodifiable(result);
  }
}

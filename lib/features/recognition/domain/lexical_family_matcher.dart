import 'knowledge_models.dart';
import 'normalization.dart';
import 'recognition_models.dart';

class LexicalFamilyMatcher {
  const LexicalFamilyMatcher(this.catalog);

  final KnowledgeCatalog catalog;

  List<LexicalFamilyMatch> match(String matchingText) {
    final result = <LexicalFamilyMatch>[];
    final seen = <String>{};
    for (final family in catalog.lexicalFamilies) {
      for (final rawTerm in family.terms) {
        final term = RecognitionNormalizer.indexKey(rawTerm);
        if (term.isEmpty) continue;
        var start = matchingText.indexOf(term);
        while (start >= 0) {
          final key = '${family.id}:$start:${start + term.length}';
          if (seen.add(key)) {
            result.add(
              LexicalFamilyMatch(
                conceptFamily: family.id,
                term: rawTerm,
                range: TextSpanRange(start: start, end: start + term.length),
              ),
            );
          }
          start = matchingText.indexOf(term, start + 1);
        }
      }
    }
    result.sort((a, b) => b.range.length.compareTo(a.range.length));
    return List.unmodifiable(result);
  }
}

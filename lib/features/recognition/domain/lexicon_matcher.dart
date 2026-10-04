import 'knowledge_models.dart';
import 'normalization.dart';
import 'recognition_models.dart';

class LexiconMatcher {
  const LexiconMatcher(this.catalog);

  final KnowledgeCatalog catalog;

  List<RecognitionEvidence> match(String matchingText) {
    final compact = RecognitionNormalizer.indexKey(matchingText);
    if (compact.isEmpty) return const [];
    final result = <RecognitionEvidence>[];
    final seen = <String>{};
    for (final item in catalog.lexicon) {
      final term = RecognitionNormalizer.indexKey(item.term);
      if (term.isEmpty || !compact.contains(term)) continue;
      final id = '${item.semanticKey}:$term:${item.role.name}';
      if (!seen.add(id)) continue;
      final conflict = item.negativeTerms
          .map(RecognitionNormalizer.indexKey)
          .where(compact.contains)
          .firstOrNull;
      result.add(
        RecognitionEvidence(
          field: 'category',
          source: RecognitionEvidenceSource.categoryLexicon,
          semanticKey: item.semanticKey,
          description: conflict == null
              ? '类别词典命中“${item.term}”'
              : '“${item.term}”被冲突词“$conflict”抑制',
          score: conflict == null ? item.score : 0.9,
          negative: conflict != null,
          role: item.role,
          specificity: item.specificity,
          matchedText: item.term,
          family: 'lexicon:$term',
        ),
      );
    }
    return List.unmodifiable(result);
  }
}

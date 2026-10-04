import 'dart:convert';

import 'normalization.dart';
import 'recognition_models.dart';

class KnowledgeCatalog {
  KnowledgeCatalog._({
    required this._merchantsByAlias,
    required this._lexiconByFirstCharacter,
  });

  factory KnowledgeCatalog.fromJsonStrings({
    required String merchantsJson,
    required String lexiconJson,
  }) {
    final merchantRoot = jsonDecode(merchantsJson) as Map<String, Object?>;
    final lexiconRoot = jsonDecode(lexiconJson) as Map<String, Object?>;
    final merchants = <String, MerchantKnowledge>{};
    for (final raw in merchantRoot['records']! as List<Object?>) {
      final item = raw! as Map<String, Object?>;
      final merchant = MerchantKnowledge(
        canonicalName: item['canonicalName']! as String,
        primarySemanticKey: item['primarySemanticKey']! as String,
        semanticKey: item['semanticKey']! as String,
        confidence: (item['confidence']! as num).toDouble(),
      );
      for (final alias in <String>[
        merchant.canonicalName,
        ...(item['aliases']! as List<Object?>).cast<String>(),
      ]) {
        merchants[RecognitionNormalizer.indexKey(alias)] = merchant;
      }
    }

    final lexicon = <String, List<LexiconTerm>>{};
    for (final raw in lexiconRoot['entries']! as List<Object?>) {
      final item = raw! as Map<String, Object?>;
      final negative = (item['negative'] as List<Object?>? ?? const [])
          .cast<String>()
          .map(RecognitionNormalizer.indexKey)
          .toList(growable: false);
      for (final keyword in <String>[
        ...(item['keywords']! as List<Object?>).cast<String>(),
        ...(item['aliases'] as List<Object?>? ?? const []).cast<String>(),
      ]) {
        final normalized = RecognitionNormalizer.indexKey(keyword);
        final term = LexiconTerm(
          keyword: normalized,
          semanticKey: item['semanticKey']! as String,
          score: (item['score']! as num).toDouble(),
          negative: negative,
        );
        lexicon.putIfAbsent(normalized[0], () => []).add(term);
      }
    }
    return KnowledgeCatalog._(
      merchantsByAlias: Map<String, MerchantKnowledge>.unmodifiable(merchants),
      lexiconByFirstCharacter: Map<String, List<LexiconTerm>>.unmodifiable({
        for (final entry in lexicon.entries)
          entry.key: List<LexiconTerm>.unmodifiable(entry.value),
      }),
    );
  }

  factory KnowledgeCatalog.empty() => KnowledgeCatalog._(
    merchantsByAlias: const {},
    lexiconByFirstCharacter: const {},
  );

  final Map<String, MerchantKnowledge> _merchantsByAlias;
  final Map<String, List<LexiconTerm>> _lexiconByFirstCharacter;

  RecognitionEvidence? matchMerchant(String normalizedMerchant) {
    final key = RecognitionNormalizer.indexKey(normalizedMerchant);
    final merchant = _merchantsByAlias[key];
    if (merchant == null) return null;
    return RecognitionEvidence(
      field: 'category',
      source: RecognitionEvidenceSource.merchantKnowledge,
      semanticKey: merchant.semanticKey,
      description: '商户知识库精确匹配“${merchant.canonicalName}”',
      score: merchant.confidence,
    );
  }

  List<RecognitionEvidence> matchLexicon(String normalizedContent) {
    final content = RecognitionNormalizer.indexKey(normalizedContent);
    final seen = <LexiconTerm>{};
    final result = <RecognitionEvidence>[];
    for (final rune in content.runes) {
      final terms = _lexiconByFirstCharacter[String.fromCharCode(rune)];
      if (terms == null) continue;
      for (final term in terms) {
        if (!seen.add(term) || !content.contains(term.keyword)) continue;
        if (term.negative.any(content.contains)) continue;
        result.add(
          RecognitionEvidence(
            field: 'category',
            source: RecognitionEvidenceSource.categoryLexicon,
            semanticKey: term.semanticKey,
            description: '类别词典命中“${term.keyword}”',
            score: term.score,
          ),
        );
      }
    }
    return result;
  }
}

class MerchantKnowledge {
  const MerchantKnowledge({
    required this.canonicalName,
    required this.primarySemanticKey,
    required this.semanticKey,
    required this.confidence,
  });

  final String canonicalName;
  final String primarySemanticKey;
  final String semanticKey;
  final double confidence;
}

class LexiconTerm {
  const LexiconTerm({
    required this.keyword,
    required this.semanticKey,
    required this.score,
    required this.negative,
  });

  final String keyword;
  final String semanticKey;
  final double score;
  final List<String> negative;
}

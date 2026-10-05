import 'normalization.dart';
import 'recognition_models.dart';

enum EntityKind {
  merchant,
  platform,
  service,
  mediaTitle,
  gameTitle,
  productBrand,
}

enum EntityBreadth { broad, specific }

enum AliasMatchPolicy { exactOnly, substring, fuzzy }

class EntityKnowledge {
  const EntityKnowledge({
    required this.canonicalName,
    required this.aliases,
    required this.semanticKey,
    required this.confidence,
    required this.kind,
    required this.breadth,
    required this.matchPolicy,
    this.aliasPolicies = const {},
  });

  final String canonicalName;
  final List<String> aliases;
  final String? semanticKey;
  final double confidence;
  final EntityKind kind;
  final EntityBreadth breadth;
  final AliasMatchPolicy matchPolicy;
  final Map<String, AliasMatchPolicy> aliasPolicies;
}

class LexiconKnowledge {
  const LexiconKnowledge({
    required this.term,
    required this.semanticKey,
    required this.score,
    required this.negativeTerms,
    required this.role,
    required this.specificity,
  });

  final String term;
  final String semanticKey;
  final double score;
  final List<String> negativeTerms;
  final EvidenceRole role;
  final EvidenceSpecificity specificity;
}

class LexicalFamilyKnowledge {
  const LexicalFamilyKnowledge({
    required this.id,
    required this.terms,
    this.prior,
    this.requiresAdjacentFamily = const [],
  });

  final String id;
  final List<String> terms;
  // Absence means contextual-only. A family has at most one default meaning.
  final ({String semanticKey, double score})? prior;
  final List<String> requiresAdjacentFamily;
}

class CompositionRuleKnowledge {
  const CompositionRuleKnowledge({
    required this.id,
    required this.leftFamily,
    required this.rightFamily,
    required this.semanticKey,
    required this.maxDistance,
    required this.score,
    this.allowOverlap = false,
  });

  final String id;
  final String leftFamily;
  final String rightFamily;
  final String semanticKey;
  final int maxDistance;
  final double score;
  final bool allowOverlap;
}

class LexicalFamilyMatch {
  const LexicalFamilyMatch({
    required this.conceptFamily,
    required this.term,
    required this.range,
  });

  final String conceptFamily;
  final String term;
  final TextSpanRange range;
}

class EntityAlias {
  const EntityAlias({
    required this.displayAlias,
    required this.normalizedAlias,
    required this.entity,
    required this.matchPolicy,
  });

  final String displayAlias;
  final String normalizedAlias;
  final EntityKnowledge entity;
  final AliasMatchPolicy matchPolicy;
}

class KnowledgeCatalog {
  factory KnowledgeCatalog({
    required List<EntityKnowledge> entities,
    required List<LexiconKnowledge> lexicon,
    List<LexicalFamilyKnowledge> lexicalFamilies = const [],
    List<CompositionRuleKnowledge> compositionRules = const [],
  }) {
    final aliases = <EntityAlias>[
      for (final entity in entities)
        for (final alias in {entity.canonicalName, ...entity.aliases})
          if (RecognitionNormalizer.indexKey(alias).isNotEmpty)
            EntityAlias(
              displayAlias: RecognitionNormalizer.normalizeDisplay(alias),
              normalizedAlias: RecognitionNormalizer.indexKey(alias),
              entity: entity,
              matchPolicy:
                  entity.aliasPolicies[RecognitionNormalizer.indexKey(alias)] ??
                  entity.matchPolicy,
            ),
    ];
    return KnowledgeCatalog._(
      entities: List.unmodifiable(entities),
      aliases: List.unmodifiable(aliases),
      lexicon: List.unmodifiable(lexicon),
      lexicalFamilies: List.unmodifiable(lexicalFamilies),
      compositionRules: List.unmodifiable(compositionRules),
      aliasesByFirstCharacter: _indexAliases(aliases),
      lexiconByFirstCharacter: _indexLexicon(lexicon),
    );
  }

  const KnowledgeCatalog._({
    required this.entities,
    required this.aliases,
    required this.lexicon,
    required this.lexicalFamilies,
    required this.compositionRules,
    required this.aliasesByFirstCharacter,
    required this.lexiconByFirstCharacter,
  });

  factory KnowledgeCatalog.empty() =>
      KnowledgeCatalog(entities: const [], lexicon: const []);

  final List<EntityKnowledge> entities;
  final List<EntityAlias> aliases;
  final List<LexiconKnowledge> lexicon;
  final List<LexicalFamilyKnowledge> lexicalFamilies;
  final List<CompositionRuleKnowledge> compositionRules;
  final Map<String, List<EntityAlias>> aliasesByFirstCharacter;
  final Map<String, List<LexiconKnowledge>> lexiconByFirstCharacter;

  static Map<String, List<EntityAlias>> _indexAliases(
    List<EntityAlias> aliases,
  ) {
    final result = <String, List<EntityAlias>>{};
    for (final alias in aliases) {
      final key = String.fromCharCode(alias.normalizedAlias.runes.first);
      result.putIfAbsent(key, () => <EntityAlias>[]).add(alias);
    }
    for (final values in result.values) {
      values.sort(
        (a, b) => b.normalizedAlias.length.compareTo(a.normalizedAlias.length),
      );
    }
    return Map<String, List<EntityAlias>>.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<EntityAlias>.unmodifiable(entry.value),
    });
  }

  static Map<String, List<LexiconKnowledge>> _indexLexicon(
    List<LexiconKnowledge> lexicon,
  ) {
    final result = <String, List<LexiconKnowledge>>{};
    for (final item in lexicon) {
      final normalized = RecognitionNormalizer.indexKey(item.term);
      if (normalized.isEmpty) continue;
      final key = String.fromCharCode(normalized.runes.first);
      result.putIfAbsent(key, () => <LexiconKnowledge>[]).add(item);
    }
    return Map<String, List<LexiconKnowledge>>.unmodifiable({
      for (final entry in result.entries)
        entry.key: List<LexiconKnowledge>.unmodifiable(entry.value),
    });
  }
}

class EntityMatch {
  const EntityMatch({
    required this.alias,
    required this.range,
    required this.matchType,
    required this.score,
  });

  final EntityAlias alias;
  final TextSpanRange range;
  final String matchType;
  final double score;
}

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
  KnowledgeCatalog({
    required List<EntityKnowledge> entities,
    required List<LexiconKnowledge> lexicon,
  }) : entities = List.unmodifiable(entities),
       lexicon = List.unmodifiable(lexicon),
       aliases = List.unmodifiable([
         for (final entity in entities)
           for (final alias in {entity.canonicalName, ...entity.aliases})
             if (RecognitionNormalizer.indexKey(alias).isNotEmpty)
               EntityAlias(
                 displayAlias: RecognitionNormalizer.normalizeDisplay(alias),
                 normalizedAlias: RecognitionNormalizer.indexKey(alias),
                 entity: entity,
                 matchPolicy:
                     entity.aliasPolicies[RecognitionNormalizer.indexKey(
                       alias,
                     )] ??
                     entity.matchPolicy,
               ),
       ]);

  factory KnowledgeCatalog.empty() =>
      KnowledgeCatalog(entities: const [], lexicon: const []);

  final List<EntityKnowledge> entities;
  final List<EntityAlias> aliases;
  final List<LexiconKnowledge> lexicon;
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

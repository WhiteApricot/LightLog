import 'dart:convert';

import '../domain/knowledge_models.dart';
import '../domain/recognition_models.dart';

class KnowledgeDecoder {
  const KnowledgeDecoder();

  KnowledgeCatalog decode({
    required String entitiesJson,
    required String lexiconJson,
    String lexicalFamiliesJson = '{"families":[]}',
    String compositionRulesJson = '{"rules":[]}',
  }) {
    final entityRoot = jsonDecode(entitiesJson) as Map<String, Object?>;
    final lexiconRoot = jsonDecode(lexiconJson) as Map<String, Object?>;
    final familyRoot = jsonDecode(lexicalFamiliesJson) as Map<String, Object?>;
    final ruleRoot = jsonDecode(compositionRulesJson) as Map<String, Object?>;
    final entities = <EntityKnowledge>[];
    for (final raw in entityRoot['records']! as List<Object?>) {
      final item = (raw! as Map).cast<String, Object?>();
      entities.add(
        EntityKnowledge(
          canonicalName: item['canonicalName']! as String,
          aliases: (item['aliases']! as List<Object?>).cast<String>(),
          semanticKey: item['semanticKey'] as String?,
          confidence: (item['confidence']! as num).toDouble(),
          kind: _entityKind(item['kind'] as String?),
          breadth: _breadth(
            item['breadth'] as String?,
            item['kind'] as String?,
          ),
          matchPolicy: _matchPolicy(item['matchPolicy'] as String?),
          aliasPolicies: {
            for (final entry
                in ((item['aliasPolicies'] as Map?) ?? const {}).entries)
              entry.key as String: _matchPolicy(entry.value as String?),
          },
        ),
      );
    }
    final lexicon = <LexiconKnowledge>[];
    for (final raw in lexiconRoot['entries']! as List<Object?>) {
      final item = (raw! as Map).cast<String, Object?>();
      final negative = (item['negative'] as List<Object?>? ?? const [])
          .cast<String>();
      for (final term in <String>[
        ...(item['keywords']! as List<Object?>).cast<String>(),
        ...(item['aliases'] as List<Object?>? ?? const []).cast<String>(),
      ]) {
        lexicon.add(
          LexiconKnowledge(
            term: term,
            semanticKey: item['semanticKey']! as String,
            score: (item['score']! as num).toDouble(),
            negativeTerms: negative,
            role: _role(item['role'] as String?),
            specificity: _specificity(item['specificity'] as String?),
          ),
        );
      }
    }
    final lexicalFamilies = <LexicalFamilyKnowledge>[];
    for (final raw in familyRoot['families']! as List<Object?>) {
      final item = (raw! as Map).cast<String, Object?>();
      lexicalFamilies.add(
        LexicalFamilyKnowledge(
          id: item['id']! as String,
          terms: (item['terms']! as List<Object?>).cast<String>(),
        ),
      );
    }
    final compositionRules = <CompositionRuleKnowledge>[];
    for (final raw in ruleRoot['rules']! as List<Object?>) {
      final item = (raw! as Map).cast<String, Object?>();
      compositionRules.add(
        CompositionRuleKnowledge(
          id: item['id']! as String,
          leftFamily: item['leftFamily']! as String,
          rightFamily: item['rightFamily']! as String,
          semanticKey: item['semanticKey']! as String,
          maxDistance: item['maxDistance']! as int,
          score: (item['score']! as num).toDouble(),
        ),
      );
    }
    return KnowledgeCatalog(
      entities: entities,
      lexicon: lexicon,
      lexicalFamilies: lexicalFamilies,
      compositionRules: compositionRules,
    );
  }

  static EntityKind _entityKind(String? value) => switch (value) {
    'platform' => EntityKind.platform,
    'service' => EntityKind.service,
    'mediaTitle' || 'media title' => EntityKind.mediaTitle,
    'gameTitle' || 'game title' => EntityKind.gameTitle,
    'media/game title' => EntityKind.mediaTitle,
    'productBrand' || 'product brand' => EntityKind.productBrand,
    _ => EntityKind.merchant,
  };

  static EntityBreadth _breadth(String? value, String? kind) => switch (value) {
    'broad' => EntityBreadth.broad,
    'specific' => EntityBreadth.specific,
    _ when kind == 'platform' || kind == 'productBrand' => EntityBreadth.broad,
    _ => EntityBreadth.specific,
  };

  static AliasMatchPolicy _matchPolicy(String? value) => switch (value) {
    'exactOnly' => AliasMatchPolicy.exactOnly,
    'substring' => AliasMatchPolicy.substring,
    _ => AliasMatchPolicy.fuzzy,
  };

  static EvidenceRole _role(String? value) => switch (value) {
    'product' => EvidenceRole.product,
    'action' => EvidenceRole.action,
    'service' => EvidenceRole.service,
    'venue' => EvidenceRole.venue,
    'platform' => EvidenceRole.platform,
    _ => EvidenceRole.merchantType,
  };

  static EvidenceSpecificity _specificity(String? value) => switch (value) {
    'broad' => EvidenceSpecificity.broad,
    'specific' => EvidenceSpecificity.specific,
    _ => EvidenceSpecificity.general,
  };
}

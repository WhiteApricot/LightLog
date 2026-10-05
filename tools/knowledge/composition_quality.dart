import 'package:light_log/features/recognition/domain/normalization.dart';
import 'package:light_log/data/database/seed_data.dart';

/// Audits the flat family layer independently of semantic lexicon ownership.
Map<String, Object?> compositionQuality(
  Map<String, Object?> familySource,
  Map<String, Object?> ruleSource,
) {
  final validSemantics = defaultCategories
      .where((c) => c.parentId != null)
      .map((c) => c.semanticKey)
      .toSet();
  final families = (familySource['families']! as List).cast<Map>();
  final rules = (ruleSource['rules']! as List).cast<Map>();
  final familyIds = <String>{};
  final priors = <String, String>{};
  final owners = <String, Set<String>>{};
  final termsByFamily = <String, int>{};
  final kinds = <String, int>{};
  final rulesPerFamily = <String, int>{};
  final rulesPerSemantic = <String, int>{};
  final domains = <String, int>{};
  final short = <String>[];
  final duplicates = <String>[];
  for (final family in families) {
    final id = family['id']! as String;
    if (id.isEmpty || !familyIds.add(id)) {
      throw FormatException('Duplicate/empty family: $id');
    }
    final prior = family['prior'] as Map?;
    if (family['policy'] != (prior == null ? 'contextualOnly' : 'standalone')) {
      throw FormatException('Invalid family policy: $id');
    }
    if (prior != null) {
      if (prior.length != 2 ||
          !validSemantics.contains(prior['semanticKey']) ||
          prior['score'] is! num ||
          (prior['score'] as num) < .60 ||
          (prior['score'] as num) > .79) {
        throw FormatException('Invalid prior: $id');
      }
      priors[id] = prior['semanticKey'] as String;
      if (id.startsWith('income.') != priors[id]!.startsWith('income.')) {
        throw FormatException('Cross-type family prior: $id');
      }
    }
    if ((family['terms'] as List).isEmpty) {
      throw FormatException('Empty family: $id');
    }
    final kind = family['kind'] as String? ?? id.split('.').first;
    if (!const {
      'object',
      'action',
      'modifier',
      'context',
      'venue',
      'platform',
      'income',
      'service',
    }.contains(kind)) {
      throw FormatException('Invalid family kind: $id / $kind');
    }
    kinds.update(kind, (v) => v + 1, ifAbsent: () => 1);
    final seen = <String>{};
    for (final term in (family['terms']! as List).cast<String>()) {
      final key = RecognitionNormalizer.indexKey(term);
      if (!seen.add(key)) duplicates.add('$id:$key');
      owners.putIfAbsent(key, () => <String>{}).add(id);
      if (key.runes.length <= 2) short.add('$id:$key');
      // Legacy characters require composition; 换 additionally requires an
      // immediately following reviewed component concept in the matcher.
      if (key.runes.length == 1 &&
          !const {
            'object.pet:猫',
            'object.pet:狗',
            'action.cleaning:洗',
            'action.repair:修',
            'action.replacePart:换',
          }.contains('$id:$key')) {
        throw FormatException(
          'Unreviewed single-character family term: $id:$key',
        );
      }
    }
    termsByFamily[id] = seen.length;
    rulesPerFamily[id] = 0;
  }
  const reviewedShared = {
    '门锁': {'object.homeFixture', 'action.replacePart'},
    '医院': {'action.medical', 'context.medicalVenue'},
    '门诊': {'action.medical', 'context.medicalVenue'},
  };
  final ambiguous = <String, List<String>>{};
  for (final entry in owners.entries.where((e) => e.value.length > 1)) {
    ambiguous[entry.key] = entry.value.toList()..sort();
    final allowed = reviewedShared[entry.key];
    if (allowed == null || entry.value.any((id) => !allowed.contains(id))) {
      throw FormatException(
        'Unresolved cross-family term: ${entry.key} / ${entry.value}',
      );
    }
  }
  final ruleIds = <String>{};
  final pairs = <String>{};
  final reviewedOverrides = <String, List<String>>{};
  for (final family in families) {
    for (final ref in (family['requiresAdjacentFamily'] as List? ?? const [])) {
      if (!familyIds.contains(ref)) {
        throw FormatException('Invalid adjacency family: $ref');
      }
    }
  }
  for (final rule in rules) {
    final id = rule['id'] as String;
    if (!ruleIds.add(id)) throw FormatException('Duplicate rule: $id');
    final pair = [rule['leftFamily'] as String, rule['rightFamily'] as String]
      ..sort();
    if (!pairs.add(pair.join('+'))) {
      throw FormatException('Duplicate pair: $id');
    }
    if (!validSemantics.contains(rule['semanticKey']) ||
        rule['score'] is! num ||
        (rule['score'] as num) < .80 ||
        (rule['score'] as num) > .99 ||
        rule['maxDistance'] is! int ||
        (rule['maxDistance'] as int) < 0 ||
        (rule['maxDistance'] as int) > 20) {
      throw FormatException('Invalid composition output/score/distance: $id');
    }
    final changes = pair
        .where(
          (family) =>
              priors[family] != null && priors[family] != rule['semanticKey'],
        )
        .toList();
    if (changes.isNotEmpty) {
      // A different output needs an explicit contextual operand; two stable
      // standalone objects cannot silently contradict their default meanings.
      if (pair.every(
        (family) => family.startsWith('object.') && priors.containsKey(family),
      )) {
        throw FormatException('Contradictory object priors: $id');
      }
      reviewedOverrides[id] = changes;
    }
    for (final field in ['leftFamily', 'rightFamily']) {
      final id = rule[field]! as String;
      if (!familyIds.contains(id)) {
        throw FormatException('Invalid family reference: $id');
      }
      rulesPerFamily.update(id, (v) => v + 1);
    }
    final semantic = rule['semanticKey']! as String;
    rulesPerSemantic.update(semantic, (v) => v + 1, ifAbsent: () => 1);
    final domain = semantic.split('.').take(2).join('.');
    domains.update(domain, (v) => v + 1, ifAbsent: () => 1);
  }
  final unused =
      rulesPerFamily.entries
          .where((e) => e.value == 0)
          .map((e) => e.key)
          .toList()
        ..sort();
  if (duplicates.isNotEmpty) {
    throw FormatException('Duplicate family terms: $duplicates');
  }
  final standalone = families.where((f) => f['prior'] != null).toList();
  final priorSemantics = standalone
      .map((f) => (f['prior'] as Map)['semanticKey'] as String)
      .toSet();
  final children = {...priorSemantics, ...rulesPerSemantic.keys};
  final orphan = families
      .where((f) => f['prior'] == null && rulesPerFamily[f['id']] == 0)
      .map((f) => f['id'])
      .toList();
  if (orphan.isNotEmpty) {
    throw FormatException('Orphan contextual families: $orphan');
  }
  return {
    'lexicalFamilyCount': families.length,
    'compositionRuleCount': rules.length,
    'reviewedPriorOverrides': reviewedOverrides,
    'unusedRules': <String>[],
    'standaloneFamilyCount': standalone.length,
    'contextualFamilyCount': families.length - standalone.length,
    'familiesWithSemanticPrior': standalone.map((f) => f['id']).toList(),
    'priorSemanticCoverage': priorSemantics.toList()..sort(),
    'parentCoverage':
        children.map((s) => s.split('.').take(2).join('.')).toSet().toList()
          ..sort(),
    'childCoverage': children.toList()..sort(),
    'orphanFamilies': orphan,
    'lexicalFamilyTermCount': owners.length,
    'familyTermsByFamily': termsByFamily,
    'familyKindDistribution': kinds,
    'unusedFamilies': unused,
    'rulesPerFamily': rulesPerFamily,
    'rulesPerSemantic': rulesPerSemantic,
    'compositionSemanticCoverage': rulesPerSemantic.keys.toList()..sort(),
    'duplicateFamilyTerms': duplicates,
    'crossFamilyAmbiguousTerms': ambiguous,
    'shortHighRiskFamilyTerms': short..sort(),
    'compositionDomainDistribution': domains,
    'invalidFamilyReferenceCount': 0,
    'invalidSemanticKeyCount': 0,
    'duplicateRuleCount': 0,
    'unresolvedDangerousConflictCount': 0,
    'constrainedSingleCharacterPolicy': '换 only matches immediately before a reviewed vehicle/digital/fixture component; legacy characters require composition proximity.',
    'reviewedSharedTermPolicy': '医院/门诊 share venue and medical action roles; 门锁 shares fixture and replacement-part roles. No other duplicated strong concept is allowed.',
  };
}

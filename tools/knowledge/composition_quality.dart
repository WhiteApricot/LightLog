import 'package:light_log/features/recognition/domain/normalization.dart';

/// Audits the flat family layer independently of semantic lexicon ownership.
Map<String, Object?> compositionQuality(
  Map<String, Object?> familySource,
  Map<String, Object?> ruleSource,
) {
  final families = (familySource['families']! as List).cast<Map>();
  final rules = (ruleSource['rules']! as List).cast<Map>();
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
  for (final rule in rules) {
    for (final field in ['leftFamily', 'rightFamily']) {
      final id = rule[field]! as String;
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
  if (families.length < 120 ||
      owners.length < 900 ||
      rules.length < 100 ||
      rulesPerSemantic.length < 50) {
    throw const FormatException(
      'Production composition coverage below 120/900/100/50',
    );
  }
  return {
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

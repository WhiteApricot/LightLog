import 'dart:convert';
import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/data/knowledge_decoder.dart';
import 'package:light_log/features/recognition/domain/compositional_matcher.dart';
import 'package:light_log/features/recognition/domain/entity_matcher.dart';
import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/knowledge_models.dart';
import 'package:light_log/features/recognition/domain/lexicon_matcher.dart';
import 'package:light_log/features/recognition/domain/lexical_family_matcher.dart';
import 'package:light_log/features/recognition/domain/normalization.dart';
import 'package:light_log/features/recognition/domain/span_conflict_resolver.dart';

const _runtimeHardLimit = 2 * 1024 * 1024;
const _minimumEntities = 300;
const _minimumAliases = 800;
const _minimumPositiveTerms = 1800;
const _minimumNegativeTerms = 250;
const _minimumSceneCoverage = 1.0;
const _minimumMainlandShare = 0.80;
const _minimumReviewSamples = 100;
const _minimumTermsPerFrequentSemantic = 10;
const _minimumNegativesPerFrequentSemantic = 2;
const _conflictTermOwners = {
  '护手霜': 'expense.daily.personal',
  '洗手液': 'expense.daily.personal',
  '身体乳': 'expense.daily.personal',
  '皮具护理': 'expense.daily.cleaning',
  '车位管理费': 'expense.transport.parking',
};
const _requiredSceneSemantics = {
  'expense.food.breakfast',
  'expense.food.lunch',
  'expense.food.dinner',
  'expense.food.takeout',
  'expense.food.drink',
  'expense.food.snack',
  'expense.food.groceries',
  'expense.food.other',
  'expense.transport.public',
  'expense.transport.taxi',
  'expense.transport.rail',
  'expense.transport.flight',
  'expense.transport.fuel',
  'expense.transport.parking',
  'expense.transport.maintenance',
  'expense.shopping.clothing',
  'expense.shopping.beauty',
  'expense.shopping.home',
  'expense.shopping.appliance',
  'expense.housing.rent',
  'expense.housing.utilities',
  'expense.housing.property',
  'expense.daily.household',
  'expense.daily.personal',
  'expense.daily.cleaning',
  'expense.daily.haircut',
  'expense.daily.service',
  'expense.entertainment.movie',
  'expense.entertainment.game',
  'expense.entertainment.subscription',
  'expense.education.book',
  'expense.education.course',
  'expense.education.exam',
  'expense.education.stationery',
  'expense.medical.clinic',
  'expense.medical.medicine',
  'expense.communication.mobile',
  'expense.communication.internet',
  'expense.communication.post',
  'expense.travel.hotel',
  'expense.travel.ticket',
  'expense.travel.attraction',
  'expense.sports.fitness',
  'expense.pets.food',
  'expense.pets.medical',
  'expense.pets.grooming',
  'expense.pets.service',
  'expense.digital.accessory',
  'expense.digital.software',
  'expense.digital.repair',
  'expense.finance.insurance',
  'expense.finance.fee',
  'income.salary.monthly',
  'income.salary.bonus',
  'income.salary.allowance',
  'income.reimbursement.work',
  'income.parttime.freelance',
  'income.parttime.project',
  'income.investment.interest',
  'income.investment.dividend',
  'income.investment.rent',
  'income.other.red.packet',
  'income.other.secondhand',
};

void main() {
  final validSemantics = defaultCategories
      .map((item) => item.semanticKey)
      .toSet();
  final curated = _read('tools/knowledge/merchants_source.json');
  final mainland = _read('tools/knowledge/mainland_entities_source.json');
  final lexiconSource = _read('tools/knowledge/category_lexicon_source.json');
  final lexiconExpansion = _read(
    'tools/knowledge/lexicon_expansion_source.json',
  );
  final reviewSamples = _read('tools/knowledge/review_samples.json');
  final lexicalFamilySource = _read(
    'tools/knowledge/lexical_families_source.json',
  );
  final compositionRuleSource = _read(
    'tools/knowledge/composition_rules_source.json',
  );
  final familyValidation = _validateCompositionKnowledge(
    familySource: lexicalFamilySource,
    ruleSource: compositionRuleSource,
    validSemantics: validSemantics,
  );

  final rawEntities = <Map<String, Object?>>[
    for (final raw in (curated['records']! as List))
      {
        ...(raw as Map).cast<String, Object?>(),
        '_source': 'curated',
        'market': raw['market'] ?? 'CN-mainland',
      },
    ..._expandGroupedEntities(mainland),
  ];
  final candidates = <Map<String, Object?>>[];
  final canonicalSeen = <String>{};
  final duplicateCanonicals = <String>[];
  for (final item in rawEntities) {
    final source = item['_source']! as String;
    final reviewStatus =
        item['reviewStatus'] as String? ??
        (source == 'curated' ? 'approved' : 'snapshotOnly');
    if (reviewStatus != 'approved') continue;
    final canonical = item['canonicalName']! as String;
    final canonicalKey = _normalize(canonical);
    if (!canonicalSeen.add(canonicalKey)) {
      duplicateCanonicals.add(canonical);
      continue;
    }
    final semantic = item['semanticKey'] as String?;
    if (semantic != null && !validSemantics.contains(semantic)) {
      throw FormatException('$canonical 使用无效 taxonomy: $semantic');
    }
    final confidence = (item['confidence']! as num).toDouble();
    if (confidence < 0.70 || confidence > 0.99) {
      throw FormatException('$canonical confidence 超出 0.70..0.99');
    }
    final kind = _entityKind(item['kind'] as String?);
    final breadth =
        item['breadth'] as String? ??
        (kind == 'platform' || kind == 'productBrand' ? 'broad' : 'specific');
    final aliases = <String>{
      canonical,
      ...(item['aliases']! as List).cast<String>(),
    }.where((value) => _normalize(value).isNotEmpty).toList();
    candidates.add({
      'canonicalName': canonical,
      'aliases': aliases,
      'kind': kind,
      'breadth': breadth,
      'matchPolicy': item['matchPolicy'] as String? ?? 'fuzzy',
      'reviewStatus': reviewStatus,
      'semanticKey': semantic,
      'confidence': confidence,
      'market': item['market'] ?? 'unknown',
    });
  }

  final aliasOwners = <String, Set<String?>>{};
  for (var index = 0; index < candidates.length; index++) {
    for (final alias
        in (candidates[index]['aliases']! as List).cast<String>()) {
      aliasOwners
          .putIfAbsent(_normalize(alias), () => <String?>{})
          .add(candidates[index]['semanticKey'] as String?);
    }
  }
  final conflictingAliases = aliasOwners.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toSet();
  final runtimeEntities = <Map<String, Object?>>[];
  for (final item in candidates) {
    final canonical = item['canonicalName']! as String;
    if (conflictingAliases.contains(_normalize(canonical))) continue;
    final aliases = (item['aliases']! as List)
        .cast<String>()
        .where(
          (alias) =>
              alias != canonical &&
              !conflictingAliases.contains(_normalize(alias)),
        )
        .toList();
    runtimeEntities.add({
      'canonicalName': canonical,
      'aliases': aliases,
      'kind': item['kind'],
      'breadth': item['breadth'],
      'matchPolicy': item['matchPolicy'],
      'aliasPolicies': {
        for (final alias in <String>[canonical, ...aliases])
          if (_isHighRiskAlias(_normalize(alias)))
            _normalize(alias): _exactOnlyAlias(_normalize(alias))
                ? 'exactOnly'
                : 'substring',
      },
      'reviewStatus': item['reviewStatus'],
      if (item['semanticKey'] != null) 'semanticKey': item['semanticKey'],
      'confidence': item['confidence'],
      'market': item['market'],
    });
  }
  final normalizedRuntimeAliases = <String>{
    for (final item in runtimeEntities)
      for (final alias in <String>[
        item['canonicalName']! as String,
        ...(item['aliases']! as List).cast<String>(),
      ])
        _normalize(alias),
  };

  final runtimeLexicon = <Map<String, Object?>>[];
  for (final raw in <Object?>[
    ...(lexiconSource['entries']! as List),
    ...(lexiconExpansion['entries']! as List),
  ]) {
    final item = (raw as Map).cast<String, Object?>();
    final semantic = item['semanticKey']! as String;
    if (!validSemantics.contains(semantic)) {
      throw FormatException('词典使用无效 taxonomy: $semantic');
    }
    final role = item['role'] as String? ?? _defaultRole(semantic);
    runtimeLexicon.add({
      'semanticKey': semantic,
      'role': role,
      'specificity':
          item['specificity'] as String? ?? _defaultSpecificity(role),
      'keywords': item['keywords'],
      'aliases': item['aliases'] ?? const <String>[],
      'negative': item['negative'] ?? const <String>[],
      'score': item['score'],
      'reviewStatus': item['reviewStatus'] ?? 'approved',
    });
  }

  final termOwners = <String, Set<String>>{};
  final negativeTerms = <String>{};
  for (final item in runtimeLexicon) {
    final semantic = item['semanticKey']! as String;
    final score = (item['score']! as num).toDouble();
    if (score < 0.40 || score > 0.95) {
      throw FormatException('$semantic score 超出 0.40..0.95');
    }
    for (final term in <String>[
      ...(item['keywords']! as List).cast<String>(),
      ...(item['aliases']! as List).cast<String>(),
    ]) {
      final key = _normalize(term);
      termOwners.putIfAbsent(key, () => <String>{}).add(semantic);
    }
    for (final term in (item['negative']! as List).cast<String>()) {
      negativeTerms.add(_normalize(term));
    }
  }
  final detectedConflictingTerms = termOwners.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toSet();
  final unresolvedConflictingTerms = detectedConflictingTerms
      .where((term) => !_conflictTermOwners.containsKey(term))
      .toSet();
  for (final item in runtimeLexicon) {
    final semantic = item['semanticKey']! as String;
    item['keywords'] = (item['keywords']! as List).cast<String>().where((term) {
      final key = _normalize(term);
      return !detectedConflictingTerms.contains(key) ||
          _conflictTermOwners[key] == semantic;
    }).toList();
    item['aliases'] = (item['aliases']! as List).cast<String>().where((term) {
      final key = _normalize(term);
      return !detectedConflictingTerms.contains(key) ||
          _conflictTermOwners[key] == semantic;
    }).toList();
  }
  final finalTermsBySemantic = <String, Set<String>>{};
  final negativesBySemantic = <String, Set<String>>{};
  for (final item in runtimeLexicon) {
    final semantic = item['semanticKey']! as String;
    finalTermsBySemantic.putIfAbsent(semantic, () => <String>{}).addAll([
      ...(item['keywords']! as List).cast<String>().map(_normalize),
      ...(item['aliases']! as List).cast<String>().map(_normalize),
    ]);
    negativesBySemantic
        .putIfAbsent(semantic, () => <String>{})
        .addAll((item['negative']! as List).cast<String>().map(_normalize));
  }
  final positiveTerms = <String>{
    for (final terms in finalTermsBySemantic.values) ...terms,
  };
  final coveredScenes = _requiredSceneSemantics.where(
    (key) => (finalTermsBySemantic[key] ?? const <String>{}).any(
      (term) => !unresolvedConflictingTerms.contains(term),
    ),
  );
  final sceneCoverage = coveredScenes.length / _requiredSceneSemantics.length;
  final merchantRuntime = {'version': 3, 'records': runtimeEntities};
  final lexiconRuntime = {'version': 3, 'entries': runtimeLexicon};
  final familyRuntime = {
    'version': 1,
    'families': lexicalFamilySource['families'],
  };
  final ruleRuntime = {'version': 1, 'rules': compositionRuleSource['rules']};
  final sampleResult = _validateSamples(
    reviewSamples: reviewSamples,
    catalog: const KnowledgeDecoder().decode(
      entitiesJson: jsonEncode(merchantRuntime),
      lexiconJson: jsonEncode(lexiconRuntime),
      lexicalFamiliesJson: jsonEncode(familyRuntime),
      compositionRulesJson: jsonEncode(ruleRuntime),
    ),
  );
  Directory('assets/knowledge').createSync(recursive: true);
  _writeCompact('assets/knowledge/merchants.json', merchantRuntime);
  _writeCompact('assets/knowledge/category_lexicon.json', lexiconRuntime);
  _writeCompact('assets/knowledge/lexical_families.json', familyRuntime);
  _writeCompact('assets/knowledge/composition_rules.json', ruleRuntime);
  final runtimeSize =
      File('assets/knowledge/merchants.json').lengthSync() +
      File('assets/knowledge/category_lexicon.json').lengthSync() +
      File('assets/knowledge/lexical_families.json').lengthSync() +
      File('assets/knowledge/composition_rules.json').lengthSync();
  final highRiskAliases = aliasOwners.keys.where(_isHighRiskAlias).toList()
    ..sort();
  final mainlandEntities = runtimeEntities
      .where((item) => item['market'] == 'CN-mainland')
      .length;
  final lowValueEntities = runtimeEntities
      .where(
        (item) => item['kind'] == 'mediaTitle' || item['kind'] == 'gameTitle',
      )
      .length;
  final insufficientFrequentSemantics = <String, Map<String, int>>{
    for (final semantic in _requiredSceneSemantics)
      if ((finalTermsBySemantic[semantic]?.length ?? 0) <
              _minimumTermsPerFrequentSemantic ||
          (negativesBySemantic[semantic]?.length ?? 0) <
              _minimumNegativesPerFrequentSemantic)
        semantic: {
          'positive': finalTermsBySemantic[semantic]?.length ?? 0,
          'negative': negativesBySemantic[semantic]?.length ?? 0,
        },
  };
  final narrowExceptions =
      ((lexiconExpansion['narrowExceptions'] as Map?) ??
              const <String, Object?>{})
          .cast<String, Object?>();
  insufficientFrequentSemantics.removeWhere(
    (semantic, _) => narrowExceptions.containsKey(semantic),
  );
  final uncoveredSemantics =
      _requiredSceneSemantics
          .where(
            (semantic) => (finalTermsBySemantic[semantic] ?? const {}).isEmpty,
          )
          .toList()
        ..sort();
  final entityAudit = _validateAuditList(
    values: (reviewSamples['entityAudit'] as List? ?? const []).cast<String>(),
    available: runtimeEntities.map((item) => item['canonicalName']! as String),
  );
  final lexiconAudit = _validateAuditList(
    values: (reviewSamples['lexiconAudit'] as List? ?? const []).cast<String>(),
    available: positiveTerms,
    normalizeValues: true,
  );
  final report = <String, Object?>{
    'canonicalEntityCount': runtimeEntities.length,
    'aliasCount': normalizedRuntimeAliases.length,
    'lexiconEntryCount': runtimeLexicon.length,
    'positiveTermCount': positiveTerms.length,
    'negativeTermCount': negativeTerms.length,
    'lexicalFamilyCount': familyValidation.familyCount,
    'lexicalFamilyTermCount': familyValidation.termCount,
    'compositionRuleCount': familyValidation.ruleCount,
    'shortHighRiskFamilyTerms': familyValidation.shortHighRiskTerms,
    'sceneSemanticCoverage': sceneCoverage,
    'requiredSceneSemanticCount': _requiredSceneSemantics.length,
    'entityKindDistribution': _counts(
      runtimeEntities.map((item) => item['kind']! as String),
    ),
    'entitySemanticDistribution': _counts(
      runtimeEntities.map((item) => item['semanticKey'] as String? ?? '(none)'),
    ),
    'mainlandEntityCount': mainlandEntities,
    'mainlandEntityShare': mainlandEntities / runtimeEntities.length,
    'lowValueMediaGameCount': lowValueEntities,
    'lowValueMediaGameShare': lowValueEntities / runtimeEntities.length,
    'entityBreadthDistribution': _counts(
      runtimeEntities.map((item) => item['breadth']! as String),
    ),
    'entityReviewDistribution': _counts(
      runtimeEntities.map((item) => item['reviewStatus']! as String),
    ),
    'lexiconRoleDistribution': _counts(
      runtimeLexicon.map((item) => item['role']! as String),
    ),
    'termsBySemantic': {
      for (final key in finalTermsBySemantic.keys.toList()..sort())
        key: finalTermsBySemantic[key]!.length,
    },
    'negativeTermsBySemantic': {
      for (final key in negativesBySemantic.keys.toList()..sort())
        key: negativesBySemantic[key]!.length,
    },
    'insufficientFrequentSemantics': insufficientFrequentSemantics,
    'narrowSemanticExceptions': narrowExceptions,
    'uncoveredFrequentSemantics': uncoveredSemantics,
    'duplicateCanonicalNames': duplicateCanonicals,
    'detectedConflictingAliases': conflictingAliases.toList()..sort(),
    'unresolvedConflictingAliases': const <String>[],
    'detectedConflictingTerms': detectedConflictingTerms.toList()..sort(),
    'resolvedConflictingTermOwners': _conflictTermOwners,
    'unresolvedConflictingTerms': unresolvedConflictingTerms.toList()..sort(),
    'highRiskAliases': highRiskAliases,
    'shortHighRiskTerms':
        positiveTerms.where((term) => term.runes.length <= 2).toList()..sort(),
    'unresolvedHighRiskAliases': const <String>[],
    'reviewSampleCount': sampleResult.total,
    'reviewSampleCorrect': sampleResult.correct,
    'reviewSampleAccuracy': sampleResult.accuracy,
    'reviewSampleFailures': sampleResult.failures,
    'reviewSampleKindDistribution': _counts(
      (reviewSamples['samples']! as List).map(
        (item) => (item as Map)['kind']! as String,
      ),
    ),
    'entityAuditRequested': entityAudit.requested,
    'entityAuditMatched': entityAudit.matched,
    'entityAuditMissing': entityAudit.missing,
    'lexiconAuditRequested': lexiconAudit.requested,
    'lexiconAuditMatched': lexiconAudit.matched,
    'lexiconAuditMissing': lexiconAudit.missing,
    'runtimeAssetBytes': runtimeSize,
  };
  _writePretty('tools/knowledge/quality_report.json', report);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));

  final failures = <String>[];
  if (runtimeEntities.length < _minimumEntities) {
    failures.add('approved runtime entities < $_minimumEntities');
  }
  if (normalizedRuntimeAliases.length < _minimumAliases) {
    failures.add('normalized aliases < $_minimumAliases');
  }
  if (positiveTerms.length < _minimumPositiveTerms) {
    failures.add('positive terms < $_minimumPositiveTerms');
  }
  if (negativeTerms.length < _minimumNegativeTerms) {
    failures.add('negative/conflict terms < $_minimumNegativeTerms');
  }
  if (mainlandEntities / runtimeEntities.length < _minimumMainlandShare) {
    failures.add('mainland merchant/service/platform share < 80%');
  }
  if (lowValueEntities / runtimeEntities.length > 0.10) {
    failures.add('media/game title share > 10%');
  }
  if (sceneCoverage < _minimumSceneCoverage) {
    failures.add('real-scene semantic coverage < $_minimumSceneCoverage');
  }
  if (sampleResult.accuracy < 0.98) {
    failures.add('review sample accuracy < 0.98');
  }
  if (sampleResult.total < _minimumReviewSamples) {
    failures.add('review samples < $_minimumReviewSamples');
  }
  if (entityAudit.requested < 50 || entityAudit.missing.isNotEmpty) {
    failures.add('entity audit < 50 or contains missing values');
  }
  if (lexiconAudit.requested < 100 || lexiconAudit.missing.isNotEmpty) {
    failures.add('lexicon audit < 100 or contains missing values');
  }
  if (insufficientFrequentSemantics.isNotEmpty) {
    failures.add('frequent semantic term/negative coverage insufficient');
  }
  if (conflictingAliases.isNotEmpty) {
    failures.add('unresolved alias conflicts');
  }
  if (unresolvedConflictingTerms.isNotEmpty) {
    failures.add('unresolved lexicon term conflicts');
  }
  if (runtimeSize >= _runtimeHardLimit) {
    failures.add('runtime assets >= 2 MiB');
  }
  if (failures.isNotEmpty) {
    throw StateError('Knowledge quality gates failed: ${failures.join(', ')}');
  }
}

({int total, int correct, double accuracy, List<String> failures})
_validateSamples({
  required Map<String, Object?> reviewSamples,
  required KnowledgeCatalog catalog,
}) {
  final failures = <String>[];
  var correct = 0;
  final entityMatcher = EntityMatcher(catalog);
  final lexiconMatcher = LexiconMatcher(catalog);
  final familyMatcher = LexicalFamilyMatcher(catalog);
  final compositionalMatcher = CompositionalMatcher(catalog);
  const resolver = SpanConflictResolver();
  const fusion = EvidenceFusion();
  final samples = (reviewSamples['samples']! as List).cast<Map>();
  for (final raw in samples) {
    final sample = raw.cast<String, Object?>();
    final text = RecognitionNormalizer.normalizeCharacters(
      sample['text']! as String,
    );
    final expected = sample['semanticKey']! as String;
    final familyMatches = resolver.resolveFamilyMatches(
      familyMatcher.match(text),
    );
    final semanticEvidence = resolver.resolveEvidence([
      ...entityMatcher.evidence(entityMatcher.match(text)),
      ...lexiconMatcher.match(text),
    ], familyMatches: familyMatches);
    final fused = fusion.fuse([
      ...semanticEvidence,
      ...compositionalMatcher.match(familyMatches),
    ]);
    final matched = fused.semanticKey == expected;
    if (matched) {
      correct++;
    } else {
      failures.add('${sample['kind']}:${sample['text']}=>$expected');
    }
  }
  return (
    total: samples.length,
    correct: correct,
    accuracy: samples.isEmpty ? 0 : correct / samples.length,
    failures: failures,
  );
}

({
  int familyCount,
  int termCount,
  int ruleCount,
  List<String> shortHighRiskTerms,
})
_validateCompositionKnowledge({
  required Map<String, Object?> familySource,
  required Map<String, Object?> ruleSource,
  required Set<String?> validSemantics,
}) {
  final familyIds = <String>{};
  final normalizedTerms = <String>{};
  final shortHighRiskTerms = <String>[];
  var termCount = 0;
  for (final raw in familySource['families']! as List) {
    final family = (raw as Map).cast<String, Object?>();
    final id = family['id'] as String?;
    if (id == null || id.trim().isEmpty || !familyIds.add(id)) {
      throw FormatException('词汇 family id 为空或重复: $id');
    }
    final terms = (family['terms'] as List? ?? const []).cast<String>();
    if (terms.isEmpty) throw FormatException('$id family term 不得为空');
    for (final term in terms) {
      final normalized = _normalize(term);
      if (normalized.isEmpty) throw FormatException('$id 包含空 family term');
      if (!normalizedTerms.add('$id:$normalized')) {
        throw FormatException('$id 包含重复 family term: $term');
      }
      if (normalized.runes.length <= 1) shortHighRiskTerms.add('$id:$term');
      termCount++;
    }
  }
  final ruleIds = <String>{};
  final pairOwners = <String, String>{};
  final rules = (ruleSource['rules']! as List).cast<Map>();
  for (final raw in rules) {
    final rule = raw.cast<String, Object?>();
    final id = rule['id'] as String?;
    if (id == null || id.trim().isEmpty || !ruleIds.add(id)) {
      throw FormatException('组合 rule id 为空或重复: $id');
    }
    final left = rule['leftFamily']! as String;
    final right = rule['rightFamily']! as String;
    if (!familyIds.contains(left) || !familyIds.contains(right)) {
      throw FormatException('$id 引用不存在的 family: $left + $right');
    }
    final semantic = rule['semanticKey']! as String;
    if (!validSemantics.contains(semantic)) {
      throw FormatException('$id 使用无效 taxonomy: $semantic');
    }
    final maxDistance = rule['maxDistance'] as int?;
    final score = (rule['score'] as num?)?.toDouble();
    if (maxDistance == null || maxDistance < 0 || maxDistance > 20) {
      throw FormatException('$id maxDistance 超出 0..20');
    }
    if (score == null || score < 0.40 || score > 0.99) {
      throw FormatException('$id score 超出 0.40..0.99');
    }
    final pair = [left, right]..sort();
    final pairKey = pair.join('+');
    final previous = pairOwners[pairKey];
    if (previous != null) {
      throw FormatException('重复或冲突组合 rule: $previous / $id');
    }
    pairOwners[pairKey] = id;
  }
  shortHighRiskTerms.sort();
  return (
    familyCount: familyIds.length,
    termCount: termCount,
    ruleCount: rules.length,
    shortHighRiskTerms: shortHighRiskTerms,
  );
}

String _entityKind(String? value) => switch (value) {
  'platform' => 'platform',
  'service' => 'service',
  'mediaTitle' || 'media title' || 'media/game title' => 'mediaTitle',
  'gameTitle' || 'game title' => 'gameTitle',
  'productBrand' || 'product brand' => 'productBrand',
  _ => 'merchant',
};

List<Map<String, Object?>> _expandGroupedEntities(
  Map<String, Object?> source,
) => [
  for (final rawGroup in (source['groups']! as List))
    for (final rawRecord in ((rawGroup as Map)['records']! as List))
      {
        'canonicalName': (rawRecord as List)[0] as String,
        'aliases': rawRecord.skip(1).cast<String>().toList(),
        'semanticKey': rawGroup['semanticKey'],
        'kind': rawGroup['kind'] ?? 'merchant',
        'breadth': rawGroup['breadth'] ?? 'specific',
        'confidence': rawGroup['confidence'] ?? 0.90,
        'reviewStatus': 'approved',
        'market': source['market'] ?? 'CN-mainland',
        '_source': 'curated',
      },
];

({int requested, int matched, List<String> missing}) _validateAuditList({
  required Iterable<String> values,
  required Iterable<String> available,
  bool normalizeValues = false,
}) {
  final expected = values.toList();
  final haystack = available
      .map((value) => normalizeValues ? _normalize(value) : value)
      .toSet();
  final missing = [
    for (final value in expected)
      if (!haystack.contains(normalizeValues ? _normalize(value) : value))
        value,
  ];
  return (
    requested: expected.length,
    matched: expected.length - missing.length,
    missing: missing,
  );
}

String _defaultRole(String semantic) {
  if (semantic.contains('.clinic') ||
      semantic.contains('.hotel') ||
      semantic.contains('.venue')) {
    return 'venue';
  }
  if (semantic.contains('.taxi') ||
      semantic.contains('.parking') ||
      semantic.contains('.reimbursement')) {
    return 'action';
  }
  return 'product';
}

String _defaultSpecificity(String role) => switch (role) {
  'product' || 'action' || 'service' => 'specific',
  'platform' => 'broad',
  _ => 'general',
};

bool _isHighRiskAlias(String alias) =>
    alias.runes.length <= 3 || RegExp(r'^\d+$').hasMatch(alias);

bool _exactOnlyAlias(String alias) =>
    RegExp(r'^\d+$').hasMatch(alias) ||
    (RegExp(r'^[a-z]+$').hasMatch(alias) && alias.length <= 3);

Map<String, int> _counts(Iterable<String> values) {
  final result = <String, int>{};
  for (final value in values) {
    result.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return result;
}

Map<String, Object?> _read(String path) {
  final content = File(path).readAsStringSync().replaceFirst('\uFEFF', '');
  return (jsonDecode(content) as Map).cast<String, Object?>();
}

void _writeCompact(String path, Object value) =>
    File(path).writeAsStringSync(jsonEncode(value));

void _writePretty(String path, Object value) => File(
  path,
).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');

String _normalize(String value) => RecognitionNormalizer.indexKey(value);

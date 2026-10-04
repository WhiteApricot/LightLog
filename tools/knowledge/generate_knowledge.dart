import 'dart:convert';
import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/domain/normalization.dart';

const _runtimeHardLimit = 2 * 1024 * 1024;
const _minimumSceneCoverage = 0.90;
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
  'expense.shopping.clothing',
  'expense.shopping.beauty',
  'expense.shopping.home',
  'expense.shopping.appliance',
  'expense.housing.rent',
  'expense.housing.utilities',
  'expense.daily.household',
  'expense.daily.haircut',
  'expense.daily.service',
  'expense.entertainment.movie',
  'expense.entertainment.game',
  'expense.entertainment.subscription',
  'expense.education.book',
  'expense.medical.clinic',
  'expense.medical.medicine',
  'expense.communication.mobile',
  'expense.communication.internet',
  'expense.travel.hotel',
  'expense.sports.fitness',
  'expense.pets.food',
  'expense.pets.medical',
  'expense.digital.accessory',
  'expense.digital.software',
  'expense.digital.repair',
  'income.salary.monthly',
  'income.salary.bonus',
  'income.reimbursement.work',
  'income.parttime.freelance',
  'income.investment.interest',
  'income.other.secondhand',
};

void main() {
  final validSemantics = defaultCategories
      .map((item) => item.semanticKey)
      .toSet();
  final curated = _read('tools/knowledge/merchants_source.json');
  final snapshot = _read('tools/knowledge/source_data/wikidata_entities.json');
  final lexiconSource = _read('tools/knowledge/category_lexicon_source.json');
  final reviewSamples = _read('tools/knowledge/review_samples.json');

  final rawEntities = <Map<String, Object?>>[
    for (final raw in (curated['records']! as List))
      {...(raw as Map).cast<String, Object?>(), '_source': 'curated'},
    for (final raw in (snapshot['records']! as List))
      {...(raw as Map).cast<String, Object?>(), '_source': 'snapshot'},
  ];
  final excludedSnapshot = rawEntities.where((item) {
    return item['_source'] == 'snapshot' && item['reviewStatus'] != 'approved';
  }).length;
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
    });
  }

  final aliasOwners = <String, Set<int>>{};
  for (var index = 0; index < candidates.length; index++) {
    for (final alias
        in (candidates[index]['aliases']! as List).cast<String>()) {
      aliasOwners.putIfAbsent(_normalize(alias), () => <int>{}).add(index);
    }
  }
  final conflictingAliases = aliasOwners.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toSet();
  final runtimeEntities = <Map<String, Object?>>[];
  var aliasCount = 0;
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
    aliasCount += aliases.length + 1;
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
    });
  }

  final runtimeLexicon = <Map<String, Object?>>[];
  for (final raw in (lexiconSource['entries']! as List)) {
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
  final termsBySemantic = <String, Set<String>>{};
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
      termsBySemantic.putIfAbsent(semantic, () => <String>{}).add(key);
    }
    for (final term in (item['negative']! as List).cast<String>()) {
      negativeTerms.add(_normalize(term));
    }
  }
  final conflictingTerms = termOwners.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toSet();
  for (final item in runtimeLexicon) {
    item['keywords'] = (item['keywords']! as List)
        .cast<String>()
        .where((term) => !conflictingTerms.contains(_normalize(term)))
        .toList();
    item['aliases'] = (item['aliases']! as List)
        .cast<String>()
        .where((term) => !conflictingTerms.contains(_normalize(term)))
        .toList();
  }
  final positiveTerms = termOwners.keys.toSet()..removeAll(conflictingTerms);
  final coveredScenes = _requiredSceneSemantics.where(
    (key) => (termsBySemantic[key] ?? const <String>{}).any(
      (term) => !conflictingTerms.contains(term),
    ),
  );
  final sceneCoverage = coveredScenes.length / _requiredSceneSemantics.length;
  final sampleResult = _validateSamples(
    reviewSamples: reviewSamples,
    entities: runtimeEntities,
    lexicon: runtimeLexicon,
  );

  final merchantRuntime = {'version': 3, 'records': runtimeEntities};
  final lexiconRuntime = {'version': 3, 'entries': runtimeLexicon};
  Directory('assets/knowledge').createSync(recursive: true);
  _writeCompact('assets/knowledge/merchants.json', merchantRuntime);
  _writeCompact('assets/knowledge/category_lexicon.json', lexiconRuntime);
  final runtimeSize =
      File('assets/knowledge/merchants.json').lengthSync() +
      File('assets/knowledge/category_lexicon.json').lengthSync();
  final highRiskAliases = aliasOwners.keys.where(_isHighRiskAlias).toList()
    ..sort();
  final report = <String, Object?>{
    'canonicalEntityCount': runtimeEntities.length,
    'aliasCount': aliasCount,
    'lexiconEntryCount': runtimeLexicon.length,
    'positiveTermCount': positiveTerms.length,
    'negativeTermCount': negativeTerms.length,
    'sceneSemanticCoverage': sceneCoverage,
    'requiredSceneSemanticCount': _requiredSceneSemantics.length,
    'excludedUnreviewedSnapshotEntities': excludedSnapshot,
    'entityKindDistribution': _counts(
      runtimeEntities.map((item) => item['kind']! as String),
    ),
    'entityBreadthDistribution': _counts(
      runtimeEntities.map((item) => item['breadth']! as String),
    ),
    'entityReviewDistribution': _counts(
      runtimeEntities.map((item) => item['reviewStatus']! as String),
    ),
    'lexiconRoleDistribution': _counts(
      runtimeLexicon.map((item) => item['role']! as String),
    ),
    'duplicateCanonicalNames': duplicateCanonicals,
    'detectedConflictingAliases': conflictingAliases.toList()..sort(),
    'unresolvedConflictingAliases': const <String>[],
    'detectedConflictingTerms': conflictingTerms.toList()..sort(),
    'unresolvedConflictingTerms': const <String>[],
    'highRiskAliases': highRiskAliases,
    'unresolvedHighRiskAliases': const <String>[],
    'reviewSampleCount': sampleResult.total,
    'reviewSampleCorrect': sampleResult.correct,
    'reviewSampleAccuracy': sampleResult.accuracy,
    'reviewSampleFailures': sampleResult.failures,
    'runtimeAssetBytes': runtimeSize,
  };
  _writePretty('tools/knowledge/quality_report.json', report);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));

  final failures = <String>[];
  if (runtimeEntities.isEmpty) failures.add('no reviewed runtime entities');
  if (positiveTerms.isEmpty) failures.add('no reviewed positive terms');
  if (sceneCoverage < _minimumSceneCoverage) {
    failures.add('real-scene semantic coverage < $_minimumSceneCoverage');
  }
  if (sampleResult.accuracy < 0.98) {
    failures.add('review sample accuracy < 0.98');
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
  required List<Map<String, Object?>> entities,
  required List<Map<String, Object?>> lexicon,
}) {
  final failures = <String>[];
  var correct = 0;
  final samples = (reviewSamples['samples']! as List).cast<Map>();
  for (final raw in samples) {
    final sample = raw.cast<String, Object?>();
    final text = _normalize(sample['text']! as String);
    final expected = sample['semanticKey']! as String;
    final matched = sample['kind'] == 'entity'
        ? entities.any((item) {
            final aliases = <String>[
              item['canonicalName']! as String,
              ...(item['aliases']! as List).cast<String>(),
            ];
            return item['semanticKey'] == expected &&
                aliases.any((alias) => _normalize(alias) == text);
          })
        : lexicon.any((item) {
            final terms = <String>[
              ...(item['keywords']! as List).cast<String>(),
              ...(item['aliases']! as List).cast<String>(),
            ];
            return item['semanticKey'] == expected &&
                terms.any((term) => _normalize(term) == text);
          });
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

String _entityKind(String? value) => switch (value) {
  'platform' => 'platform',
  'service' => 'service',
  'mediaTitle' || 'media title' || 'media/game title' => 'mediaTitle',
  'gameTitle' || 'game title' => 'gameTitle',
  'productBrand' || 'product brand' => 'productBrand',
  _ => 'merchant',
};

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

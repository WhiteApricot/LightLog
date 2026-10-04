import 'dart:convert';
import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/domain/normalization.dart';

const _sourceId = 'phase3CandidateLexiconV1';
const _positiveFields = ['positiveTerms', 'colloquialTerms'];
const _contextFields = ['actions', 'objects', 'modifiers'];
const _templatePattern =
    r'(?:通知|记录|明细|截图|页面|入口|教程|攻略|推荐|哪个好|怎么样|如何|怎么|附近|查询|搜索|排名|排行榜|测评|评测|申请|审核|流程|标准|比例|凭证上传|发票抬头)';
const _genericTerms = {
  '消费',
  '付款',
  '支付',
  '花钱',
  '买东西',
  '费用',
  '账单',
  '订单',
  '服务',
  '商品',
  '充值',
  '缴费',
  '礼物',
  '其他',
  '成功',
  '失败',
  '取消',
  '处理中',
  '待支付',
  '已支付',
};

void main(List<String> args) {
  final options = _options(args);
  final candidatePath = options['candidate'];
  final reportPath = options['report'];
  final reviewPath = options['review'];
  if (candidatePath == null || reportPath == null || reviewPath == null) {
    throw ArgumentError(
      'Usage: dart tools/knowledge/prepare_lexicon_candidates.dart '
      '--candidate <candidate.json> --report <report.json> '
      '--review <review.json>',
    );
  }

  final candidate = _read(candidatePath);
  final base = _read('tools/knowledge/category_lexicon_source.json');
  final expansion = _read('tools/knowledge/lexicon_expansion_source.json');
  final categories = (candidate['categories'] as List?)
      ?.cast<Map<String, Object?>>();
  final conflicts = (candidate['crossCategoryConflicts'] as List?)
      ?.cast<Map<String, Object?>>();
  if (candidate['version'] == null || categories == null || conflicts == null) {
    throw const FormatException('Candidate schema is missing required fields.');
  }

  final seedBySemantic = {
    for (final seed in defaultCategories) seed.semanticKey: seed,
  };
  final validLeafSemantics = {
    for (final seed in defaultCategories)
      if (seed.parentId != null) seed.semanticKey,
  };
  final existingOwners = <String, Set<String>>{};
  final existingBySemantic = <String, Set<String>>{};
  for (final raw in <Object?>[
    ...(base['entries']! as List),
    ...(expansion['entries']! as List),
  ]) {
    final entry = (raw as Map).cast<String, Object?>();
    if (entry['sourceId'] == _sourceId) continue;
    final semantic = entry['semanticKey']! as String;
    for (final term in <String>[
      ...(entry['keywords']! as List).cast<String>(),
      ...(entry['aliases'] as List? ?? const []).cast<String>(),
    ]) {
      final normalized = _normalize(term);
      existingOwners.putIfAbsent(normalized, () => <String>{}).add(semantic);
      existingBySemantic
          .putIfAbsent(semantic, () => <String>{})
          .add(normalized);
    }
  }
  final currentCounts = {
    for (final entry in existingBySemantic.entries)
      entry.key: entry.value.length,
  };

  final explicitConflictTerms = <String>{};
  for (final raw in conflicts) {
    final term = raw['term'] as String?;
    if (term != null && term.trim().isNotEmpty) {
      explicitConflictTerms.add(_normalize(term));
    }
  }

  final negativeOwners = <String, Set<String>>{};
  final occurrences = <String, _CandidateAggregate>{};
  final invalidTaxonomy = <String>[];
  var rawPositiveCount = 0;
  var rawNegativeCount = 0;
  for (final category in categories) {
    final semantic = category['semanticKey'] as String?;
    if (semantic == null || !validLeafSemantics.contains(semantic)) {
      invalidTaxonomy.add(semantic ?? '(missing)');
      continue;
    }
    final seed = seedBySemantic[semantic]!;
    final parent =
        seedBySemantic[defaultCategories
            .firstWhere((item) => item.id == seed.parentId)
            .semanticKey]!;
    if (category['name'] != seed.name || category['parent'] != parent.name) {
      invalidTaxonomy.add(semantic);
      continue;
    }

    final contextTerms = <String>{};
    for (final field in _contextFields) {
      contextTerms.addAll(_splitTerms(category[field]));
    }
    for (final field in _positiveFields) {
      for (final term in _splitTerms(category[field])) {
        rawPositiveCount++;
        final normalized = _normalize(term);
        if (normalized.isEmpty) continue;
        final aggregate = occurrences.putIfAbsent(
          normalized,
          () => _CandidateAggregate(normalized),
        );
        aggregate.originals.add(term);
        aggregate.owners.add(semantic);
        aggregate.sources.add(field);
        if (contextTerms.any((value) => _normalize(value) == normalized)) {
          aggregate.sources.add('contextField');
        }
      }
    }
    for (final field in ['negativeTerms', 'conflictTerms']) {
      for (final term in _splitTerms(category[field])) {
        rawNegativeCount++;
        if (field == 'conflictTerms') {
          negativeOwners
              .putIfAbsent(_normalize(term), () => <String>{})
              .add(semantic);
        }
      }
    }
  }
  if (invalidTaxonomy.isNotEmpty) {
    throw FormatException(
      'Candidate taxonomy mismatch: ${invalidTaxonomy.toSet().toList()..sort()}',
    );
  }

  final decisions = <_Decision>[];
  for (final aggregate in occurrences.values) {
    final semantic = aggregate.owners.length == 1
        ? aggregate.owners.single
        : null;
    final existing = existingOwners[aggregate.normalized] ?? const <String>{};
    final hardReason = _hardRejectionReason(
      aggregate,
      semantic: semantic,
      existingOwners: existing,
      explicitConflictTerms: explicitConflictTerms,
      negativeOwners: negativeOwners[aggregate.normalized] ?? const <String>{},
    );
    if (hardReason != null) {
      decisions.add(
        _Decision.rejected(aggregate, semantic, hardReason, score: 0),
      );
      continue;
    }
    final score = _score(aggregate, currentCount: currentCounts[semantic] ?? 0);
    decisions.add(
      score.total >= 75
          ? _Decision.reviewable(aggregate, semantic!, score)
          : _Decision.rejected(
              aggregate,
              semantic,
              'scoreBelowThreshold',
              score: score.total,
              components: score.components,
            ),
    );
  }

  final reviewableBySemantic = <String, List<_Decision>>{};
  for (final decision in decisions.where((item) => item.reviewable)) {
    reviewableBySemantic
        .putIfAbsent(decision.semanticKey!, () => <_Decision>[])
        .add(decision);
  }
  for (final entry in reviewableBySemantic.entries) {
    final currentCount = currentCounts[entry.key] ?? 0;
    final cap = currentCount < 10
        ? 50
        : currentCount < 20
        ? 45
        : currentCount < 40
        ? 40
        : 35;
    entry.value.sort(_compareCandidates);
    for (var index = 0; index < entry.value.length; index++) {
      final decision = entry.value[index];
      if (index < cap) {
        decision.accept('semanticReviewAccepted');
      } else {
        decision.reject('semanticReviewCap');
      }
    }
  }

  decisions.sort((left, right) {
    final semantic = (left.semanticKey ?? '').compareTo(
      right.semanticKey ?? '',
    );
    return semantic != 0
        ? semantic
        : left.aggregate.normalized.compareTo(right.aggregate.normalized);
  });
  final accepted = decisions.where((item) => item.decision == 'accepted');
  final acceptedBySemantic = <String, List<_Decision>>{};
  for (final decision in accepted) {
    acceptedBySemantic
        .putIfAbsent(decision.semanticKey!, () => <_Decision>[])
        .add(decision);
  }
  final reasonCounts = <String, int>{};
  final decisionCounts = <String, int>{};
  for (final decision in decisions) {
    decisionCounts.update(
      decision.decision,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    reasonCounts.update(
      decision.reason,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
  }

  final summary = <String, Object?>{
    'sourceId': _sourceId,
    'candidateVersion': candidate['version'],
    'candidateCategoryCount': categories.length,
    'candidateConflictCount': conflicts.length,
    'rawPositiveOccurrences': rawPositiveCount,
    'uniqueNormalizedPositiveCandidates': occurrences.length,
    'rawNegativeConflictOccurrences': rawNegativeCount,
    'acceptedPositiveTerms': accepted.length,
    'acceptedNegativeTerms': 0,
    'decisionCounts': decisionCounts,
    'reasonCounts': reasonCounts,
    'acceptedBySemantic': {
      for (final key in acceptedBySemantic.keys.toList()..sort())
        key: acceptedBySemantic[key]!.length,
    },
    'coveredSemanticCount': acceptedBySemantic.length,
    'candidateSemanticCount': categories.length,
  };
  final report = <String, Object?>{
    'summary': summary,
    'policy': {
      'minimumScore': 75,
      'minimumRuneLength': 3,
      'maximumRuneLength': 12,
      'negativeImportPolicy':
          'No bulk import; candidate negatives remain analysis-only.',
      'primarySemanticPolicy': 'Exactly one owner for every accepted term.',
    },
    'decisions': decisions.map((item) => item.toJson()).toList(),
  };
  final review = <String, Object?>{
    'sourceId': _sourceId,
    'summary': summary,
    'acceptedGroups': [
      for (final semantic in acceptedBySemantic.keys.toList()..sort())
        {
          'semanticKey': semantic,
          'role': _defaultRole(semantic),
          'specificity': 'specific',
          'score': 0.80,
          'reviewStatus': 'approved',
          'keywords': [
            for (final item
                in acceptedBySemantic[semantic]!..sort(_compareCandidates))
              item.aggregate.originals.toList()..sort(),
          ].expand((items) => items).toList(),
          'aliases': const <String>[],
          'negative': const <String>[],
        },
    ],
  };
  _writeCompact(reportPath, report);
  _writePretty(reviewPath, review);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(summary));
  if (accepted.length < 3000 || accepted.length > 6000) {
    stderr.writeln(
      'Candidate selection is outside the 3000..6000 target: '
      '${accepted.length}. Review quality before merging.',
    );
    exitCode = 2;
  }
}

String? _hardRejectionReason(
  _CandidateAggregate aggregate, {
  required String? semantic,
  required Set<String> existingOwners,
  required Set<String> explicitConflictTerms,
  required Set<String> negativeOwners,
}) {
  final term = aggregate.normalized;
  final length = term.runes.length;
  if (semantic == null) return 'crossCategoryPositiveConflict';
  if (existingOwners.contains(semantic)) return 'exactExisting';
  if (existingOwners.isNotEmpty) return 'existingCrossCategoryConflict';
  if (semantic == 'expense.medical.clinic' &&
      RegExp(r'眼科|验光|视力|配眼镜').hasMatch(term)) {
    return 'taxonomyBoundaryMismatch';
  }
  if (length <= 2) return 'shortHighRisk';
  if (length > 12) return 'syntheticLongPhrase';
  if (!RegExp(r'[a-zA-Z\u3400-\u9fff]').hasMatch(term)) {
    return 'nonLexicalToken';
  }
  if (_genericTerms.contains(term)) return 'ambiguousGenericTerm';
  if (explicitConflictTerms.contains(term)) return 'declaredAmbiguity';
  if (negativeOwners.any((owner) => owner != semantic)) {
    return 'crossCategoryNegativeConflict';
  }
  if (RegExp(_templatePattern).hasMatch(term)) return 'lowValueTemplate';
  if (_isRepeatedPhrase(term)) return 'syntheticRepetition';
  return null;
}

({int total, Map<String, int> components}) _score(
  _CandidateAggregate aggregate, {
  required int currentCount,
}) {
  final length = aggregate.normalized.runes.length;
  final components = <String, int>{
    'semanticPrecision': 30,
    'realBookkeepingUsage': length <= 8 ? 20 : 14,
    'weakCoverageGain': currentCount < 10
        ? 15
        : currentCount < 20
        ? 12
        : currentCount < 40
        ? 8
        : 5,
    'specificity': length >= 4 ? 15 : 10,
    'naturalColloquialForm': aggregate.sources.contains('colloquialTerms')
        ? 10
        : 6,
    'independentSourceValue': aggregate.sources.length >= 3
        ? 10
        : aggregate.sources.length == 2
        ? 6
        : 0,
  };
  return (
    total: components.values.fold(0, (sum, value) => sum + value),
    components: components,
  );
}

int _compareCandidates(_Decision left, _Decision right) {
  final score = right.score.compareTo(left.score);
  if (score != 0) return score;
  final length = left.aggregate.normalized.runes.length.compareTo(
    right.aggregate.normalized.runes.length,
  );
  return length != 0
      ? length
      : left.aggregate.normalized.compareTo(right.aggregate.normalized);
}

bool _isRepeatedPhrase(String value) {
  final runes = value.runes.toList();
  if (runes.length.isOdd || runes.length < 4) return false;
  final half = runes.length ~/ 2;
  for (var index = 0; index < half; index++) {
    if (runes[index] != runes[index + half]) return false;
  }
  return true;
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

List<String> _splitTerms(Object? value) {
  final values = switch (value) {
    String text => text.split(RegExp(r'\s+')),
    List items => items.whereType<String>(),
    _ => const <String>[],
  };
  return values
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _normalize(String value) => RecognitionNormalizer.indexKey(value);

Map<String, String> _options(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--candidate' ||
        argument == '--report' ||
        argument == '--review') {
      if (index + 1 >= args.length) {
        throw ArgumentError('Missing value for $argument');
      }
      result[argument.substring(2)] = args[++index];
    }
  }
  return result;
}

Map<String, Object?> _read(String path) => (jsonDecode(
  File(path).readAsStringSync().replaceFirst('\uFEFF', ''),
) as Map).cast<String, Object?>();

void _writePretty(String path, Object value) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(value)}\n',
  );
}

void _writeCompact(String path, Object value) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync('${jsonEncode(value)}\n');
}

class _CandidateAggregate {
  _CandidateAggregate(this.normalized);

  final String normalized;
  final Set<String> originals = {};
  final Set<String> owners = {};
  final Set<String> sources = {};
}

class _Decision {
  _Decision({
    required this.aggregate,
    required this.semanticKey,
    required this.decision,
    required this.reason,
    required this.score,
    required this.components,
    required this.reviewable,
  });

  factory _Decision.reviewable(
    _CandidateAggregate aggregate,
    String semantic,
    ({int total, Map<String, int> components}) score,
  ) => _Decision(
    aggregate: aggregate,
    semanticKey: semantic,
    decision: 'pending',
    reason: 'scoreQualified',
    score: score.total,
    components: score.components,
    reviewable: true,
  );

  factory _Decision.rejected(
    _CandidateAggregate aggregate,
    String? semantic,
    String reason, {
    required int score,
    Map<String, int> components = const {},
  }) => _Decision(
    aggregate: aggregate,
    semanticKey: semantic,
    decision: 'rejected',
    reason: reason,
    score: score,
    components: components,
    reviewable: false,
  );

  final _CandidateAggregate aggregate;
  final String? semanticKey;
  String decision;
  String reason;
  final int score;
  final Map<String, int> components;
  final bool reviewable;

  void accept(String value) {
    decision = 'accepted';
    reason = value;
  }

  void reject(String value) {
    decision = 'rejected';
    reason = value;
  }

  Map<String, Object?> toJson() => {
    'term': aggregate.originals.toList()..sort(),
    'normalizedTerm': aggregate.normalized,
    'semanticKey': semanticKey,
    'candidateOwners': aggregate.owners.toList()..sort(),
    'sources': aggregate.sources.toList()..sort(),
    'decision': decision,
    'reason': reason,
    'score': score,
    'scoreComponents': components,
  };
}

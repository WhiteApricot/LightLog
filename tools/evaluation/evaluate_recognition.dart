import 'dart:convert';
import 'dart:io';

import 'package:light_log/features/recognition/domain/normalization.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

import '../recognition_tool_harness.dart';
import 'knowledge_hash.dart';

void main(List<String> args) {
  final options = _options(args);
  final corpusPath =
      options['corpus'] ?? const String.fromEnvironment('BLIND_CORPUS');
  final reportPath =
      options['report'] ?? const String.fromEnvironment('BLIND_REPORT');
  if (corpusPath.isEmpty) {
    throw StateError('Pass --corpus <corpus.json> or BLIND_CORPUS');
  }
  if (reportPath.endsWith('_initial.json') && File(reportPath).existsSync()) {
    throw StateError('Initial evaluation report is immutable: $reportPath');
  }
  final root = (jsonDecode(File(corpusPath).readAsStringSync()) as Map)
      .cast<String, Object?>();
  final isBaselineReport = root['cases'] == null && root['failures'] != null;
  final metadata = isBaselineReport
      ? <String, Object?>{
          'name': '${root['corpus']} baseline failure subset',
          'version': root['corpusVersion'],
          'referenceNow': '2026-10-04T14:30:00',
        }
      : (root['metadata']! as Map).cast<String, Object?>();
  final now = _wallTime(metadata['referenceNow']! as String);
  final harness = RecognitionToolHarness();
  final categoryById = {
    for (final item in RecognitionToolHarness.categories) item.id: item,
  };
  final cases = isBaselineReport
      ? [
          for (final raw in (root['failures']! as List))
            {
              'id': (raw as Map)['id'],
              'priority': raw['priority'],
              'group': raw['group'],
              'input': raw['input'],
              'setup': <String, Object?>{},
              'expected': raw['expected'],
            },
        ]
      : (root['cases']! as List).cast<Map<String, Object?>>();
  for (var index = 0; index < 1000; index++) {
    harness.recognize(
      cases[index % cases.length]['input']! as String,
      now: now,
    );
  }

  final results = <Map<String, Object?>>[];
  final latencies = <int>[];
  for (final testCase in cases) {
    final setup = (testCase['setup']! as Map).cast<String, Object?>();
    final history = <PersonalHistoryRecord>[];
    for (final raw in (setup['history'] as List? ?? const [])) {
      final item = (raw as Map).cast<String, Object?>();
      final category = categoryById[item['subcategoryId']! as String]!;
      history.add(
        PersonalHistoryRecord(
          normalizedContent: item['normalizedContent']! as String,
          semanticKey: category.semanticKey!,
          hitCount: item['hitCount']! as int,
          correctionCount: item['correctionCount']! as int,
          lastUsedAt: now.millisecondsSinceEpoch,
        ),
      );
    }
    final stopwatch = Stopwatch()..start();
    final candidate = harness.recognize(
      testCase['input']! as String,
      now: now,
      history: history,
    );
    stopwatch.stop();
    latencies.add(stopwatch.elapsedMicroseconds);
    results.add(_evaluate(testCase, candidate));
  }
  latencies.sort();
  final failures = results.where((item) => item['correct'] != true).toList();
  final report = <String, Object?>{
    'corpus': metadata['name'],
    'corpusVersion': metadata['version'],
    'recognizerVersion': 3,
    'knowledgeHash': knowledgeHash(),
    'evaluatedAt': DateTime.now().toUtc().toIso8601String(),
    'totalCases': results.length,
    'priority': {
      for (final priority in ['P0', 'P1', 'P2'])
        priority: _priority(results, priority),
    },
    'p2SafeRejectionRate': _rate(
      results.where((item) => item['priority'] == 'P2'),
      (item) => item['safe'] == true,
    ),
    'amountAccuracy': _fieldAccuracy(results, 'amountCorrect'),
    'typeAccuracy': _fieldAccuracy(results, 'typeCorrect'),
    'categoryAccuracy': _fieldAccuracy(results, 'categoryCorrect'),
    'parentCategoryAccuracy': _fieldAccuracy(results, 'parentCorrect'),
    'childCategoryAccuracy': _fieldAccuracy(results, 'categoryCorrect'),
    'categoryNullCount': results
        .where((r) => (r['actual'] as Map)['categoryId'] == null)
        .length,
    'wrongCategoryCount': results
        .where(
          (r) =>
              r['categoryCorrect'] == false &&
              (r['actual'] as Map)['categoryId'] != null,
        )
        .length,
    'routingFailureBreakdown': {
      'noSemanticOutput': results
          .where(
            (r) =>
                r['categoryCorrect'] == false &&
                (r['actual'] as Map)['semanticKey'] == null,
          )
          .length,
      'noCategoryOutput': results
          .where(
            (r) =>
                r['categoryCorrect'] == false &&
                (r['actual'] as Map)['categoryId'] == null,
          )
          .length,
      'wrongParent': results
          .where(
            (r) =>
                r['parentCorrect'] == false &&
                (r['actual'] as Map)['categoryId'] != null,
          )
          .length,
      'correctParentWrongChild': results
          .where(
            (r) => r['parentCorrect'] == true && r['categoryCorrect'] == false,
          )
          .length,
      'wrongType': results.where((r) => r['typeCorrect'] == false).length,
    },
    'timeAccuracy': _fieldAccuracy(results, 'timeCorrect'),
    'contentAccuracy': _fieldAccuracy(results, 'contentCorrect'),
    'contentSpanAccuracy': _fieldAccuracy(results, 'contentSpanCorrect'),
    'displayFormattingMismatchCount': results
        .where((item) => item['displayFormattingMismatch'] == true)
        .length,
    'contentSpanErrorCount': results
        .where((item) => item['contentSpanError'] == true)
        .length,
    'completeAccuracy': _rate(results, (item) => item['correct'] == true),
    'highConfidenceWrongPredictionCount': results
        .where((item) => item['highConfidenceWrong'] == true)
        .length,
    'confirmationLevelDistribution': _counts(
      results.map((item) => item['confirmationLevel']! as String),
    ),
    'confidenceBuckets': _confidenceBuckets(results),
    'latencyMicroseconds': {
      'average':
          latencies.fold<int>(0, (sum, value) => sum + value) /
          latencies.length,
      'p50': _percentile(latencies, 0.50),
      'p95': _percentile(latencies, 0.95),
      'p99': _percentile(latencies, 0.99),
      'max': latencies.last,
    },
    'failureReasonCounts': _failureCounts(failures),
    'groupMetrics': _groupMetrics(results),
    'semanticMetrics': _semanticMetrics(results),
    'failures': failures,
  };
  final output = const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln(output);
  if (reportPath.isNotEmpty) {
    final target = File(reportPath);
    target.parent.createSync(recursive: true);
    target.writeAsStringSync('$output\n');
  }
}

Map<String, Object?> _evaluate(
  Map<String, Object?> testCase,
  RecognitionResult actual,
) {
  final expected = (testCase['expected']! as Map).cast<String, Object?>();
  final expectedContent = expected['content'] as String?;
  final actualContent = actual.draft.content;
  final contentCorrect =
      expectedContent == null || actualContent == expectedContent;
  final contentSpanCorrect =
      expectedContent == null ||
      RecognitionNormalizer.indexKey(actualContent ?? '') ==
          RecognitionNormalizer.indexKey(expectedContent);
  final displayMismatch = !contentCorrect && contentSpanCorrect;
  final statusCorrect = switch (expected['status']) {
    'complete' => actual.resultStatus == RecognitionResultStatus.complete,
    'partial' => actual.confirmationLevel != ConfirmationLevel.confident,
    'reject' ||
    'rejected' => actual.confirmationLevel == ConfirmationLevel.blocked,
    _ => actual.resultStatus.name == expected['status'],
  };
  final amountCorrect =
      expected['amountMinor'] == null ||
      actual.draft.amountMinor == expected['amountMinor'];
  final typeCorrect =
      expected['type'] == null || actual.draft.type?.value == expected['type'];
  final categoryCorrect =
      expected['categoryId'] == null ||
      (actual.categoryId == expected['categoryId'] &&
          actual.subcategoryId == expected['subcategoryId']);
  final timeCorrect =
      expected['occurredAtLocal'] == null ||
      _sameWallTime(
        actual.draft.occurredAtLocal,
        _wallTime(expected['occurredAtLocal']! as String),
      );
  final expectedIssues = (expected['issues']! as List).cast<String>();
  final actualIssues = actual.issueCodes.map(_issueCode).toSet();
  final issuesCorrect = expectedIssues.every(actualIssues.contains);
  final correct =
      statusCorrect &&
      amountCorrect &&
      typeCorrect &&
      categoryCorrect &&
      timeCorrect &&
      contentCorrect &&
      issuesCorrect;
  final reasons = <String>[
    if (!statusCorrect) 'status',
    if (!amountCorrect) 'amount_extraction',
    if (!typeCorrect) 'type_inference',
    if (!categoryCorrect) 'category_or_fusion',
    if (!timeCorrect) 'time_parsing',
    if (displayMismatch) 'display_formatting_mismatch',
    if (!contentSpanCorrect) 'content_span_error',
    if (!issuesCorrect) 'safe_rejection_issue',
  ];
  final wrongCore = !amountCorrect || !typeCorrect || !categoryCorrect;
  final highConfidenceWrong =
      actual.confirmationLevel == ConfirmationLevel.confident &&
      actual.confidence >= 0.80 &&
      wrongCore;
  return {
    'id': testCase['id'],
    'priority': testCase['priority'],
    'group': testCase['group'],
    'input': testCase['input'],
    'correct': correct,
    'safe':
        correct ||
        actual.resultStatus != RecognitionResultStatus.complete ||
        !highConfidenceWrong,
    'expectedStatus': expected['status'],
    'actualStatus': actual.resultStatus.name,
    'confirmationLevel': actual.confirmationLevel.name,
    'canQuickConfirm': actual.canQuickConfirm,
    'amountCorrect': amountCorrect,
    'typeCorrect': typeCorrect,
    'categoryCorrect': categoryCorrect,
    'parentCorrect':
        expected['categoryId'] == null ||
        actual.categoryId == expected['categoryId'],
    'timeCorrect': timeCorrect,
    'contentCorrect': contentCorrect,
    'contentSpanCorrect': contentSpanCorrect,
    'displayFormattingMismatch': displayMismatch,
    'contentSpanError': !contentSpanCorrect,
    'issuesCorrect': issuesCorrect,
    'expected': expected,
    'actual': {
      'semanticKey': actual.semanticKey,
      'type': actual.draft.type?.value,
      'amountMinor': actual.draft.amountMinor,
      'content': actualContent,
      'categoryId': actual.categoryId,
      'subcategoryId': actual.subcategoryId,
      'occurredAtLocal': actual.draft.occurredAtLocal?.toIso8601String(),
      'confidence': actual.confidence,
      'confirmationLevel': actual.confirmationLevel.name,
      'canQuickConfirm': actual.canQuickConfirm,
      'fieldConfidence': {
        'amount': actual.fieldConfidence.amount,
        'type': actual.fieldConfidence.type,
        'category': actual.fieldConfidence.category,
        'time': actual.fieldConfidence.time,
        'content': actual.fieldConfidence.content,
      },
      'issues': actualIssues.toList()..sort(),
      'amountCandidates': [
        for (final candidate in actual.amountCandidates)
          {
            'raw': candidate.raw,
            'amountMinor': candidate.amountMinor,
            'score': candidate.score,
            'role': candidate.role.name,
            'reason': candidate.reason,
            'features': candidate.features,
          },
      ],
    },
    'failureReasons': reasons,
    'highConfidenceWrong': highConfidenceWrong,
  };
}

Map<String, String> _options(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--corpus' || argument == '--report') {
      if (index + 1 >= args.length) {
        throw ArgumentError('Missing value for $argument');
      }
      result[argument.substring(2)] = args[++index];
    }
  }
  return result;
}

Map<String, Object?> _priority(
  List<Map<String, Object?>> results,
  String value,
) {
  final subset = results.where((item) => item['priority'] == value).toList();
  final correct = subset.where((item) => item['correct'] == true).length;
  return {
    'total': subset.length,
    'correct': correct,
    'accuracy': subset.isEmpty ? 0 : correct / subset.length,
    'categoryAccuracy': _fieldAccuracy(subset, 'categoryCorrect'),
    'typeAccuracy': _fieldAccuracy(subset, 'typeCorrect'),
  };
}

Map<String, int> _failureCounts(List<Map<String, Object?>> failures) {
  final result = <String, int>{};
  for (final failure in failures) {
    for (final reason in (failure['failureReasons']! as List).cast<String>()) {
      result.update(reason, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  return result;
}

Map<String, Object?> _groupMetrics(List<Map<String, Object?>> results) {
  final groups = results.map((item) => item['group']! as String).toSet();
  return {
    for (final group in groups.toList()..sort())
      group: () {
        final subset = results.where((item) => item['group'] == group).toList();
        return {
          'count': subset.length,
          'overallAccuracy': _rate(subset, (item) => item['correct'] == true),
          'amountAccuracy': _fieldAccuracy(subset, 'amountCorrect'),
          'typeAccuracy': _fieldAccuracy(subset, 'typeCorrect'),
          'categoryAccuracy': _fieldAccuracy(subset, 'categoryCorrect'),
          'parentCategoryAccuracy': _fieldAccuracy(subset, 'parentCorrect'),
          'timeAccuracy': _fieldAccuracy(subset, 'timeCorrect'),
        };
      }(),
  };
}

Map<String, Object?> _semanticMetrics(List<Map<String, Object?>> results) {
  final byId = {
    for (final category in RecognitionToolHarness.categories)
      category.id: category.semanticKey,
  };
  final grouped = <String, List<Map<String, Object?>>>{};
  for (final result in results) {
    final expected = result['expected']! as Map;
    final key = byId[expected['subcategoryId'] ?? expected['categoryId']];
    if (key != null) grouped.putIfAbsent(key, () => []).add(result);
  }
  return {
    'testedSemanticKeyCount': grouped.length,
    'fullyCorrectSemanticKeyCount': grouped.values
        .where(
          (items) => items.every((item) => item['categoryCorrect'] == true),
        )
        .length,
    'bySemanticKey': {
      for (final key in grouped.keys.toList()..sort())
        key: {
          'count': grouped[key]!.length,
          'categoryAccuracy': _fieldAccuracy(grouped[key]!, 'categoryCorrect'),
        },
    },
  };
}

Map<String, int> _counts(Iterable<String> values) {
  final result = <String, int>{};
  for (final value in values) {
    result.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return result;
}

Map<String, Object?> _confidenceBuckets(List<Map<String, Object?>> results) {
  const buckets = <(String, double, double)>[
    ('lt_0_5', 0, 0.5),
    ('0_5_to_0_65', 0.5, 0.65),
    ('0_65_to_0_8', 0.65, 0.8),
    ('gte_0_8', 0.8, 1.01),
  ];
  return {
    for (final (name, lower, upper) in buckets)
      name: () {
        final subset = results.where((item) {
          final actual = item['actual']! as Map<String, Object?>;
          final confidence = actual['confidence']! as double;
          return confidence >= lower && confidence < upper;
        }).toList();
        return {
          'count': subset.length,
          'accuracy': _rate(subset, (item) => item['correct'] == true),
          'coverage': results.isEmpty ? 0 : subset.length / results.length,
        };
      }(),
  };
}

String _issueCode(RecognitionIssueCode code) => switch (code) {
  RecognitionIssueCode.emptyInput => 'empty_input',
  RecognitionIssueCode.amountUnrecognized => 'amount_unrecognized',
  RecognitionIssueCode.ambiguousAmount => 'ambiguous_amount',
  RecognitionIssueCode.contentUnrecognized => 'content_unrecognized',
  RecognitionIssueCode.typeLowConfidence => 'type_low_confidence',
  RecognitionIssueCode.typeConflict => 'type_conflict',
  RecognitionIssueCode.categoryLowConfidence => 'category_low_confidence',
  RecognitionIssueCode.categoryAmbiguous => 'category_ambiguous',
  RecognitionIssueCode.categoryMappingMissing => 'category_mapping_missing',
  RecognitionIssueCode.ambiguousWeekday => 'ambiguous_weekday',
  RecognitionIssueCode.transactionNotCompleted => 'transaction_not_completed',
  RecognitionIssueCode.transactionCancelled => 'transaction_cancelled',
  RecognitionIssueCode.noTransactionEvidence => 'no_transaction_evidence',
  RecognitionIssueCode.relatedTransactionRequired =>
    'related_transaction_required',
  RecognitionIssueCode.multipleTransactionsDetected =>
    'multiple_transactions_detected',
};

double _fieldAccuracy(List<Map<String, Object?>> values, String key) =>
    _rate(values, (item) => item[key] == true);

double _rate(
  Iterable<Map<String, Object?>> values,
  bool Function(Map<String, Object?>) predicate,
) {
  final list = values.toList();
  if (list.isEmpty) return 0;
  return list.where(predicate).length / list.length;
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];

bool _sameWallTime(DateTime? left, DateTime right) =>
    left != null &&
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day &&
    left.hour == right.hour &&
    left.minute == right.minute &&
    left.second == right.second;

DateTime _wallTime(String iso) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})')
      .firstMatch(iso)!;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

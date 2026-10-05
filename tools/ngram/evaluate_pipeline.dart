import 'dart:convert';
import 'dart:io';

import '../recognition_tool_harness.dart';
import 'archive/pooled/candidate.dart';

import 'package:light_log/features/recognition/domain/recognition_models.dart';

void main(List<String> args) {
  final stage = args.first;
  final h = RecognitionToolHarness(
    classifier: args.length > 1 && args[1] == 'pooled'
        ? PooledCandidate.load()
        : null,
  );
  final rows = File('tools/ngram/data/ngram_dev_v2.jsonl')
      .readAsLinesSync()
      .map((s) => jsonDecode(s) as Map)
      .toList();
  final traces = File('tools/ngram/dev_pipeline.jsonl')
      .readAsLinesSync()
      .map((s) => jsonDecode(s) as Map)
      .toList();
  final tax =
      jsonDecode(File('tools/ngram/taxonomy.json').readAsStringSync()) as Map;
  final result = <Map<String, Object?>>[];
  final timings = <int>[];
  for (var i = 0; i < 1000; i++) {
    h.recognize(
      traces[i % traces.length]['text'] as String,
      now: DateTime(2026, 10, 5, 12),
    );
  }
  for (var i = 0; i < rows.length; i++) {
    final timer = Stopwatch()..start();
    final r = h.recognize(
      traces[i]['text'] as String,
      now: DateTime(2026, 10, 5, 12),
    );
    timer.stop();
    timings.add(timer.elapsedMicroseconds);
    final label = rows[i]['semanticKey'];
    final pred = r.semanticKey;
    result.add({
      'correct': pred == label,
      'parentCorrect': tax[pred] == tax[label],
      'typeCorrect': r.draft.type?.value == rows[i]['type'],
      'specific': pred != null && !pred.endsWith('.other.general'),
      'falseFallback':
          pred != null && pred.endsWith('.other.general') && pred != label,
      'mealOracle': const {
        'expense.food.breakfast',
        'expense.food.lunch',
        'expense.food.dinner',
      }.contains(label),
      'mealDetected': r.evidence.any(
        (e) =>
            e.family == 'mealByExplicitTime' ||
            e.family == 'mealByOccurredAt' ||
            e.family == 'preparedMealStatistical',
      ),
      'nullCategory':
          r.categoryId == null &&
          !RecognitionResult.isSafetyBlocked(r.issueCodes),
      'highWrong':
          r.confirmationLevel == ConfirmationLevel.confident &&
          (pred != label || r.draft.type?.value != rows[i]['type']),
      'accepted': r.evidence.any(
        (e) =>
            e.source == RecognitionEvidenceSource.ngram &&
            e.semanticKey == pred,
      ),
      'sameParent': r.evidence.any(
        (e) => e.family == 'statisticalSameParent' && e.semanticKey == pred,
      ),
    });
  }
  double? rate(Iterable<Map<String, Object?>> set, String key) {
    final a = set.toList();
    return a.isEmpty ? null : a.where((r) => r[key] == true).length / a.length;
  }

  int count(String key) => result.where((r) => r[key] == true).length;
  final specific = result.where((r) => r['specific'] == true);
  final parent = result.where((r) => r['parentCorrect'] == true);
  final accepted = result.where((r) => r['accepted'] == true);
  timings.sort();
  final report = {
    'stage': stage,
    'devCount': rows.length,
    'categoryAccuracy': rate(result, 'correct'),
    'parentAccuracy': rate(result, 'parentCorrect'),
    'typeAccuracy': rate(result, 'typeCorrect'),
    'specificCategoryCoverage': specific.length / result.length,
    'specificCategoryAccuracy': rate(specific, 'correct'),
    'fallbackRate': 1 - specific.length / result.length,
    'falseFallbackRate': count('falseFallback') / result.length,
    'childConditionalAccuracy': rate(parent, 'correct'),
    'acceptedCoverage': accepted.length / result.length,
    'acceptedAccuracy': rate(accepted, 'correct'),
    'sameParentRerankAccuracy': rate(
      accepted.where((r) => r['sameParent'] == true),
      'correct',
    ),
    'crossParentStatisticalAccuracy': rate(
      accepted.where((r) => r['sameParent'] != true),
      'correct',
    ),
    'mealAccuracy': rate(
      result.where((r) => r['mealOracle'] == true),
      'correct',
    ),
    'mealDetectionRecall': rate(
      result.where((r) => r['mealOracle'] == true),
      'mealDetected',
    ),
    'highConfidenceWrong': count('highWrong'),
    'ordinaryCategoryNull': count('nullCategory'),
    'failureDecomposition': {
      'otherFallbackError': count('falseFallback'),
      'wrongParent': result.length - parent.length,
      'correctParentWrongChild': parent
          .where((r) => r['correct'] != true)
          .length,
      'wrongType': result.where((r) => r['typeCorrect'] != true).length,
      'mealDetection': result
          .where((r) => r['mealOracle'] == true && r['mealDetected'] != true)
          .length,
      'taxonomyAmbiguity': 'not adjudicated; labels unchanged',
      'safety': 'historical P2 suite separately',
    },
    'latencyMicroseconds': {
      for (final p in [50, 95, 99])
        'p$p': timings[((timings.length - 1) * p / 100).round()],
    },
    'environment': 'Windows host warm Dart VM; not Android API26',
    'inputContract': 'original text; fixed 37 suffix only when existing field extraction has no amount; semantic labels unchanged',
  };
  File('tools/ngram/stage_${stage.toLowerCase()}_pipeline_dev.json')
      .writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
  stdout.writeln(jsonEncode(report));
}

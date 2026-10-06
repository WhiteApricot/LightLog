import 'dart:convert';
import 'dart:io';

import 'package:light_log/features/recognition/domain/ngram_classifier.dart';
import 'package:light_log/features/recognition/domain/ngram_model.dart';

import '../recognition_tool_harness.dart';

/// Dev parity evaluation plus warm performance on all dev input styles.
void main() {
  final model = NgramModel.decode(
    File('assets/knowledge/ngram.bin').readAsBytesSync(),
  );
  final classifier = NgramClassifier(model);
  final dev = File('tools/ngram/data/ngram_dev_v2.jsonl')
      .readAsLinesSync()
      .map((l) => jsonDecode(l) as Map)
      .toList();
  final harness = RecognitionToolHarness();
  final offline = jsonDecode(
    File('tools/ngram/final96/dev_predictions.json').readAsStringSync(),
  ) as List;
  final traces = File('tools/ngram/dev_pipeline.jsonl')
      .readAsLinesSync()
      .map((l) => jsonDecode(l) as Map)
      .toList();
  final now = DateTime(2026, 10, 5, 12);
  for (var i = 0; i < 2000; i++) {
    final text = dev[i % dev.length]['text'] as String;
    classifier.scores(text);
    harness.recognize(text, now: now);
  }
  final ngram = <int>[];
  final full = <int>[];
  var correct = 0;
  final classes = {
    for (final label in model.labels)
      label: <String, int>{'support': 0, 'tp': 0, 'predicted': 0},
  };
  for (final row in dev) {
    final timer = Stopwatch()..start();
    final trace = traces[ngram.length];
    final prediction = classifier.predict(
      row['text'] as String,
      structuredFeatures: List<String>.from(trace['features'] as List),
    );
    final scores = prediction.scores;
    timer.stop();
    ngram.add(timer.elapsedMicroseconds);
    var top = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[top]) top = i;
    }
    final expected = row['semanticKey'] as String;
    final predicted = model.labels[top];
    final reference = offline[ngram.length - 1] as Map;
    if (reference['id'] != row['id'] ||
        reference['label'] != predicted ||
        (scores[top] - (reference['probability'] as num)).abs() > 1e-10) {
      throw StateError(
        'Offline/runtime parity mismatch: ${row['id']} Dart=$predicted/${scores[top]} reference=${reference['label']}/${reference['probability']}',
      );
    }
    if ((prediction.incomeProbability - (reference['incomeProbability'] as num))
                .abs() >
            1e-10 ||
        (prediction.preparedMealProbability -
                    (reference['preparedMealProbability'] as num))
                .abs() >
            1e-10) {
      throw StateError('Auxiliary head parity mismatch: ${row['id']}');
    }
    classes[expected]!['support'] = classes[expected]!['support']! + 1;
    classes[predicted]!['predicted'] = classes[predicted]!['predicted']! + 1;
    if (predicted == expected) {
      correct++;
      classes[expected]!['tp'] = classes[expected]!['tp']! + 1;
    }
    timer.reset();
    timer.start();
    harness.recognize(row['text'] as String, now: now);
    timer.stop();
    full.add(timer.elapsedMicroseconds);
  }
  final report = {
    'devCount': dev.length,
    'accuracy': correct / dev.length,
    'macroF1':
        classes.values
            .map((v) => 2 * v['tp']! / (v['support']! + v['predicted']!))
            .reduce((a, b) => a + b) /
        classes.length,
    'macroAccuracy':
        classes.values
            .map((v) => v['tp']! / v['support']!)
            .reduce((a, b) => a + b) /
        classes.length,
    'perClass': classes,
    'ngramMicroseconds': latency(ngram),
    'recognizerMicroseconds': latency(full),
    'environment': 'Dart VM warm, host CPU; not Android device',
  };
  File('tools/ngram/final96/runtime_report.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(jsonEncode(report));
  if (latency(ngram)['p95']! > 1000 || latency(full)['p95']! >= 5000) {
    exitCode = 1;
  }
}

Map<String, int> latency(List<int> values) {
  values.sort();
  return {
    for (final p in [50, 95, 99])
      'p$p': values[((values.length - 1) * p / 100).round()],
  };
}

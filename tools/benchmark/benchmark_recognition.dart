import 'dart:convert';
import 'dart:io';

import 'package:light_log/features/recognition/data/knowledge_decoder.dart';

import '../recognition_tool_harness.dart';

void main() {
  final harness = RecognitionToolHarness();
  final inputs = [
    '汉堡王 32',
    '淘宝 iPhone手机壳 49.9',
    '晚饭麦当劳 25',
    '7-Eleven 15',
    '12306 553',
    '速度与激情8 20',
    '原价 42 优惠 5 实付 37 麦当劳',
  ];
  final now = DateTime(2026, 10, 4, 12, 30);
  const warmUpIterations = 1000;
  for (var index = 0; index < warmUpIterations; index++) {
    harness.recognize(inputs[index % inputs.length], now: now);
  }

  const iterations = 10000;
  final samples = <int>[];
  for (var index = 0; index < iterations; index++) {
    final stopwatch = Stopwatch()..start();
    harness.recognize(inputs[index % inputs.length], now: now);
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  final average =
      samples.fold<int>(0, (sum, value) => sum + value) / samples.length;
  final report = {
    'warmUpIterations': warmUpIterations,
    'iterations': iterations,
    'averageMicroseconds': average,
    'p50Microseconds': _percentile(samples, 0.50),
    'p95Microseconds': _percentile(samples, 0.95),
    'p99Microseconds': _percentile(samples, 0.99),
    'maxMicroseconds': samples.last,
    'coldKnowledgeDecodeMicroseconds': _coldDecode(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  if ((report['p95Microseconds']! as int) >= 5000) {
    stderr.writeln('Benchmark failed: warm p95 must stay below 5000 µs.');
    exitCode = 1;
  }
}

int _percentile(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];

int _coldDecode() {
  final stopwatch = Stopwatch()..start();
  const KnowledgeDecoder().decode(
    entitiesJson: File('assets/knowledge/merchants.json').readAsStringSync(),
    lexiconJson: File('assets/knowledge/category_lexicon.json')
        .readAsStringSync(),
  );
  stopwatch.stop();
  return stopwatch.elapsedMicroseconds;
}

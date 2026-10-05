import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    throw ArgumentError(
      'Usage: dart run tools/evaluation/analyze_failures.dart <report.json> [summary.md]',
    );
  }
  if (args.length > 1 &&
      args[1].endsWith('_initial_analysis.md') &&
      File(args[1]).existsSync()) {
    throw StateError('Initial analysis is immutable: ${args[1]}');
  }
  final report = (jsonDecode(File(args.first).readAsStringSync()) as Map)
      .cast<String, Object?>();
  final failures = (report['failures']! as List).cast<Map<String, Object?>>();
  final summary = _summary(report, failures);
  stdout.write(summary);
  if (args.length > 1) File(args[1]).writeAsStringSync(summary);
}

String _summary(
  Map<String, Object?> report,
  List<Map<String, Object?>> failures,
) {
  final byPriority = _counts(failures, (item) => item['priority'] as String);
  final byGroup = _counts(failures, (item) => item['group'] as String);
  final byReason = <String, int>{};
  for (final failure in failures) {
    for (final reason in (failure['failureReasons']! as List).cast<String>()) {
      byReason.update(reason, (value) => value + 1, ifAbsent: () => 1);
    }
  }
  final highConfidence = failures
      .where((item) => item['highConfidenceWrong'] == true)
      .toList();
  final buffer = StringBuffer()
    ..writeln('# Recognition failure analysis')
    ..writeln()
    ..writeln('- Corpus: ${report['corpus']} v${report['corpusVersion']}')
    ..writeln('- Recognizer: v${report['recognizerVersion']}')
    ..writeln('- Knowledge hash: `${report['knowledgeHash']}`')
    ..writeln('- Failures: ${failures.length}/${report['totalCases']}')
    ..writeln('- High-confidence wrong: ${highConfidence.length}')
    ..writeln()
    ..writeln('Routing failures: ${report['routingFailureBreakdown']}')
    ..writeln(
      'Parent accuracy: ${report['parentCategoryAccuracy']}; child: ${report['childCategoryAccuracy']}; category null: ${report['categoryNullCount']}',
    )
    ..writeln()
    ..writeln('## By priority')
    ..writeln()
    ..writeln(_table(byPriority))
    ..writeln('## By failure reason')
    ..writeln()
    ..writeln(_table(byReason))
    ..writeln('## By group')
    ..writeln()
    ..writeln(_table(byGroup));
  if (highConfidence.isNotEmpty) {
    buffer
      ..writeln('## High-confidence wrong predictions')
      ..writeln();
    for (final item in highConfidence) {
      final actual = item['actual']! as Map<String, Object?>;
      buffer.writeln(
        '- `${item['id']}` `${item['input']}`: confidence=${actual['confidence']}',
      );
    }
    buffer.writeln();
  }
  return '${buffer.toString().trimRight()}\n';
}

Map<String, int> _counts(
  Iterable<Map<String, Object?>> values,
  String Function(Map<String, Object?>) key,
) {
  final counts = <String, int>{};
  for (final item in values) {
    counts.update(key(item), (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

String _table(Map<String, int> values) {
  final entries = values.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    '| Key | Count |',
    '|---|---:|',
    for (final entry in entries) '| ${entry.key} | ${entry.value} |',
    '',
  ].join('\n');
}

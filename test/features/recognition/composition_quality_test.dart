import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tools/knowledge/composition_quality.dart';
import '../../../tools/evaluation/knowledge_hash.dart';

void main() {
  Map<String, Object?> read(String path) =>
      (jsonDecode(File(path).readAsStringSync()) as Map)
          .cast<String, Object?>();

  test('production family coverage and shared concepts are audited', () {
    final families = read('tools/knowledge/lexical_families_source.json');
    final rules = read('tools/knowledge/composition_rules_source.json');
    final report = compositionQuality(families, rules);
    expect(report['lexicalFamilyTermCount'], greaterThanOrEqualTo(900));
    expect(report['unresolvedDangerousConflictCount'], 0);
    expect(report['unusedFamilies'], isEmpty);
    final first = (families['families']! as List).first as Map;
    (first['terms']! as List).add('充值');
    expect(() => compositionQuality(families, rules), throwsFormatException);
  });

  test('every production asset participates in evaluation fingerprint', () {
    final temp = Directory.systemTemp.createTempSync('lightlog-knowledge-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final paths = [
      for (var index = 0; index < recognitionKnowledgePaths.length; index++)
        '${temp.path}/asset-$index.json',
    ];
    for (final path in paths) {
      File(path).writeAsStringSync('{}');
    }
    final baseline = knowledgeHash(paths: paths);
    for (final path in paths) {
      File(path).writeAsStringSync('{"version":2}');
      expect(knowledgeHash(paths: paths), isNot(baseline));
      File(path).writeAsStringSync('{}');
    }
  });
}

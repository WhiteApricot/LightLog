import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/seed_data.dart';

import '../../../tools/knowledge/composition_quality.dart';
import '../../../tools/evaluation/knowledge_hash.dart';

void main() {
  test('V0.1 taxonomy is exactly the approved 104 children', () {
    final children = defaultCategories
        .where((c) => c.parentId != null)
        .toList();
    expect(children, hasLength(104));
    expect(children.where((c) => c.type == 'expense'), hasLength(78));
    expect(children.where((c) => c.type == 'income'), hasLength(26));
    expect(defaultCategories.where((c) => c.parentId == null), hasLength(21));
    expect(children.map((c) => c.semanticKey).toSet(), hasLength(104));
    expect(
      children.any(
        (c) =>
            c.semanticKey == 'expense.food.takeout' ||
            c.semanticKey.startsWith('expense.travel.') ||
            c.semanticKey.startsWith('expense.family.'),
      ),
      isFalse,
    );
    expect(
      children.map((c) => c.semanticKey),
      contains('income.reimbursement.travel'),
    );
  });
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

  test('prior policy, taxonomy and bounded score are enforced', () {
    final families = read('tools/knowledge/lexical_families_source.json');
    final rules = read('tools/knowledge/composition_rules_source.json');
    final family = (families['families'] as List).cast<Map>().firstWhere(
      (f) => f['prior'] != null,
    );
    final prior = family['prior'] as Map;
    final semantic = prior['semanticKey'];
    prior['semanticKey'] = 'expense.nonexistent.child';
    expect(() => compositionQuality(families, rules), throwsFormatException);
    prior['semanticKey'] = semantic;
    final score = prior['score'];
    prior['score'] = .99;
    expect(() => compositionQuality(families, rules), throwsFormatException);
    prior['score'] = score;
    family['policy'] = 'contextualOnly';
    expect(() => compositionQuality(families, rules), throwsFormatException);
  });
}

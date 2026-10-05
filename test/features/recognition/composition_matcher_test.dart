import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/compositional_matcher.dart';
import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/knowledge_models.dart';
import 'package:light_log/features/recognition/domain/lexical_family_matcher.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/span_conflict_resolver.dart';

void main() {
  final catalog = KnowledgeCatalog(
    entities: const [],
    lexicon: const [],
    lexicalFamilies: const [
      LexicalFamilyKnowledge(id: 'object.device', terms: ['设备']),
      LexicalFamilyKnowledge(id: 'action.repair', terms: ['维修']),
      LexicalFamilyKnowledge(id: 'modifier.child', terms: ['孩子']),
      LexicalFamilyKnowledge(id: 'action.medical', terms: ['看病']),
    ],
    compositionRules: const [
      CompositionRuleKnowledge(
        id: 'device-repair',
        leftFamily: 'object.device',
        rightFamily: 'action.repair',
        semanticKey: 'expense.digital.repair',
        maxDistance: 3,
        score: 0.94,
      ),
      CompositionRuleKnowledge(
        id: 'child-medical',
        leftFamily: 'modifier.child',
        rightFamily: 'action.medical',
        semanticKey: 'expense.family.health',
        maxDistance: 3,
        score: 0.94,
      ),
    ],
  );

  test('specific action and object compose into stronger evidence', () {
    final matches = LexicalFamilyMatcher(catalog).match('设备维修');
    final evidence = CompositionalMatcher(catalog).match(matches);

    expect(evidence, hasLength(1));
    expect(evidence.single.semanticKey, 'expense.digital.repair');
    expect(evidence.single.source, RecognitionEvidenceSource.composition);
    expect(evidence.single.span, isNotNull);
  });

  test('modifier plus nearby action composes', () {
    final evidence = CompositionalMatcher(catalog)
        .match(LexicalFamilyMatcher(catalog).match('孩子去看病'));

    expect(evidence.single.semanticKey, 'expense.family.health');
  });

  test('unrelated distant spans do not compose', () {
    final evidence = CompositionalMatcher(catalog)
        .match(LexicalFamilyMatcher(catalog).match('设备和其他无关说明文字之后才维修'));

    expect(evidence, isEmpty);
  });

  test('contained shorter conflicting span is suppressed', () {
    const short = RecognitionEvidence(
      field: 'category',
      description: '短词',
      score: 0.9,
      semanticKey: 'expense.transport.rail',
      specificity: EvidenceSpecificity.specific,
      span: TextSpanRange(start: 1, end: 3),
    );
    const long = RecognitionEvidence(
      field: 'category',
      description: '长词',
      score: 0.95,
      semanticKey: 'expense.shopping.other',
      specificity: EvidenceSpecificity.specific,
      span: TextSpanRange(start: 0, end: 3),
    );

    expect(const SpanConflictResolver().resolveEvidence([short, long]), [long]);
  });

  test('same-semantic evidence is deduplicated by evidence family', () {
    const duplicateA = RecognitionEvidence(
      field: 'category',
      description: 'A',
      score: 0.8,
      semanticKey: 'expense.digital.repair',
      family: 'same',
    );
    const duplicateB = RecognitionEvidence(
      field: 'category',
      description: 'B',
      score: 0.9,
      semanticKey: 'expense.digital.repair',
      family: 'same',
    );

    final result = const EvidenceFusion().fuse([duplicateA, duplicateB]);
    expect(result.winningEvidence, [duplicateB]);
  });
}

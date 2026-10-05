import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/knowledge_models.dart';
import 'package:light_log/features/recognition/domain/family_matcher.dart';
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
    final matches = FamilyMatcher(catalog).match('设备维修');
    final evidence = FamilyMatcher(catalog).evidence(matches);

    expect(evidence, hasLength(1));
    expect(evidence.single.semanticKey, 'expense.digital.repair');
    expect(evidence.single.source, RecognitionEvidenceSource.composition);
    expect(evidence.single.span, isNotNull);
  });

  test('modifier plus nearby action composes', () {
    final evidence = FamilyMatcher(catalog)
        .evidence(FamilyMatcher(catalog).match('孩子去看病'));

    expect(evidence.single.semanticKey, 'expense.family.health');
  });

  test('unrelated distant spans do not compose', () {
    final evidence = FamilyMatcher(catalog)
        .evidence(FamilyMatcher(catalog).match('设备和其他无关说明文字之后才维修'));

    expect(evidence, isEmpty);
  });

  test('single-character replacement requires an immediate component', () {
    final knowledge = KnowledgeCatalog(
      entities: const [],
      lexicon: const [],
      lexicalFamilies: const [
        LexicalFamilyKnowledge(
          id: 'action.replacePart',
          terms: ['换'],
          requiresAdjacentFamily: ['object.digitalComponent'],
        ),
        LexicalFamilyKnowledge(id: 'object.digitalComponent', terms: ['硬盘']),
        LexicalFamilyKnowledge(id: 'object.digitalDevice', terms: ['手机']),
      ],
    );
    final matcher = FamilyMatcher(knowledge);
    expect(
      matcher
          .match('换手机')
          .where((m) => m.conceptFamily == 'action.replacePart'),
      isEmpty,
    );
    expect(
      matcher
          .match('换了别的硬盘')
          .where((m) => m.conceptFamily == 'action.replacePart'),
      isEmpty,
    );
    expect(
      matcher
          .match('换硬盘')
          .where((m) => m.conceptFamily == 'action.replacePart'),
      hasLength(1),
    );
  });

  test('an embedded context can qualify a specific object', () {
    final knowledge = KnowledgeCatalog(
      entities: const [],
      lexicon: const [],
      compositionRules: const [
        CompositionRuleKnowledge(
          id: 'photo-object',
          allowOverlap: true,
          leftFamily: 'context.photo',
          rightFamily: 'object.light',
          semanticKey: 'expense.digital.photo',
          maxDistance: 4,
          score: .93,
        ),
      ],
    );
    final evidence = FamilyMatcher(knowledge).evidence(const [
      LexicalFamilyMatch(
        conceptFamily: 'context.photo',
        term: '摄影',
        range: TextSpanRange(start: 0, end: 2),
      ),
      LexicalFamilyMatch(
        conceptFamily: 'object.light',
        term: '摄影灯',
        range: TextSpanRange(start: 0, end: 3),
      ),
    ]);
    expect(evidence.single.semanticKey, 'expense.digital.photo');
  });

  test('atomic concept survives when its compound embeds another family', () {
    const cloud = LexicalFamilyMatch(
      conceptFamily: 'object.cloud',
      term: '网盘',
      range: TextSpanRange(start: 0, end: 2),
    );
    const compound = LexicalFamilyMatch(
      conceptFamily: 'object.cloud',
      term: '网盘会员',
      range: TextSpanRange(start: 0, end: 4),
    );
    const membership = LexicalFamilyMatch(
      conceptFamily: 'service.membership',
      term: '会员',
      range: TextSpanRange(start: 2, end: 4),
    );
    final matcher = FamilyMatcher(
      KnowledgeCatalog(
        entities: const [],
        lexicon: const [],
        lexicalFamilies: [
          LexicalFamilyKnowledge(
            id: cloud.conceptFamily,
            terms: [cloud.term, compound.term],
          ),
          LexicalFamilyKnowledge(
            id: membership.conceptFamily,
            terms: [membership.term],
          ),
        ],
      ),
    );
    final result = matcher.match('网盘会员');
    expect(result.where((m) => m.term == cloud.term), hasLength(1));
    expect(result.where((m) => m.term == membership.term), hasLength(1));
  });

  test('one nested compound cannot act as two independent concepts', () {
    final evidence = FamilyMatcher(catalog).evidence(const [
      LexicalFamilyMatch(
        conceptFamily: 'object.device',
        term: '设备',
        range: TextSpanRange(start: 0, end: 2),
      ),
      LexicalFamilyMatch(
        conceptFamily: 'action.repair',
        term: '设备维修',
        range: TextSpanRange(start: 0, end: 4),
      ),
    ]);
    expect(evidence, isEmpty);
  });

  test(
    'concept matching retains nested objects until semantic replacement',
    () {
      const short = LexicalFamilyMatch(
        conceptFamily: 'object.phone',
        term: '手机',
        range: TextSpanRange(start: 0, end: 2),
      );
      const long = LexicalFamilyMatch(
        conceptFamily: 'object.accessory',
        term: '手机壳',
        range: TextSpanRange(start: 0, end: 3),
      );
      final matcher = FamilyMatcher(
        KnowledgeCatalog(
          entities: const [],
          lexicon: const [],
          lexicalFamilies: [
            LexicalFamilyKnowledge(
              id: short.conceptFamily,
              terms: [short.term],
            ),
            LexicalFamilyKnowledge(id: long.conceptFamily, terms: [long.term]),
          ],
        ),
      );
      final matches = matcher.match('手机壳');
      expect(matches.map((m) => m.term), containsAll([short.term, long.term]));
    },
  );

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

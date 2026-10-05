import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/family_matcher.dart';
import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/knowledge_models.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/span_conflict_resolver.dart';
import 'package:light_log/features/recognition/domain/type_inference.dart';
import 'package:light_log/features/recognition/domain/recognizer.dart';

void main() {
  final matcher = FamilyMatcher(
    KnowledgeCatalog(
      entities: const [],
      lexicon: const [],
      lexicalFamilies: const [
        LexicalFamilyKnowledge(
          id: 'object.synthetic',
          terms: ['晶盒'],
          prior: (semanticKey: 'expense.digital.photo', score: .76),
        ),
        LexicalFamilyKnowledge(id: 'action.synthetic', terms: ['整修']),
      ],
      compositionRules: const [
        CompositionRuleKnowledge(
          id: 'synthetic-repair',
          leftFamily: 'object.synthetic',
          rightFamily: 'action.synthetic',
          semanticKey: 'expense.digital.repair',
          maxDistance: 2,
          score: .94,
        ),
      ],
    ),
  );
  test(
    'standalone prior emits bounded evidence; contextual concept emits none',
    () {
      final prior = matcher.evidence(matcher.match('晶盒'));
      expect(prior.single.source, RecognitionEvidenceSource.familyPrior);
      expect(const EvidenceFusion().fuse(prior).confidence, lessThan(.80));
      expect(matcher.evidence(matcher.match('整修')), isEmpty);
    },
  );
  test('composition overrides the default child', () {
    final result = const EvidenceFusion().fuse(
      matcher.evidence(matcher.match('晶盒整修')),
    );
    expect(result.semanticKey, 'expense.digital.repair');
  });
  test('concept without output cannot erase contained semantic evidence', () {
    const existing = RecognitionEvidence(
      field: 'category',
      description: 'synthetic',
      semanticKey: 'expense.digital.photo',
      score: .91,
      span: TextSpanRange(start: 1, end: 3),
    );
    final contextual = matcher.evidence(matcher.match('整修'));
    expect(
      const SpanConflictResolver().resolveEvidence([existing, ...contextual]),
      [existing],
    );
  });
  test('actual longer prior replaces a false contained substring', () {
    const substring = RecognitionEvidence(
      field: 'category',
      description: 'substring',
      semanticKey: 'expense.transport.rail',
      score: .94,
      span: TextSpanRange(start: 1, end: 2),
    );
    final replacement = matcher.evidence(matcher.match('晶盒'));
    expect(
      const SpanConflictResolver().resolveEvidence([substring, ...replacement]),
      replacement,
    );
  });
  test(
    'independent parent support breaks equal-anchor cross-parent competition',
    () {
      RecognitionEvidence item(String key, String family) =>
          RecognitionEvidence(
            field: 'category',
            description: family,
            semanticKey: key,
            score: .80,
            family: family,
            role: EvidenceRole.service,
            specificity: EvidenceSpecificity.specific,
          );
      final result = const EvidenceFusion().fuse([
        item('expense.housing.rent', 'a'),
        item('expense.transport.rail', 'b'),
        item('expense.transport.taxi', 'c'),
      ]);
      expect(result.semanticKey, startsWith('expense.transport.'));
      expect(
        result.winningEvidence.every(
          (e) => e.semanticKey == result.semanticKey,
        ),
        isTrue,
      );
    },
  );
  const inference = TypeInference();
  const incomeEvidence = RecognitionEvidence(
    field: 'category',
    description: 'synthetic income',
    semanticKey: 'income.salary.monthly',
    score: .76,
    source: RecognitionEvidenceSource.familyPrior,
  );
  test('semantic income corrects weak expense default', () {
    final result = inference.reconcile(
      const TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: .88,
        evidence: [],
        isDefault: true,
      ),
      'income.salary.monthly',
      [incomeEvidence],
    );
    expect(result.type, RecognitionTransactionType.income);
    expect(result.hasConflict, isFalse);
  });
  test('strong opposing type evidence remains a conflict', () {
    final result = inference.reconcile(
      const TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: .98,
        evidence: [],
      ),
      'income.salary.monthly',
      [incomeEvidence],
    );
    expect(result.type, RecognitionTransactionType.expense);
    expect(result.hasConflict, isTrue);
  });
  test('refund direction is never changed by semantic reconciliation', () {
    final refund = inference.inferPreliminary(
      matchingText: '退回',
      status: TransactionStatus.refund,
      amount: null,
      hasContent: true,
    );
    expect(
      inference.reconcile(refund, 'income.salary.monthly', [
        incomeEvidence,
      ]).type,
      RecognitionTransactionType.refund,
    );
  });
  test('semantic refund restores refund type and blocks unlinked entry', () {
    final recognizer = LocalRecognizer(
      knowledge: KnowledgeCatalog(
        entities: const [],
        lexicon: const [],
        lexicalFamilies: const [
          LexicalFamilyKnowledge(
            id: 'object.syntheticReturn',
            terms: ['回流'],
            prior: (semanticKey: 'income.refund.service', score: .76),
          ),
        ],
      ),
    );
    final result = recognizer.recognize(
      RecognitionInput(
        rawText: '回流 13元',
        nowLocal: DateTime(2026, 1, 1),
        timezoneOffsetMinutes: 480,
        activeCategories: const [
          RecognitionCategory(
            id: 'parent',
            parentId: null,
            name: '退款',
            type: RecognitionTransactionType.income,
            semanticKey: 'income.refund',
            isSystem: true,
            sortOrder: 0,
            isActive: true,
          ),
          RecognitionCategory(
            id: 'child',
            parentId: 'parent',
            name: '服务',
            type: RecognitionTransactionType.income,
            semanticKey: 'income.refund.service',
            isSystem: true,
            sortOrder: 0,
            isActive: true,
          ),
        ],
      ),
    );
    expect(result.draft.type, RecognitionTransactionType.refund);
    expect(result.subcategoryId, 'child');
    expect(
      result.issueCodes,
      contains(RecognitionIssueCode.relatedTransactionRequired),
    );
    expect(result.confirmationLevel, ConfirmationLevel.blocked);
    expect(result.canQuickConfirm, isFalse);
  });
}

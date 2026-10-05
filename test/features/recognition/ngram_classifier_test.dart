import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/ngram_classifier.dart';
import 'package:light_log/features/recognition/domain/ngram_model.dart';
import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

import '../../../tools/recognition_tool_harness.dart';
import '../../../tools/ngram/archive/pooled/candidate.dart';

import 'package:light_log/features/recognition/domain/type_inference.dart';

void main() {
  final bytes = File('assets/knowledge/ngram.bin').readAsBytesSync();
  final classifier = NgramClassifier(NgramModel.decode(bytes));
  test('offline normalization and all class probabilities agree with Dart', () {
    final vectors = jsonDecode(
      File('tools/ngram/parity_vectors.json').readAsStringSync(),
    ) as List;
    for (final v in vectors) {
      expect(NgramClassifier.normalize(v['text'] as String), v['normalized']);
      final scores = classifier.scores(
        v['text'] as String,
        structuredFeatures: List<String>.from(
          v['features'] as List? ?? const [],
        ),
      );
      final expected = v['scores'] as List;
      for (var i = 0; i < scores.length; i++) {
        expect(scores[i], closeTo((expected[i] as num).toDouble(), 1e-10));
      }
    }
    expect(NgramClassifier.normalize('ＡＢＣ１２３，猫🐈粮\n２０元'), 'abc 猫 粮 元');
    expect(
      classifier
          .hierarchicalEvidence(
            '123 ! 🐈',
            RecognitionToolHarness.categories,
            level: 2,
          )
          .evidence,
      isNull,
    );
    expect(classifier.scores(''), everyElement(0));
  });
  test('malformed/unsupported assets fail explicitly', () {
    expect(() => NgramModel.decode(Uint8List(4)), throwsFormatException);
    expect(
      () => NgramModel.decode(bytes.sublist(0, bytes.length - 1)),
      throwsFormatException,
    );
    final corrupt = Uint8List.fromList(bytes)
      ..[4] = 255
      ..[5] = 255
      ..[6] = 255
      ..[7] = 127;
    expect(() => NgramModel.decode(corrupt), throwsFormatException);
  });
  test(
    'fusion protects strong evidence and direction and caps weak evidence',
    () {
      const fusion = EvidenceFusion();
      const weak = RecognitionEvidence(
        field: 'category',
        description: 'test',
        score: .99,
        source: RecognitionEvidenceSource.ngram,
        semanticKey: 'expense.pets.food',
      );
      final empty = fusion.fuse([]);
      final fallback = fusion.withWeakEvidence(
        empty,
        weak,
        RecognitionTransactionType.expense,
      );
      expect(fallback.confidence, .69);
      expect(fallback.semanticKey, weak.semanticKey);
      expect(
        fusion.withWeakEvidence(empty, weak, RecognitionTransactionType.income),
        same(empty),
      );
      final strong = fusion.fuse([
        const RecognitionEvidence(
          field: 'category',
          description: 'specific',
          score: .60,
          source: RecognitionEvidenceSource.categoryLexicon,
          role: EvidenceRole.product,
          specificity: EvidenceSpecificity.specific,
          semanticKey: 'expense.digital.phone',
        ),
      ]);
      expect(
        fusion.withWeakEvidence(
          strong,
          weak,
          RecognitionTransactionType.expense,
        ),
        same(strong),
      );
    },
  );
  test('weak fallback cannot weaken dangerous gates or change type', () {
    final withModel = RecognitionToolHarness();
    final baseline = RecognitionToolHarness(useNgram: false);
    for (final text in [
      '买猫粮 30',
      '交易失败 猫粮 30',
      '交易取消 猫粮 30',
      '余额 猫粮 30',
      '退款 猫粮 30',
      '猫粮',
      '买猫粮30\n买狗粮40',
    ]) {
      final now = DateTime(2026, 10, 5, 12);
      final before = baseline.recognize(text, now: now);
      final after = withModel.recognize(text, now: now);
      expect(after.draft.type, before.draft.type);
      expect(after.draft.amountMinor, before.draft.amountMinor);
      expect(after.blockingIssues, containsAll(before.blockingIssues));
      if (before.confirmationLevel == ConfirmationLevel.blocked) {
        expect(after.confirmationLevel, ConfirmationLevel.blocked);
      }
      if (after.evidence.any(
        (e) => e.source == RecognitionEvidenceSource.ngram,
      )) {
        expect(after.confirmationLevel, isNot(ConfirmationLevel.confident));
      }
    }
  });
  test(
    'hierarchy metadata uses all active children and exactly 21 parents',
    () {
      final categories = RecognitionToolHarness.categories;
      final byId = {for (final c in categories) c.id: c};
      final actual = {
        for (final c in categories)
          if (c.parentId != null) c.semanticKey: byId[c.parentId]!.semanticKey,
      };
      expect(classifier.model.labels.length, 104);
      expect(classifier.model.parentByChild, actual);
      expect(classifier.model.heads.first.labels.length, 21);
      final probabilities = classifier.scores('教育培训课程');
      expect(probabilities.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(probabilities, everyElement(inInclusiveRange(0, 1)));
    },
  );
  test(
    'permission levels protect strong evidence and same-parent boundaries',
    () {
      const fusion = EvidenceFusion();
      const strong = RecognitionEvidence(
        field: 'category',
        description: 'specific',
        score: .90,
        source: RecognitionEvidenceSource.categoryLexicon,
        role: EvidenceRole.product,
        specificity: EvidenceSpecificity.specific,
        semanticKey: 'expense.digital.phone',
      );
      final protected = fusion.fuse([strong]);
      expect(fusion.statisticalLevel(protected), 0);
      final uncertain = EvidenceFusionResult(
        semanticKey: strong.semanticKey,
        confidence: .64,
        issueCodes: const {RecognitionIssueCode.categoryAmbiguous},
        winningEvidence: const [strong],
      );
      expect(fusion.statisticalLevel(uncertain), 1);
      expect(fusion.statisticalLevel(fusion.fuse([])), 2);
      for (final source in [
        RecognitionEvidenceSource.familyPrior,
        RecognitionEvidenceSource.categoryLexicon,
      ]) {
        final general = fusion.fuse([
          RecognitionEvidence(
            field: 'category',
            description: 'general',
            score: .76,
            source: source,
            role: EvidenceRole.product,
            specificity: EvidenceSpecificity.general,
            semanticKey: 'expense.digital.phone',
          ),
        ]);
        expect(fusion.statisticalLevel(general), 2);
      }

      const sameParent = RecognitionEvidence(
        field: 'category',
        description: 'statistical',
        score: .69,
        source: RecognitionEvidenceSource.ngram,
        semanticKey: 'expense.digital.computer',
      );
      const crossParent = RecognitionEvidence(
        field: 'category',
        description: 'statistical',
        score: .69,
        source: RecognitionEvidenceSource.ngram,
        semanticKey: 'expense.pets.food',
      );
      expect(
        fusion.withWeakEvidence(
          uncertain,
          crossParent,
          RecognitionTransactionType.expense,
        ),
        same(uncertain),
      );
      expect(
        fusion
            .withWeakEvidence(
              uncertain,
              sameParent,
              RecognitionTransactionType.expense,
            )
            .semanticKey,
        sameParent.semanticKey,
      );
      expect(
        fusion.withWeakEvidence(
          protected,
          sameParent,
          RecognitionTransactionType.expense,
        ),
        same(protected),
      );
      final routed = classifier.hierarchicalEvidence(
        '电脑办公笔记本',
        RecognitionToolHarness.categories,
        level: 1,
        anchor: 'expense.digital.phone',
      );
      if (routed.evidence != null) {
        expect(
          classifier.model.parentByChild[routed.evidence!.semanticKey],
          'expense.digital',
        );
      }
      expect(
        classifier
            .hierarchicalEvidence(
              '电脑办公笔记本',
              RecognitionToolHarness.categories,
              level: 0,
            )
            .evidence,
        isNull,
      );
    },
  );
  test(
    'statistical type correction only changes a weak default and never refund',
    () {
      const inference = TypeInference();
      const expense = TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: .94,
        evidence: [],
      );
      const weakDefault = TypeDecision(
        type: RecognitionTransactionType.expense,
        isDefault: true,
        confidence: .88,
        evidence: [],
      );
      const evidence = RecognitionEvidence(
        field: 'category',
        description: 'statistical',
        score: .69,
        source: RecognitionEvidenceSource.ngram,
        semanticKey: 'income.salary.monthly',
      );
      expect(
        inference.reconcile(weakDefault, evidence.semanticKey, [
          evidence,
        ], statisticalParentConfidence: .84),
        same(weakDefault),
      );
      final corrected = inference.reconcile(weakDefault, evidence.semanticKey, [
        evidence,
      ], statisticalParentConfidence: .90);
      expect(corrected.type, RecognitionTransactionType.income);
      expect(corrected.confidence, lessThan(.80));
      expect(
        inference.reconcile(expense, evidence.semanticKey, [
          evidence,
        ], statisticalParentConfidence: .90).type,
        expense.type,
      );
      const refund = TypeDecision(
        type: RecognitionTransactionType.refund,
        confidence: .99,
        evidence: [],
      );
      expect(
        inference.reconcile(refund, evidence.semanticKey, [
          evidence,
        ], statisticalParentConfidence: .99),
        same(refund),
      );
      const refundEvidence = RecognitionEvidence(
        field: 'category',
        description: 'statistical',
        score: .69,
        source: RecognitionEvidenceSource.ngram,
        semanticKey: 'income.refund.shopping',
      );
      expect(
        inference.reconcile(weakDefault, refundEvidence.semanticKey, [
          refundEvidence,
        ], statisticalParentConfidence: .99),
        same(weakDefault),
      );
    },
  );
  test('archived pooled candidate matches exported int8 probabilities', () {
    final candidate = PooledCandidate.load();
    final vectors = jsonDecode(
      File('tools/ngram/stage_c_runtime_parity.json').readAsStringSync(),
    ) as List;
    for (final v in vectors) {
      final scores = candidate.scores(
        v['text'] as String,
        structuredFeatures: List<String>.from(v['features'] as List),
      );
      for (var i = 0; i < scores.length; i++) {
        expect(scores[i], closeTo((v['scores'][i] as num).toDouble(), 1e-10));
      }
    }
  });
}

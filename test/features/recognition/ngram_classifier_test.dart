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
  test(
    'Direction Head corrects only weak defaults and retains explicit direction',
    () {
      const inference = TypeInference();
      const weak = TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: .88,
        evidence: [],
        isDefault: true,
      );
      expect(
        inference.withStatisticalDirection(weak, .99, .8).type,
        RecognitionTransactionType.income,
      );
      expect(inference.withStatisticalDirection(weak, .6, .8), same(weak));
      expect(inference.withStatisticalDirection(weak, .5, .5), same(weak));
      for (final type in [
        RecognitionTransactionType.expense,
        RecognitionTransactionType.income,
        RecognitionTransactionType.refund,
      ]) {
        final strong = TypeDecision(type: type, confidence: .98, evidence: []);
        expect(
          inference.withStatisticalDirection(strong, .99, .8),
          same(strong),
        );
      }
    },
  );
  final bytes = File('assets/knowledge/ngram.bin').readAsBytesSync();
  final classifier = NgramClassifier(NgramModel.decode(bytes));
  test('independent direction handles weak income and preserves signs/refund safety', () {
    final harness = RecognitionToolHarness();
    final now = DateTime(2026, 10, 5, 12);
    for (final text in ['收到租金100元', '收到红包100元', '投资收益100元', '兼职收入100元']) {
      expect(
        harness.recognize(text, now: now).draft.type,
        RecognitionTransactionType.income,
        reason: text,
      );
    }
    expect(
      harness.recognize('房租 +100元', now: now).draft.type,
      RecognitionTransactionType.income,
    );
    expect(
      harness.recognize('投资收益 -100元', now: now).draft.type,
      RecognitionTransactionType.expense,
    );
    expect(
      harness.recognize('支付收益结算手续费100元', now: now).draft.type,
      RecognitionTransactionType.expense,
    );
    for (final text in [
      '退款猫粮30元',
      '交易失败 收到租金100元',
      '交易取消 收到红包100元',
      '支付成功 猫粮30元\n支付成功 狗粮40元',
    ]) {
      final r = harness.recognize(text, now: now);
      expect(r.confirmationLevel, ConfirmationLevel.blocked, reason: text);
      expect(r.canQuickConfirm, isFalse);
      expect(
        r.evidence.any((e) => e.family == 'statisticalDirection'),
        isFalse,
      );
    }
  });
  test(
    'weak child retains accepted parent and warning instead of global fallback',
    () {
      final n = ByteData.sublistView(bytes).getUint32(4, Endian.little);
      final header = jsonDecode(utf8.decode(bytes.sublist(8, 8 + n))) as Map;
      header['parentThreshold'] = 0;
      header['childCalibration'] = {
        for (final parent in classifier.model.heads.first.labels)
          parent: {'threshold': 1.0, 'margin': 1.0},
      };
      final raw = utf8.encode(jsonEncode(header));
      final changed = Uint8List(8 + raw.length + bytes.length - 8 - n);
      changed.setRange(0, 4, ascii.encode('LLNG'));
      ByteData.sublistView(changed).setUint32(4, raw.length, Endian.little);
      changed.setRange(8, 8 + raw.length, raw);
      changed.setRange(8 + raw.length, changed.length, bytes.sublist(8 + n));
      final c = NgramClassifier(NgramModel.decode(changed));
      final r = c.hierarchicalEvidence(
        '电脑办公笔记本',
        RecognitionToolHarness.categories,
        level: 2,
      );
      expect(r.evidence, isNotNull);
      expect(r.evidence!.family, 'statisticalUncertainChild');
      expect(r.evidence!.score, .55);
      expect(r.evidence!.semanticKey!.endsWith('.other.general'), isFalse);
    },
  );
  test('offline normalization and all class probabilities agree with Dart', () {
    final vectors = jsonDecode(
      File('tools/ngram/final96/parity_vectors.json').readAsStringSync(),
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
    'fusion treats ordinary semantic evidence as soft and protects direction',
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
      final corrected = fusion.withWeakEvidence(
        strong,
        weak,
        RecognitionTransactionType.expense,
      );
      expect(corrected.semanticKey, weak.semanticKey);
      expect(corrected.confidence, .69);
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
      if (before.fieldConfidence.type >= .90 ||
          before.status == TransactionStatus.refund) {
        expect(after.draft.type, before.draft.type);
      }
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
      expect(classifier.model.labels.length, 96);
      expect(classifier.model.parentByChild, actual);
      expect(classifier.model.heads.first.labels.length, 21);
      final probabilities = classifier.scores('教育培训课程');
      expect(probabilities.reduce((a, b) => a + b), closeTo(1, 1e-12));
      expect(probabilities, everyElement(inInclusiveRange(0, 1)));
    },
  );
  test(
    'ordinary evidence permits statistical parent correction; history locks',
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
      expect(fusion.statisticalLevel(protected), 2);
      final uncertain = EvidenceFusionResult(
        semanticKey: strong.semanticKey,
        confidence: .64,
        issueCodes: const {RecognitionIssueCode.categoryAmbiguous},
        winningEvidence: const [strong],
      );
      expect(fusion.statisticalLevel(uncertain), 2);
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
        fusion
            .withWeakEvidence(
              uncertain,
              crossParent,
              RecognitionTransactionType.expense,
            )
            .semanticKey,
        crossParent.semanticKey,
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
        fusion
            .withWeakEvidence(
              protected,
              sameParent,
              RecognitionTransactionType.expense,
            )
            .semanticKey,
        sameParent.semanticKey,
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

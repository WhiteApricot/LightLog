import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/ngram_classifier.dart';
import 'package:light_log/features/recognition/domain/ngram_model.dart';
import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

import '../../../tools/recognition_tool_harness.dart';

void main() {
  final bytes = File('assets/knowledge/ngram.bin').readAsBytesSync();
  final classifier = NgramClassifier(NgramModel.decode(bytes));
  test('offline normalization and all class probabilities agree with Dart', () {
    final vectors = jsonDecode(
      File('tools/ngram/parity_vectors.json').readAsStringSync(),
    ) as List;
    for (final v in vectors) {
      expect(NgramClassifier.normalize(v['text'] as String), v['normalized']);
      final scores = classifier.scores(v['text'] as String);
      final expected = v['scores'] as List;
      for (var i = 0; i < scores.length; i++) {
        expect(scores[i], closeTo((expected[i] as num).toDouble(), 1e-10));
      }
    }
    expect(NgramClassifier.normalize('ＡＢＣ１２３，猫🐈粮\n２０元'), 'abc 猫 粮 元');
    expect(classifier.evidence('123 ! 🐈'), isNull);
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
}

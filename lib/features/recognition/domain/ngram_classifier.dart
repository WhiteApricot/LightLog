import 'dart:math' as math;

import 'ngram_model.dart';
import 'recognition_models.dart';

class NgramClassifier {
  const NgramClassifier(this.model);
  final NgramModel model;

  /// Same codepoint contract as offline training; numbers/punctuation separate words.
  static String normalize(String text) {
    final chars = <int>[];
    var space = true;
    for (var c in text.runes.take(2048)) {
      if (c >= 0xff01 && c <= 0xff5e) c -= 0xfee0;
      if (c >= 65 && c <= 90) c += 32;
      if ((c >= 97 && c <= 122) || (c >= 0x3400 && c <= 0x9fff)) {
        chars.add(c);
        space = false;
      } else if (!space) {
        chars.add(32);
        space = true;
      }
    }
    if (chars.isNotEmpty && chars.last == 32) chars.removeLast();
    return String.fromCharCodes(chars);
  }

  List<double> scores(String rawText) {
    final text = normalize(rawText);
    final features = <int>{};
    for (var n = model.minGram; n <= model.maxGram; n++) {
      for (var i = 0; i + n <= text.length; i++) {
        final index = model.vocabulary[text.substring(i, i + n)];
        if (index != null) features.add(index);
      }
    }
    if (features.isEmpty) return List.filled(model.labels.length, 0);
    final sums = List<int>.filled(model.labels.length, 0);
    for (final feature in features) {
      final offset = feature * sums.length;
      for (var c = 0; c < sums.length; c++) {
        sums[c] += model.weights[offset + c];
      }
    }
    final logits = [
      for (var c = 0; c < sums.length; c++)
        sums[c] * model.scales[c] + model.bias[c],
    ];
    final maxLogit = logits.reduce(math.max);
    final probabilities = logits.map((v) => math.exp(v - maxLogit)).toList();
    final total = probabilities.reduce((a, b) => a + b);
    return probabilities.map((p) => p / total).toList();
  }

  RecognitionEvidence? evidence(String rawText) {
    final probabilities = scores(rawText);
    var first = 0;
    var second = 0.0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[first]) {
        second = probabilities[first];
        first = i;
      } else {
        second = math.max(second, probabilities[i]);
      }
    }
    final p = probabilities[first];
    if (p < model.threshold || p - second < model.margin) return null;
    return RecognitionEvidence(
      field: 'category',
      description: '本地字符模型弱证据（需确认）',
      score: p.clamp(.40, .69),
      source: RecognitionEvidenceSource.ngram,
      semanticKey: model.labels[first],
      family: 'ngram',
      role: EvidenceRole.context,
    );
  }
}

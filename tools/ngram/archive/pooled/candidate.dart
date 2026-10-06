import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:light_log/features/recognition/domain/ngram_classifier.dart';
import 'package:light_log/features/recognition/domain/ngram_model.dart';

/// Archived experimental backend. Never imported by lib/ or App providers.
class PooledCandidate extends NgramClassifier {
  PooledCandidate._(
    super.model,
    this.dimension,
    this.embeddingScales,
    this.embeddings,
    this.classifierWeights,
    this.heads,
  );
  factory PooledCandidate.load() {
    final bytes = File('tools/ngram/archive/pooled/candidate.bin')
        .readAsBytesSync();
    final n = ByteData.sublistView(bytes).getUint32(4, Endian.little);
    final h = jsonDecode(utf8.decode(bytes.sublist(8, 8 + n))) as Map;
    final base = File('tools/ngram/archive/104-final/ngram.bin')
        .readAsBytesSync();
    final bn = ByteData.sublistView(base).getUint32(4, Endian.little);
    final bh = jsonDecode(utf8.decode(base.sublist(8, 8 + bn))) as Map;
    for (final key in [
      'parentThreshold',
      'parentMargin',
      'childThreshold',
      'childMargin',
    ]) {
      bh[key] = h[key];
    }
    final header = utf8.encode(jsonEncode(bh));
    final adapted = Uint8List(8 + header.length + base.length - 8 - bn);
    adapted.setRange(0, 4, ascii.encode('LLNG'));
    ByteData.sublistView(adapted).setUint32(4, header.length, Endian.little);
    adapted.setRange(8, 8 + header.length, header);
    adapted.setRange(8 + header.length, adapted.length, base.sublist(8 + bn));
    final model = NgramModel.decode(adapted);
    if (jsonEncode(model.labels) != jsonEncode(h['labels']) ||
        jsonEncode(model.vocabulary.keys.toList()) !=
            jsonEncode(h['vocabulary']) ||
        jsonEncode(model.structuredVocabulary.keys.toList()) !=
            jsonEncode(h['structuredVocabulary'])) {
      throw StateError('Candidate shared contract differs');
    }
    final dim = h['embeddingDimension'] as int;
    final featureCount =
        model.vocabulary.length + model.structuredVocabulary.length;
    return PooledCandidate._(
      model,
      dim,
      [for (final v in h['embeddingScales'] as List) (v as num).toDouble()],
      Int8List.fromList(bytes.sublist(8 + n, 8 + n + dim * featureCount)),
      Int8List.fromList(bytes.sublist(8 + n + dim * featureCount)),
      [for (final head in h['heads'] as List) NgramHead.decode(head as Map)],
    );
  }
  final int dimension;
  final List<double> embeddingScales;
  final Int8List embeddings, classifierWeights;
  final List<NgramHead> heads;
  @override
  List<double> scores(
    String rawText, {
    List<String> structuredFeatures = const [],
  }) {
    final text = NgramClassifier.normalize(rawText);
    final features = <int>{};
    for (var n = model.minGram; n <= model.maxGram; n++) {
      for (var i = 0; i + n <= text.length; i++) {
        final f = model.vocabulary[text.substring(i, i + n)];
        if (f != null) features.add(f);
      }
    }
    for (final term in structuredFeatures) {
      final f = model.structuredVocabulary[term];
      if (f != null) features.add(f);
    }
    if (features.isEmpty) return List.filled(model.labels.length, 0);
    final pooled = List<double>.filled(dimension, 0);
    for (final f in features) {
      for (var d = 0; d < dimension; d++) {
        pooled[d] +=
            embeddings[f * dimension + d] *
            embeddingScales[f] /
            features.length;
      }
    }
    List<double> headScores(NgramHead head) {
      final z = [for (final v in head.bias) v];
      for (var d = 0; d < dimension; d++) {
        for (var c = 0; c < z.length; c++) {
          z[c] +=
              pooled[d] *
              classifierWeights[head.offset + d * z.length + c] *
              head.scales[c];
        }
      }
      final max = z.reduce(math.max);
      final p = z.map((v) => math.exp(v - max)).toList();
      final total = p.reduce((a, b) => a + b);
      return p.map((v) => v / total).toList();
    }

    final pp = headScores(heads.first);
    final joint = <String, double>{};
    for (var i = 0; i < pp.length; i++) {
      final parent = heads.first.labels[i];
      final head = heads.where((h) => h.parent == parent).firstOrNull;
      if (head == null) {
        joint[model.labels.singleWhere(
              (l) => model.parentByChild[l] == parent,
            )] =
            pp[i];
      } else {
        final cp = headScores(head);
        for (var j = 0; j < cp.length; j++) {
          joint[head.labels[j]] = pp[i] * cp[j];
        }
      }
    }
    return [for (final label in model.labels) joint[label]!];
  }
}

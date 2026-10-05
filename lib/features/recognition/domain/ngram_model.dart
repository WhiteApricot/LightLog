import 'dart:convert';
import 'dart:typed_data';

/// Versioned feature-major int8 weights, with a separate scale for each class.
class NgramModel {
  NgramModel._(
    this.labels,
    this.vocabulary,
    this.scales,
    this.bias,
    this.weights,
    this.minGram,
    this.maxGram,
    this.threshold,
    this.margin,
  );

  factory NgramModel.decode(Uint8List bytes) {
    if (bytes.length < 8 || ascii.decode(bytes.sublist(0, 4)) != 'LLNG') {
      throw const FormatException('Invalid n-gram asset magic');
    }
    final length = ByteData.sublistView(bytes).getUint32(4, Endian.little);
    if (length > bytes.length - 8) {
      throw const FormatException('Truncated n-gram header');
    }
    final h = jsonDecode(utf8.decode(bytes.sublist(8, 8 + length))) as Map;
    if (h['version'] != 1 || h['normalization'] != 'ascii-cjk-space-v1') {
      throw const FormatException('Unsupported n-gram asset version');
    }
    final labels = List<String>.from(h['labels'] as List);
    final terms = List<String>.from(h['vocabulary'] as List);
    final scales = (h['scales'] as List)
        .map((v) => (v as num).toDouble())
        .toList();
    final bias = (h['bias'] as List).map((v) => (v as num).toDouble()).toList();
    final grams = List<int>.from(h['grams'] as List);
    final threshold = (h['threshold'] as num).toDouble();
    final margin = (h['margin'] as num).toDouble();
    if (labels.isEmpty ||
        labels.toSet().length != labels.length ||
        terms.toSet().length != terms.length ||
        scales.length != labels.length ||
        bias.length != labels.length ||
        scales.any((v) => !v.isFinite || v <= 0) ||
        bias.any((v) => !v.isFinite) ||
        grams.length != 2 ||
        grams[0] < 2 ||
        grams[1] > 4 ||
        grams[0] > grams[1] ||
        !threshold.isFinite ||
        threshold < 0 ||
        threshold > 1 ||
        !margin.isFinite ||
        margin < 0 ||
        margin > 1 ||
        bytes.length != 8 + length + terms.length * labels.length) {
      throw const FormatException('Invalid n-gram asset dimensions/parameters');
    }
    return NgramModel._(
      List.unmodifiable(labels),
      Map.unmodifiable({for (var i = 0; i < terms.length; i++) terms[i]: i}),
      List.unmodifiable(scales),
      List.unmodifiable(bias),
      Int8List.fromList(bytes.sublist(8 + length)),
      grams[0],
      grams[1],
      threshold,
      margin,
    );
  }

  final List<String> labels;
  final Map<String, int> vocabulary;
  final List<double> scales;
  final List<double> bias;
  final Int8List weights;
  final int minGram;
  final int maxGram;
  final double threshold;
  final double margin;
}

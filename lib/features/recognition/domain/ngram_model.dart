import 'dart:convert';
import 'dart:typed_data';

/// One shared vocabulary and quantized parent / parent-specific child heads.
class NgramModel {
  NgramModel._(
    this.labels,
    this.vocabulary,
    this.structuredVocabulary,
    this.parentByChild,
    this.heads,
    this.weights,
    this.minGram,
    this.maxGram,
    this.parentThreshold,
    this.parentMargin,
    this.childThreshold,
    this.childMargin,
  );
  factory NgramModel.decode(Uint8List bytes) {
    if (bytes.length < 8 || ascii.decode(bytes.sublist(0, 4)) != 'LLNG') {
      throw const FormatException('Invalid classifier magic');
    }
    final length = ByteData.sublistView(bytes).getUint32(4, Endian.little);
    if (length > bytes.length - 8) {
      throw const FormatException('Truncated classifier header');
    }
    final h = jsonDecode(utf8.decode(bytes.sublist(8, 8 + length))) as Map;
    if (h['version'] != 2 ||
        h['backend'] != 'hierarchical-lr' ||
        h['normalization'] != 'ascii-cjk-space-v1') {
      throw const FormatException('Unsupported classifier contract');
    }
    final labels = List<String>.from(h['labels'] as List);
    final terms = List<String>.from(h['vocabulary'] as List);
    final structured = List<String>.from(h['structuredVocabulary'] as List);
    final parents = Map<String, String>.from(h['parentByChild'] as Map);
    final heads = [
      for (final raw in h['heads'] as List) NgramHead.decode(raw as Map),
    ];
    final grams = List<int>.from(h['grams'] as List);
    final parameters = [
      for (final k in [
        'parentThreshold',
        'parentMargin',
        'childThreshold',
        'childMargin',
      ])
        (h[k] as num).toDouble(),
    ];
    final dimension = terms.length + structured.length;
    var expected = 0;
    for (final head in heads) {
      if (head.offset != expected) {
        throw const FormatException('Noncontiguous classifier heads');
      }
      expected += dimension * head.labels.length;
    }
    final childLabels = heads.skip(1).expand((h) => h.labels).toList();
    final children = childLabels.toSet();
    final parentClasses = parents.values.toSet();
    if (labels.isEmpty ||
        labels.toSet().length != labels.length ||
        terms.toSet().length != terms.length ||
        structured.toSet().length != structured.length ||
        dimension == 0 ||
        childLabels.length != children.length ||
        parents.values.any((p) => p.isEmpty) ||
        parents.length != labels.length ||
        !labels.every(parents.containsKey) ||
        heads.isEmpty ||
        heads.first.parent != null ||
        heads.first.labels.toSet().length != parentClasses.length ||
        !heads.first.labels.every(parentClasses.contains) ||
        heads
            .skip(1)
            .any(
              (h) =>
                  h.parent == null ||
                  h.labels.length < 2 ||
                  h.labels.any((l) => parents[l] != h.parent),
            ) ||
        heads.skip(1).map((h) => h.parent).toSet().length != heads.length - 1 ||
        labels.any(
          (l) =>
              !children.contains(l) &&
              parents.values.where((p) => p == parents[l]).length != 1,
        ) ||
        grams.length != 2 ||
        grams[0] < 2 ||
        grams[1] > 4 ||
        grams[0] > grams[1] ||
        parameters.any((p) => !p.isFinite || p < 0 || p > 1) ||
        bytes.length != 8 + length + expected) {
      throw const FormatException('Invalid classifier dimensions/parameters');
    }
    return NgramModel._(
      List.unmodifiable(labels),
      Map.unmodifiable({for (var i = 0; i < terms.length; i++) terms[i]: i}),
      Map.unmodifiable({
        for (var i = 0; i < structured.length; i++)
          structured[i]: terms.length + i,
      }),
      Map.unmodifiable(parents),
      List.unmodifiable(heads),
      Int8List.fromList(bytes.sublist(8 + length)),
      grams[0],
      grams[1],
      parameters[0],
      parameters[1],
      parameters[2],
      parameters[3],
    );
  }
  final List<String> labels;
  final Map<String, int> vocabulary, structuredVocabulary;
  final Map<String, String> parentByChild;
  final List<NgramHead> heads;
  final Int8List weights;
  final int minGram, maxGram;
  final double parentThreshold, parentMargin, childThreshold, childMargin;
}

class NgramHead {
  NgramHead._(this.labels, this.parent, this.offset, this.scales, this.bias);
  factory NgramHead.decode(Map h) {
    final labels = List<String>.from(h['labels'] as List);
    final scales = [for (final v in h['scales'] as List) (v as num).toDouble()];
    final bias = [for (final v in h['bias'] as List) (v as num).toDouble()];
    if (labels.isEmpty ||
        labels.toSet().length != labels.length ||
        scales.length != labels.length ||
        bias.length != labels.length ||
        scales.any((v) => !v.isFinite || v <= 0) ||
        bias.any((v) => !v.isFinite)) {
      throw const FormatException('Invalid classifier head');
    }
    return NgramHead._(
      List.unmodifiable(labels),
      h['parent'] as String?,
      h['offset'] as int,
      List.unmodifiable(scales),
      List.unmodifiable(bias),
    );
  }
  final List<String> labels;
  final String? parent;
  final int offset;
  final List<double> scales, bias;
}

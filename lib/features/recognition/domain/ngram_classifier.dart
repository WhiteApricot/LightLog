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

  List<double> scores(
    String rawText, {
    List<String> structuredFeatures = const [],
  }) => predict(rawText, structuredFeatures: structuredFeatures).scores;

  Set<int> _features(String rawText, List<String> structuredFeatures) {
    final text = normalize(rawText);
    final features = <int>{};
    for (var n = model.minGram; n <= model.maxGram; n++) {
      for (var i = 0; i + n <= text.length; i++) {
        final index = model.vocabulary[text.substring(i, i + n)];
        if (index != null) features.add(index);
      }
    }
    for (final term in structuredFeatures) {
      final index = model.structuredVocabulary[term];
      if (index != null) features.add(index);
    }
    return features;
  }

  List<double> _headScores(NgramHead head, Set<int> features) {
    final sums = List<int>.filled(head.labels.length, 0);
    for (final feature in features) {
      final offset = head.offset + feature * sums.length;
      for (var c = 0; c < sums.length; c++) {
        sums[c] += model.weights[offset + c];
      }
    }
    final logits = [
      for (var c = 0; c < sums.length; c++)
        sums[c] * head.scales[c] + head.bias[c],
    ];
    final maxLogit = logits.reduce(math.max);
    final probabilities = logits.map((v) => math.exp(v - maxLogit)).toList();
    final total = probabilities.reduce((a, b) => a + b);
    return probabilities.map((p) => p / total).toList();
  }

  static final mealTimeMask = RegExp(
    r'早餐|午餐|晚餐|早饭|午饭|晚饭|早上|中午|晚上|清晨|早晨|上午|下午|正午|午间|晚间|凌晨|今早|昨晚|今晚|'
    r'[零〇一二两三四五六七八九十\d]{1,3}点(?:半|[零〇一二两三四五六七八九十\d]{1,3}分)?|\d{1,2}:\d{2}',
  );

  ({
    List<double> scores,
    double incomeProbability,
    double preparedMealProbability,
  })
  predict(String rawText, {List<String> structuredFeatures = const []}) {
    final features = _features(rawText, structuredFeatures);
    if (features.isEmpty) {
      return (
        scores: List.filled(model.labels.length, 0),
        incomeProbability: .5,
        preparedMealProbability: 0,
      );
    }

    final parent = model.heads.first;
    final pp = _headScores(parent, features);
    final joint = <String, double>{};
    for (var i = 0; i < parent.labels.length; i++) {
      final key = parent.labels[i];
      final head = model.heads.where((h) => h.parent == key).firstOrNull;
      if (head == null) {
        final child = model.labels.singleWhere(
          (l) => model.parentByChild[l] == key,
        );
        joint[child] = pp[i];
      } else {
        final cp = _headScores(head, features);
        for (var j = 0; j < head.labels.length; j++) {
          joint[head.labels[j]] = pp[i] * cp[j];
        }
      }
    }
    final direction = model.heads
        .where((h) => h.parent == '@direction')
        .firstOrNull;
    final meal = model.heads.where((h) => h.parent == '@meal').firstOrNull;
    final maskedFeatures = meal == null
        ? <int>{}
        : _features(rawText.replaceAll(mealTimeMask, ' '), const []);
    return (
      scores: [for (final label in model.labels) joint[label]!],
      incomeProbability: direction == null
          ? .5
          : _headScores(direction, features)[direction.labels.indexOf(
              'income',
            )],
      preparedMealProbability: meal == null || maskedFeatures.isEmpty
          ? 0
          : _headScores(meal, maskedFeatures)[meal.labels.indexOf('meal')],
    );
  }

  /// One feature extraction feeds both parent aggregation and child routing.
  ({RecognitionEvidence? evidence, double parentConfidence})
  hierarchicalEvidence(
    String rawText,
    List<RecognitionCategory> categories, {
    required int level,
    String? anchor,
    List<String> structuredFeatures = const [],
    List<double>? probabilitiesOverride,
    String? direction,
    double deterministicSupport = 0,
  }) {
    final byId = {
      for (final c in categories)
        if (c.isActive) c.id: c,
    };
    final parentByChild = <String, String>{};
    for (final c in categories) {
      final parent = byId[c.parentId];
      if (c.isActive && c.semanticKey != null && parent?.semanticKey != null) {
        parentByChild[c.semanticKey!] = parent!.semanticKey!;
      }
    }
    final probabilities =
        probabilitiesOverride ??
        scores(rawText, structuredFeatures: structuredFeatures);
    final parents = <String, double>{};
    for (var i = 0; i < probabilities.length; i++) {
      final parent = parentByChild[model.labels[i]];
      if (parent != null &&
          (direction == null || parent.startsWith('$direction.'))) {
        parents[parent] = (parents[parent] ?? 0) + probabilities[i];
      }
    }
    if (model.fusion == 'F2' && anchor != null) {
      final parent = parentByChild[anchor];
      if (parent != null && parents.containsKey(parent)) {
        parents[parent] =
            parents[parent]! +
            model.parentPrior * deterministicSupport.clamp(0, 1);
      }
    }
    final ranked = parents.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ranked.isEmpty || level == 0) {
      return (evidence: null, parentConfidence: 0);
    }
    final selected = level == 1 ? parentByChild[anchor] : ranked.first.key;
    final mass = [
      for (var i = 0; i < probabilities.length; i++)
        if (parentByChild[model.labels[i]] == selected) probabilities[i],
    ].fold<double>(0, (a, b) => a + b);
    if (mass <= 0 ||
        mass < model.parentThreshold ||
        (level == 2 &&
            ranked.first.value - (ranked.length > 1 ? ranked[1].value : 0) <
                model.parentMargin)) {
      return (evidence: null, parentConfidence: mass);
    }
    final children = [
      for (var i = 0; i < model.labels.length; i++)
        if (parentByChild[model.labels[i]] == selected) i,
    ]..sort((a, b) => probabilities[b].compareTo(probabilities[a]));
    final first = children.first;
    final conditional = probabilities[first] / mass;
    final margin =
        (probabilities[first] -
            (children.length > 1 ? probabilities[children[1]] : 0)) /
        mass;
    final calibration = model.childCalibration[selected];
    final uncertainChild =
        conditional < (calibration?['threshold'] ?? model.childThreshold) ||
        margin < (calibration?['margin'] ?? model.childMargin);
    return (
      evidence: RecognitionEvidence(
        field: 'category',
        description: '本地层级字符模型弱证据（需确认）',
        score: uncertainChild
            ? .55
            : math.min(mass, conditional).clamp(.40, .69),
        source: RecognitionEvidenceSource.ngram,
        semanticKey: model.labels[first],
        family: uncertainChild
            ? 'statisticalUncertainChild'
            : level == 1
            ? 'statisticalSameParent'
            : 'statisticalParentRouting',
        role: EvidenceRole.context,
      ),
      parentConfidence: mass,
    );
  }

  static List<String> structuredFeatures(
    TypeDecision type,
    List<RecognitionEvidence> evidence,
    Map<String, String> taxonomy,
  ) => [
    for (final e in evidence) ...[
      if (e.negative) 'negative:${e.semanticKey}',
      'source:${e.source.name}',
      'role:${e.role.name}',
      'specificity:${e.specificity.name}',
      if (e.family != null) 'family:${e.family}',
      if (e.semanticKey != null) 'parent:${taxonomy[e.semanticKey]}',
      if (e.semanticKey != null) 'semantic:${e.semanticKey}',
    ],
  ];
}

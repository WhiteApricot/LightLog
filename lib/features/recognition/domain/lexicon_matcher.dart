import 'knowledge_models.dart';
import 'normalization.dart';
import 'recognition_models.dart';

class LexiconMatcher {
  const LexiconMatcher(this.catalog);

  final KnowledgeCatalog catalog;

  List<RecognitionEvidence> match(String matchingText) {
    final compact = _CompactText.from(matchingText);
    if (compact.value.isEmpty) return const [];
    final result = <RecognitionEvidence>[];
    final seen = <String>{};
    final candidates = <LexiconKnowledge>{};
    for (final rune in compact.value.runes.toSet()) {
      candidates.addAll(
        catalog.lexiconByFirstCharacter[String.fromCharCode(rune)] ?? const [],
      );
    }
    for (final item in candidates) {
      final term = RecognitionNormalizer.indexKey(item.term);
      final start = compact.value.indexOf(term);
      if (term.isEmpty || start < 0) continue;
      final id = '${item.semanticKey}:$term:${item.role.name}';
      if (!seen.add(id)) continue;
      final conflict = item.negativeTerms
          .map(RecognitionNormalizer.indexKey)
          .where(compact.value.contains)
          .firstOrNull;
      result.add(
        RecognitionEvidence(
          field: 'category',
          source: RecognitionEvidenceSource.categoryLexicon,
          semanticKey: item.semanticKey,
          description: conflict == null
              ? '类别词典命中“${item.term}”'
              : '“${item.term}”被冲突词“$conflict”抑制',
          score: conflict == null ? item.score : 0.9,
          negative: conflict != null,
          role: item.role,
          specificity: item.specificity,
          matchedText: item.term,
          family: 'lexicon:$term',
          span: compact.sourceRange(start, start + term.length),
        ),
      );
    }
    result.addAll(_modifierEvidence(compact.value));
    return List.unmodifiable(result);
  }

  static List<RecognitionEvidence> _modifierEvidence(String text) {
    final rules = <({RegExp modifier, RegExp expression, String semantic})>[
      (
        modifier: RegExp(r'宠物|猫|狗'),
        expression: RegExp(r'美容|洗护|洗澡|剪毛|修毛'),
        semantic: 'expense.pets.grooming',
      ),
      (
        modifier: RegExp(r'宠物|猫|狗'),
        expression: RegExp(r'寄养|托管|遛狗'),
        semantic: 'expense.pets.service',
      ),
      (
        modifier: RegExp(r'汽车|车辆|轿车|爱车|车子'),
        expression: RegExp(r'洗车|维修|保养|换机油|补胎'),
        semantic: 'expense.transport.maintenance',
      ),
    ];
    return [
      for (final rule in rules)
        if (rule.modifier.hasMatch(text) && rule.expression.hasMatch(text))
          RecognitionEvidence(
            field: 'category',
            source: RecognitionEvidenceSource.context,
            semanticKey: rule.semantic,
            description: '修饰对象与行为组合语义',
            score: 0.93,
            role: EvidenceRole.action,
            specificity: EvidenceSpecificity.specific,
            family: 'modifierAction:${rule.semantic}',
          ),
    ];
  }
}

class _CompactText {
  const _CompactText(this.value, this.sourceOffsets);

  factory _CompactText.from(String source) {
    final value = StringBuffer();
    final offsets = <int>[];
    for (var index = 0; index < source.length; index++) {
      final character = source[index];
      if (RegExp(r"[\s,.:：·_\-/\\'’]").hasMatch(character)) continue;
      value.write(character);
      offsets.add(index);
    }
    return _CompactText(value.toString(), offsets);
  }

  final String value;
  final List<int> sourceOffsets;

  TextSpanRange sourceRange(int start, int end) => TextSpanRange(
    start: sourceOffsets[start],
    end: sourceOffsets[end - 1] + 1,
  );
}

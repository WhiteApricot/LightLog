import 'recognition_models.dart';

class ContextEvidenceBuilder {
  const ContextEvidenceBuilder();

  List<RecognitionEvidence> build({
    required String matchingText,
    required int occurredHour,
    required bool timeIsExplicit,
    List<RecognitionEvidence> entityEvidence = const [],
  }) {
    final explicitMeal = <(RegExp, String)>[
      (RegExp(r'早餐|早点|早饭'), 'expense.food.breakfast'),
      (RegExp(r'午餐|午饭'), 'expense.food.lunch'),
      (RegExp(r'晚餐|晚饭|夜宵'), 'expense.food.dinner'),
    ];
    for (final (pattern, semanticKey) in explicitMeal) {
      final match = pattern.firstMatch(matchingText);
      if (match != null) {
        return [
          RecognitionEvidence(
            field: 'category',
            source: RecognitionEvidenceSource.context,
            semanticKey: semanticKey,
            description: '明确餐食行为“${match.group(0)}”',
            score: 0.91,
            role: EvidenceRole.action,
            specificity: EvidenceSpecificity.specific,
            matchedText: match.group(0),
            span: TextSpanRange(start: match.start, end: match.end),
            family: 'explicitMeal',
          ),
        ];
      }
    }
    final hasFoodMerchant = entityEvidence.any(
      (item) =>
          item.role == EvidenceRole.merchantType &&
          (item.semanticKey?.startsWith('expense.food.') ?? false),
    );
    final hasMealScene = RegExp(r'食堂|餐厅|吃饭|用餐').hasMatch(matchingText);
    final hasDaypart = RegExp(r'今早|早上|上午|中午|下午|昨晚|今晚|晚上')
        .hasMatch(matchingText);
    if (!hasMealScene && !(hasFoodMerchant && (hasDaypart || timeIsExplicit))) {
      return const [];
    }
    final semanticKey = switch (occurredHour) {
      >= 5 && < 10 => 'expense.food.breakfast',
      >= 10 && < 15 => 'expense.food.lunch',
      >= 17 && < 24 => 'expense.food.dinner',
      _ => 'expense.food.other',
    };
    return [
      RecognitionEvidence(
        field: 'category',
        source: RecognitionEvidenceSource.context,
        semanticKey: semanticKey,
        description: '餐食场景结合发生时段',
        score: hasFoodMerchant && (hasDaypart || timeIsExplicit) ? 0.84 : 0.70,
        role: hasFoodMerchant && (hasDaypart || timeIsExplicit)
            ? EvidenceRole.action
            : EvidenceRole.context,
        specificity: hasFoodMerchant && (hasDaypart || timeIsExplicit)
            ? EvidenceSpecificity.specific
            : EvidenceSpecificity.general,
        family: 'mealDaypart',
      ),
    ];
  }
}

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
    final hasMealEligibleMerchant = entityEvidence.any(
      (item) =>
          item.role == EvidenceRole.merchantType &&
          (item.semanticKey == 'expense.food.other' ||
              item.semanticKey == 'expense.food.takeout'),
    );
    final hasMealScene = RegExp(r'食堂|餐厅|吃饭|用餐|套餐|吃了|吃的').hasMatch(matchingText);
    final hasDaypart = RegExp(r'今早|早上|上午|中午|下午|昨晚|今晚|晚上')
        .hasMatch(matchingText);
    final hasExplicitClock = RegExp(r'(?<!\d)(?:[01]?\d|2[0-3]):[0-5]\d')
        .hasMatch(matchingText);
    final clockOnlyMealTime = !hasDaypart && timeIsExplicit && hasExplicitClock;
    final hasMealTime = hasDaypart || clockOnlyMealTime;
    if (!hasMealScene && !(hasMealEligibleMerchant && hasMealTime)) {
      return const [];
    }
    final semanticKey = switch (occurredHour) {
      >= 5 && < 10 => 'expense.food.breakfast',
      >= 10 && < 15 => 'expense.food.lunch',
      >= 17 && < 24 => 'expense.food.dinner',
      _ => 'expense.food.other',
    };
    final strongMealContext =
        hasMealTime && (hasMealScene || hasMealEligibleMerchant);
    return [
      RecognitionEvidence(
        field: 'category',
        source: RecognitionEvidenceSource.context,
        semanticKey: semanticKey,
        description: '餐食场景结合发生时段',
        score: strongMealContext ? 0.94 : 0.70,
        role: strongMealContext ? EvidenceRole.action : EvidenceRole.context,
        specificity: strongMealContext
            ? EvidenceSpecificity.specific
            : EvidenceSpecificity.general,
        family: clockOnlyMealTime ? 'mealDaypartClock' : 'mealDaypart',
      ),
    ];
  }
}

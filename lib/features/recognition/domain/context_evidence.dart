import 'recognition_models.dart';

class ContextEvidenceBuilder {
  const ContextEvidenceBuilder();

  static const mealSemantics = {
    'expense.food.breakfast',
    'expense.food.lunch',
    'expense.food.dinner',
  };

  // Complete, non-overlapping local-hour windows, including late-night meals.
  static const mealWindows = [
    (start: 5, end: 10, semantic: 'expense.food.breakfast'),
    (start: 10, end: 17, semantic: 'expense.food.lunch'),
    (start: 17, end: 24, semantic: 'expense.food.dinner'),
    (start: 0, end: 5, semantic: 'expense.food.dinner'),
  ];

  static String mealForHour(int hour) => mealWindows
      .firstWhere((window) => hour >= window.start && hour < window.end)
      .semantic;

  // Purpose eligibility, not another category dictionary: use existing matched
  // food evidence. A channel, merchant name, drink/snack, or ingredient alone
  // is insufficient. Prepared staple morphology also covers unlisted dishes.
  static final _mainDish = RegExp(
    r'饭|面(?!包)|米粉|河粉|火锅|汉堡|披萨|寿司|日料|韩餐|西餐|'
    r'烤鱼|酸菜鱼|水煮鱼|黄焖鸡|烤肉|涮肉|麻辣烫|馄饨|水饺|饺子|'
    r'盒饭|便当|工作餐|沙拉餐|自助餐|堂食|点菜|餐费|餐饮费',
  );
  static final _preparedStaple = RegExp(
    r'(?:炒|拌|盖|焖|煲).{0,2}(?:饭|面|粉)(?!机|锅|工具|调料|原料|料包)',
  );
  static final _mealScene = RegExp(r'吃饭|用餐|正餐');
  static final _textTime = RegExp(
    r'(?<!\d)(?:[01]?\d|2[0-3]):[0-5]\d|'
    r'[零〇一二两三四五六七八九十\d]{1,3}点|'
    r'凌晨|今早|昨晚|今晚|早上|清晨|早晨|上午|中午|正午|午间|下午|晚上|晚间|早餐|早点|早饭|午餐|午饭|中饭|晚餐|晚饭|夜宵',
  );

  List<RecognitionEvidence> build({
    required String matchingText,
    required int occurredHour,
    required bool timeIsExplicit,
    List<RecognitionEvidence> entityEvidence = const [],
    bool preparedMeal = false,
  }) {
    final hasMealEvidence = entityEvidence.any(
      (e) =>
          !e.negative &&
          e.source != RecognitionEvidenceSource.ngram &&
          (mealSemantics.contains(e.semanticKey) ||
              (e.source == RecognitionEvidenceSource.categoryLexicon &&
                  e.semanticKey == 'expense.food.other' &&
                  e.specificity == EvidenceSpecificity.specific &&
                  e.role == EvidenceRole.product &&
                  _mainDish.hasMatch(e.matchedText ?? ''))),
    );
    final preparedProducts = entityEvidence
        .where(
          (e) =>
              !e.negative &&
              e.semanticKey == 'expense.food.other' &&
              e.role == EvidenceRole.product &&
              _mainDish.hasMatch(e.matchedText ?? ''),
        )
        .toList();
    final groceryPurchase = RegExp(r'买|采购|购入|囤|超市|市场|食材|生鲜|家庭采购')
        .hasMatch(matchingText);
    final hasNonMealFood = entityEvidence.any(
      (e) =>
          !e.negative &&
              e.specificity == EvidenceSpecificity.specific &&
              const {
                'expense.food.drink',
                'expense.food.snack',
              }.contains(e.semanticKey) ||
          (!e.negative &&
              e.specificity == EvidenceSpecificity.specific &&
              e.semanticKey == 'expense.food.groceries' &&
              groceryPurchase &&
              !preparedProducts.any(
                (p) =>
                    p.span != null &&
                    e.span != null &&
                    p.span!.start <= e.span!.start &&
                    p.span!.end >= e.span!.end &&
                    p.matchedText != e.matchedText,
              )),
    );
    if (hasNonMealFood ||
        RegExp(r'夜宵|宵夜|小吃|食材|生鲜|买菜|家庭采购').hasMatch(matchingText)) {
      return const [];
    }
    final cafeteriaMeal = matchingText.contains('食堂') && !hasNonMealFood;
    // Preserve the existing weak restaurant + explicit transaction-time path.
    final restaurantMeal =
        !hasNonMealFood &&
        timeIsExplicit &&
        _textTime.hasMatch(matchingText) &&
        entityEvidence.any(
          (e) =>
              !e.negative &&
              e.role == EvidenceRole.merchantType &&
              e.semanticKey == 'expense.food.other',
        );
    if (!preparedMeal &&
        !hasMealEvidence &&
        !cafeteriaMeal &&
        !restaurantMeal &&
        !_mealScene.hasMatch(matchingText) &&
        !_preparedStaple.hasMatch(matchingText)) {
      return const [];
    }
    final explicitTime = timeIsExplicit && _textTime.hasMatch(matchingText);
    return [
      RecognitionEvidence(
        field: 'category',
        source: RecognitionEvidenceSource.context,
        semanticKey: mealForHour(occurredHour),
        description: explicitTime ? '明确正餐按文本时刻归类' : '明确正餐按发生时刻归类',
        score: explicitTime ? .79 : .74,
        role: EvidenceRole.context,
        specificity: EvidenceSpecificity.specific,
        family: explicitTime ? 'mealByExplicitTime' : 'mealByOccurredAt',
      ),
    ];
  }
}

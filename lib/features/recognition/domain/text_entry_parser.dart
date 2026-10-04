import '../../../core/money.dart';
import '../../../data/database/database.dart';
import '../../ledger/domain/ledger_models.dart';
import 'category_resolver.dart';
import 'evidence_fusion.dart';
import 'knowledge_catalog.dart';
import 'natural_time_parser.dart';
import 'ngram_classifier.dart';
import 'normalization.dart';
import 'personal_history.dart';
import 'recognition_models.dart';

class TextEntryParser {
  TextEntryParser({
    KnowledgeCatalog? knowledge,
    this.ngramClassifier = const DisabledNgramClassifier(),
  }) : _knowledge = knowledge ?? KnowledgeCatalog.empty();

  final KnowledgeCatalog _knowledge;
  final NgramClassifier ngramClassifier;
  static const _normalizer = RecognitionNormalizer();
  static const _timeParser = NaturalTimeParser();
  static const _historyMatcher = PersonalHistoryMatcher();
  static const _fusion = EvidenceFusion();
  static const _resolver = CategoryResolver();

  static final RegExp _amountPattern = RegExp(
    r'(?<![\d.])([+-]?\d+(?:\.\d{1,2})?)(?:\s*(?:元|块))?(?![\d.])',
  );

  RecognitionCandidate parse({
    required String rawText,
    required List<Category> categories,
    required DateTime now,
    List<PersonalHistoryRecord> history = const [],
  }) {
    final normalizedInput = _normalizer.normalize(rawText);
    final evidence = <RecognitionEvidence>[];
    final issues = <String>[];
    final blockingIssues = <String>[];

    final parsedTime = _timeParser.parse(normalizedInput.normalizedText, now);
    if (parsedTime.isExplicit) {
      evidence.add(
        RecognitionEvidence(
          field: 'time',
          description: parsedTime.description ?? '识别到明确时间',
          score: 0.10,
        ),
      );
    }

    final amountMatches = _amountPattern
        .allMatches(parsedTime.remaining)
        .toList();
    int? amountMinor;
    String? signedAmount;
    var contentSource = parsedTime.remaining;
    if (amountMatches.isEmpty) {
      blockingIssues.add('未识别到金额');
    } else if (amountMatches.length > 1) {
      blockingIssues.add('识别到多个金额，请手动确认');
    } else {
      final match = amountMatches.single;
      signedAmount = match.group(1)!;
      amountMinor = MoneyParser.parseCnyMinor(
        signedAmount.replaceFirst(RegExp(r'^[+-]'), ''),
      );
      if (amountMinor == null) {
        blockingIssues.add('金额格式无效');
      } else {
        evidence.add(
          const RecognitionEvidence(
            field: 'amount',
            description: '识别到唯一有效金额',
            score: 0.35,
          ),
        );
      }
      contentSource = contentSource.replaceRange(match.start, match.end, ' ');
    }

    final typeResult = _detectType(
      normalizedInput.normalizedText,
      signedAmount,
    );
    evidence.add(
      RecognitionEvidence(
        field: 'type',
        description: typeResult.description,
        score: typeResult.explicit ? 0.15 : 0.05,
      ),
    );

    final content = _cleanContent(contentSource);
    final normalizedContent = _normalizer.normalize(content);
    if (content.isEmpty) {
      blockingIssues.add('未识别到内容或商户');
    } else {
      evidence.add(
        const RecognitionEvidence(
          field: 'content',
          description: '金额和时间之外存在可用内容',
          score: 0.15,
        ),
      );
    }

    final historyKey = RecognitionNormalizer.indexKey(
      normalizedContent.normalizedMerchant,
    );
    final merchantEvidence = _knowledge.matchMerchant(
      normalizedContent.normalizedMerchant,
    );
    final semanticEvidence =
        <RecognitionEvidence>[
              ..._historyMatcher.match(
                normalizedContent: historyKey,
                records: history,
                now: now,
              ),
              ?merchantEvidence,
              ..._knowledge.matchLexicon(normalizedContent.normalizedContent),
              ..._mealContextEvidence(
                normalizedContent.normalizedContent,
                parsedTime.value.hour,
              ),
              ...ngramClassifier.classify(
                normalizedText: normalizedContent.normalizedContent,
                normalizedMerchant: normalizedContent.normalizedMerchant,
              ),
            ]
            .where((item) {
              final semanticKey = item.semanticKey;
              return semanticKey == null ||
                  semanticKey.startsWith('${typeResult.type.value}.');
            })
            .toList(growable: false);
    evidence.addAll(semanticEvidence);

    final fusion = _fusion.fuse(semanticEvidence);
    issues.addAll(fusion.issues);
    final resolved = fusion.semanticKey == null
        ? null
        : _resolver.resolve(
            semanticKey: fusion.semanticKey!,
            type: typeResult.type,
            categories: categories,
          );
    if (fusion.semanticKey == null) {
      blockingIssues.add('无法可靠判断分类');
    } else if (resolved == null) {
      blockingIssues.add('当前分类中没有语义“${fusion.semanticKey}”的可用映射');
    }
    issues.addAll(blockingIssues);

    return RecognitionCandidate(
      draft: EntryDraft(
        rawText: rawText,
        normalizedText: normalizedInput.normalizedText,
        type: typeResult.type,
        amountMinor: amountMinor,
        content: content.isEmpty ? null : content,
        normalizedContent: normalizedContent.normalizedContent,
        normalizedMerchant: normalizedContent.normalizedMerchant,
        occurredAtLocal: parsedTime.value,
        timezoneOffsetMinutes: parsedTime.value.timeZoneOffset.inMinutes,
      ),
      categoryId: resolved?.parent.id,
      subcategoryId: resolved?.child.id,
      categoryName: resolved?.parent.name,
      subcategoryName: resolved?.child.name,
      semanticKey: fusion.semanticKey,
      confidence: fusion.confidence,
      evidence: List.unmodifiable(evidence),
      issues: List.unmodifiable(issues),
      blockingIssues: List.unmodifiable(blockingIssues),
    );
  }

  static String normalize(String input) =>
      RecognitionNormalizer.normalizeCharacters(input);

  static _TypeResult _detectType(String input, String? signedAmount) {
    if (signedAmount?.startsWith('+') ?? false) {
      return const _TypeResult(
        LedgerTransactionType.income,
        true,
        '金额带有收入符号 +',
      );
    }
    if (signedAmount?.startsWith('-') ?? false) {
      return const _TypeResult(
        LedgerTransactionType.expense,
        true,
        '金额带有支出符号 -',
      );
    }
    if (RegExp(r'工资|薪资|奖金|报销|兼职收入').hasMatch(input)) {
      return const _TypeResult(LedgerTransactionType.income, true, '收入关键词匹配');
    }
    return const _TypeResult(
      LedgerTransactionType.expense,
      false,
      '未发现收入标记，按支出候选处理',
    );
  }

  static String _cleanContent(String input) => input
      .replaceAll(RegExp(r'[¥￥]'), ' ')
      .replaceAll(RegExp(r'^[\s,。;:]+|[\s,。;:]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<RecognitionEvidence> _mealContextEvidence(
    String content,
    int hour,
  ) {
    if (!RegExp(r'食堂|餐厅|吃饭|早餐|午餐|晚餐').hasMatch(content)) {
      return const [];
    }
    final semanticKey = switch (hour) {
      >= 5 && < 10 => 'expense.food.breakfast',
      >= 10 && < 15 => 'expense.food.lunch',
      >= 17 && < 23 => 'expense.food.dinner',
      _ => 'expense.food.other',
    };
    return [
      RecognitionEvidence(
        field: 'category',
        source: RecognitionEvidenceSource.context,
        semanticKey: semanticKey,
        description: '餐食词结合发生时段提供弱上下文',
        score: 0.68,
      ),
    ];
  }
}

class _TypeResult {
  const _TypeResult(this.type, this.explicit, this.description);

  final LedgerTransactionType type;
  final bool explicit;
  final String description;
}

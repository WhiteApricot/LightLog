import '../../../core/money.dart';
import '../../../data/database/database.dart';
import '../../ledger/domain/ledger_models.dart';
import 'recognition_models.dart';

class TextEntryParser {
  const TextEntryParser();

  static final RegExp _clockPattern = RegExp(
    r'(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)',
  );
  static final RegExp _amountPattern = RegExp(
    r'(?<![\d.])([+-]?\d+(?:\.\d{1,2})?)(?:\s*(?:元|块))?(?![\d.])',
  );

  RecognitionCandidate parse({
    required String rawText,
    required List<Category> categories,
    required DateTime now,
  }) {
    final normalized = normalize(rawText);
    final evidence = <RecognitionEvidence>[];
    final issues = <String>[];

    final parsedTime = _parseTime(normalized, now);
    if (parsedTime.isExplicit) {
      evidence.add(
        const RecognitionEvidence(
          field: 'time',
          description: '识别到明确的日期或时间表达',
          weight: 0.10,
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
      issues.add('未识别到金额');
    } else if (amountMatches.length > 1) {
      issues.add('识别到多个金额，请手动确认');
    } else {
      final match = amountMatches.single;
      signedAmount = match.group(1)!;
      final unsignedAmount = signedAmount.replaceFirst(RegExp(r'^[+-]'), '');
      amountMinor = MoneyParser.parseCnyMinor(unsignedAmount);
      if (amountMinor == null) {
        issues.add('金额格式无效');
      } else {
        evidence.add(
          const RecognitionEvidence(
            field: 'amount',
            description: '识别到唯一且格式有效的金额',
            weight: 0.35,
          ),
        );
      }
      contentSource = contentSource.replaceRange(match.start, match.end, ' ');
    }

    final typeResult = _detectType(normalized, signedAmount);
    evidence.add(
      RecognitionEvidence(
        field: 'type',
        description: typeResult.description,
        weight: typeResult.explicit ? 0.15 : 0.05,
      ),
    );

    final content = _cleanContent(contentSource);
    if (content.isEmpty) {
      issues.add('未识别到内容或商户');
    } else {
      evidence.add(
        const RecognitionEvidence(
          field: 'content',
          description: '金额和时间之外存在可用内容',
          weight: 0.15,
        ),
      );
    }

    final classification = _classify(
      content: content,
      type: typeResult.type,
      hour: parsedTime.value.hour,
      categories: categories,
    );
    if (classification == null) {
      issues.add('数据库中缺少可用分类');
    } else {
      evidence.add(
        RecognitionEvidence(
          field: 'category',
          description: classification.description,
          weight: classification.keywordMatched ? 0.25 : 0.05,
        ),
      );
    }

    return RecognitionCandidate(
      draft: EntryDraft(
        rawText: rawText,
        normalizedText: normalized,
        type: typeResult.type,
        amountMinor: amountMinor,
        content: content.isEmpty ? null : content,
        occurredAtLocal: parsedTime.value,
        timezoneOffsetMinutes: parsedTime.value.timeZoneOffset.inMinutes,
      ),
      categoryId: classification?.parent.id,
      subcategoryId: classification?.child.id,
      categoryName: classification?.parent.name,
      subcategoryName: classification?.child.name,
      evidence: List.unmodifiable(evidence),
      issues: List.unmodifiable(issues),
    );
  }

  static String normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0xFFE5) {
        buffer.write('¥');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  _ParsedTime _parseTime(String input, DateTime now) {
    var remaining = input;
    var year = now.year;
    var month = now.month;
    var day = now.day;
    var hour = now.hour;
    var minute = now.minute;
    var explicit = false;

    final dayToken = [
      '昨晚',
      '昨天',
      '今早',
      '今晚',
      '今天',
    ].where(remaining.contains).firstOrNull;
    if (dayToken != null) {
      explicit = true;
      final base = dayToken == '昨晚' || dayToken == '昨天'
          ? DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(const Duration(days: 1))
          : DateTime(now.year, now.month, now.day);
      year = base.year;
      month = base.month;
      day = base.day;
      if (dayToken == '昨晚' || dayToken == '今晚') {
        hour = 20;
        minute = 0;
      } else if (dayToken == '今早') {
        hour = 8;
        minute = 0;
      }
      remaining = remaining.replaceFirst(dayToken, ' ');
    }

    final clockMatch = _clockPattern.firstMatch(remaining);
    if (clockMatch != null) {
      explicit = true;
      hour = int.parse(clockMatch.group(1)!);
      minute = int.parse(clockMatch.group(2)!);
      remaining = remaining.replaceRange(clockMatch.start, clockMatch.end, ' ');
    }

    return _ParsedTime(
      value: DateTime(year, month, day, hour, minute),
      remaining: remaining,
      isExplicit: explicit,
    );
  }

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
    if (RegExp(r'工资|薪资|奖金').hasMatch(input)) {
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
      .replaceAll(RegExp(r'^[\s,，。;；:：]+|[\s,，。;；:：]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static _Classification? _classify({
    required String content,
    required LedgerTransactionType type,
    required int hour,
    required List<Category> categories,
  }) {
    late String parentName;
    late String childName;
    late String description;
    var keywordMatched = true;

    if (type == LedgerTransactionType.income) {
      if (RegExp(r'工资|薪资').hasMatch(content)) {
        parentName = '工资奖金';
        childName = '基本工资';
        description = '“工资/薪资”匹配工资奖金 · 基本工资';
      } else {
        parentName = '其他收入';
        childName = '未分类收入';
        description = '没有收入分类关键词，使用其他收入 · 未分类收入';
        keywordMatched = false;
      }
    } else if (RegExp(r'星巴克|咖啡|奶茶|饮料').hasMatch(content)) {
      parentName = '餐饮';
      childName = '饮品';
      description = '饮品关键词匹配餐饮 · 饮品';
    } else if (RegExp(r'食堂|麦当劳|早餐|午餐|晚餐|饭|餐').hasMatch(content)) {
      parentName = '餐饮';
      childName = switch (hour) {
        >= 5 && < 10 => '早餐',
        >= 10 && < 15 => '午餐',
        >= 17 && < 23 => '晚餐',
        _ => '其他餐饮',
      };
      description = '餐饮关键词结合发生时间匹配餐饮 · $childName';
    } else if (RegExp(r'打车|出租|网约车').hasMatch(content)) {
      parentName = '交通';
      childName = '打车';
      description = '打车关键词匹配交通 · 打车';
    } else if (RegExp(r'公交|地铁').hasMatch(content)) {
      parentName = '交通';
      childName = '公交地铁';
      description = '公共交通关键词匹配交通 · 公交地铁';
    } else {
      parentName = '其他支出';
      childName = '未分类支出';
      description = '没有分类关键词，使用其他支出 · 未分类支出';
      keywordMatched = false;
    }

    final parent = categories
        .where(
          (item) =>
              item.parentId == null &&
              item.type == type.value &&
              item.name == parentName &&
              item.isActive,
        )
        .firstOrNull;
    if (parent == null) return null;
    final child = categories
        .where(
          (item) =>
              item.parentId == parent.id &&
              item.type == type.value &&
              item.name == childName &&
              item.isActive,
        )
        .firstOrNull;
    if (child == null) return null;
    return _Classification(
      parent: parent,
      child: child,
      description: description,
      keywordMatched: keywordMatched,
    );
  }
}

class _ParsedTime {
  const _ParsedTime({
    required this.value,
    required this.remaining,
    required this.isExplicit,
  });

  final DateTime value;
  final String remaining;
  final bool isExplicit;
}

class _TypeResult {
  const _TypeResult(this.type, this.explicit, this.description);

  final LedgerTransactionType type;
  final bool explicit;
  final String description;
}

class _Classification {
  const _Classification({
    required this.parent,
    required this.child,
    required this.description,
    required this.keywordMatched,
  });

  final Category parent;
  final Category child;
  final String description;
  final bool keywordMatched;
}

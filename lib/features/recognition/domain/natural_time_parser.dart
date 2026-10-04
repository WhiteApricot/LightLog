import 'recognition_models.dart';

class ParsedNaturalTime {
  const ParsedNaturalTime({
    required this.value,
    required this.remaining,
    required this.isExplicit,
    required this.description,
    this.spans = const [],
  });

  final DateTime value;
  final String remaining;
  final bool isExplicit;
  final String? description;
  final List<RecognizedSpan> spans;
}

class NaturalTimeParser {
  const NaturalTimeParser();

  static final RegExp _weekPattern = RegExp(r'(本周|上周)([一二三四五六日天])');
  static final RegExp _ambiguousWeekPattern = RegExp(r'(?<!本|上)周[一二三四五六日天]');
  static final RegExp _clockPattern = RegExp(
    r'(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?::([0-5]\d))?(?!\d)',
  );
  static final RegExp _hourPattern = RegExp(
    r'(?<!\d)([零〇一二两三四五六七八九十\d]{1,3})点(?:(半)|([零〇一二两三四五六七八九十\d]{1,3})分?)?',
  );
  static final RegExp _absoluteDatePattern = RegExp(
    r'(?:(\d{4})\s*年\s*)?(\d{1,2})\s*月\s*(\d{1,2})\s*[日号]|(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})',
  );

  ParsedNaturalTime parse(String input, DateTime now) {
    var remaining = input;
    var date = DateTime(now.year, now.month, now.day);
    var hour = now.hour;
    var minute = now.minute;
    var explicit = false;
    String? description;

    final absoluteDates = <({RegExpMatch match, DateTime value, int score})>[];
    for (final match in _absoluteDatePattern.allMatches(remaining)) {
      final year =
          int.tryParse(match.group(1) ?? match.group(4) ?? '') ?? now.year;
      final month = int.parse(match.group(2) ?? match.group(5)!);
      final day = int.parse(match.group(3) ?? match.group(6)!);
      final candidate = DateTime(year, month, day);
      if (candidate.year != year ||
          candidate.month != month ||
          candidate.day != day) {
        continue;
      }
      final start = match.start > 12 ? match.start - 12 : 0;
      final label = remaining.substring(start, match.start);
      final score = RegExp(r'支付时间|交易时间|付款时间').hasMatch(label)
          ? 30
          : RegExp(r'下单时间|订单时间').hasMatch(label)
          ? 15
          : RegExp(r'乘车日期|场次时间|有效期|入住日期').hasMatch(label)
          ? -20
          : 0;
      absoluteDates.add((match: match, value: candidate, score: score));
    }
    if (absoluteDates.isNotEmpty) {
      absoluteDates.sort((a, b) => b.score.compareTo(a.score));
      date = absoluteDates.first.value;
      explicit = true;
      description = '绝对日期';
      remaining = remaining.replaceAll(_absoluteDatePattern, ' ');
    }

    final monthToken = [
      '这个月初',
      '本月初',
      '这个月底',
      '本月底',
    ].where(remaining.contains).firstOrNull;
    if (!explicit && monthToken != null) {
      explicit = true;
      final isEnd = monthToken.contains('底');
      date = isEnd
          ? DateTime(now.year, now.month + 1, 0)
          : DateTime(now.year, now.month, 1);
      hour = isEnd ? 20 : 9;
      minute = 0;
      description = isEnd ? '月底按本月最后一天 20:00 解析' : '月初按本月 1 日 09:00 解析';
      remaining = remaining.replaceFirst(monthToken, ' ');
    } else if (!explicit) {
      final week = _weekPattern.firstMatch(remaining);
      if (week != null) {
        explicit = true;
        final monday = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(Duration(days: now.weekday - DateTime.monday));
        final targetWeekday = _weekday(week.group(2)!);
        final weekOffset = week.group(1) == '上周' ? -7 : 0;
        date = monday.add(Duration(days: weekOffset + targetWeekday - 1));
        description = '${week.group(1)}${week.group(2)}';
        remaining = remaining.replaceRange(week.start, week.end, ' ');
      } else {
        final relative = [
          '前天',
          '昨晚',
          '昨天',
          '今早',
          '今晚',
          '今天',
          '明天',
        ].where(remaining.contains).firstOrNull;
        if (relative != null) {
          explicit = true;
          final dayOffset = switch (relative) {
            '前天' => -2,
            '昨晚' || '昨天' => -1,
            '明天' => 1,
            _ => 0,
          };
          date = date.add(Duration(days: dayOffset));
          description = relative;
          remaining = remaining.replaceFirst(relative, ' ');
          if (relative == '今早') {
            hour = 8;
            minute = 0;
          } else if (relative == '昨晚' || relative == '今晚') {
            hour = 20;
            minute = 0;
          }
        }
      }
    }

    String? daypart;
    for (final token in ['凌晨', '今天早上', '早上', '上午', '中午', '下午', '晚上']) {
      if (remaining.contains(token)) {
        daypart = token;
        break;
      }
    }
    if (daypart != null) {
      explicit = true;
      hour = switch (daypart) {
        '凌晨' => 2,
        '今天早上' || '早上' => 8,
        '上午' => 9,
        '中午' => 12,
        '下午' => 15,
        _ => 20,
      };
      minute = 0;
      description = description == null ? daypart : '$description$daypart';
      remaining = remaining.replaceFirst(daypart, ' ');
    } else {
      final mealDaypart = [
        '早餐',
        '早点',
        '早饭',
        '午餐',
        '午饭',
        '晚餐',
        '晚饭',
        '夜宵',
      ].where(remaining.contains).firstOrNull;
      if (mealDaypart != null) {
        explicit = true;
        hour = switch (mealDaypart) {
          '早餐' || '早点' || '早饭' => 8,
          '午餐' || '午饭' => 12,
          '晚餐' || '晚饭' => 20,
          _ => 22,
        };
        minute = 0;
        description = description == null
            ? mealDaypart
            : '$description$mealDaypart';
      }
    }

    final clock = _clockPattern.firstMatch(remaining);
    if (clock != null) {
      explicit = true;
      hour = int.parse(clock.group(1)!);
      minute = int.parse(clock.group(2)!);
      hour = _adjustHourForPeriod(hour, input);
      remaining = remaining.replaceRange(clock.start, clock.end, ' ');
    } else {
      final spoken = _hourPattern.firstMatch(remaining);
      if (spoken != null) {
        final parsedHour = _chineseNumber(spoken.group(1)!);
        final parsedMinute = spoken.group(2) != null
            ? 30
            : spoken.group(3) == null
            ? 0
            : _chineseNumber(spoken.group(3)!);
        if (parsedHour >= 0 && parsedHour <= 23 && parsedMinute <= 59) {
          explicit = true;
          hour = parsedHour;
          minute = parsedMinute;
          hour = _adjustHourForPeriod(hour, input);
          remaining = remaining.replaceRange(spoken.start, spoken.end, ' ');
        }
      }
    }

    return ParsedNaturalTime(
      value: DateTime(date.year, date.month, date.day, hour, minute),
      remaining: remaining.replaceAll(RegExp(r'\s+'), ' ').trim(),
      isExplicit: explicit,
      description: description,
      spans: _timeSpans(input),
    );
  }

  static List<RecognizedSpan> _timeSpans(String input) {
    final spans = <RecognizedSpan>[];
    void addMatches(RegExp pattern, String kind) {
      for (final match in pattern.allMatches(input)) {
        spans.add(
          RecognizedSpan(
            range: TextSpanRange(start: match.start, end: match.end),
            kind: kind,
            text: match.group(0)!,
            protected: true,
          ),
        );
      }
    }

    addMatches(_absoluteDatePattern, 'date');
    addMatches(_clockPattern, 'clock');
    addMatches(_hourPattern, 'clock');
    addMatches(_weekPattern, 'relativeDate');
    addMatches(_ambiguousWeekPattern, 'ambiguousWeekday');
    addMatches(
      RegExp(r'这个月初|本月初|这个月底|本月底|前天|昨晚|昨天|今早|今晚|今天|明天'),
      'relativeDate',
    );
    addMatches(RegExp(r'凌晨|今天早上|早上|上午|中午|下午|晚上'), 'daypart');
    spans.sort((a, b) => a.range.start.compareTo(b.range.start));
    return List.unmodifiable(spans);
  }

  static int _weekday(String value) => switch (value) {
    '一' => DateTime.monday,
    '二' => DateTime.tuesday,
    '三' => DateTime.wednesday,
    '四' => DateTime.thursday,
    '五' => DateTime.friday,
    '六' => DateTime.saturday,
    _ => DateTime.sunday,
  };

  static int _adjustHourForPeriod(int hour, String input) {
    if (RegExp(r'下午|晚上|今晚|昨晚').hasMatch(input) && hour < 12) {
      return hour + 12;
    }
    if (input.contains('中午') && hour < 11) return hour + 12;
    if (input.contains('凌晨') && hour == 12) return 0;
    return hour;
  }

  static int _chineseNumber(String value) {
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;
    const digits = {
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.contains('十')) {
      final parts = value.split('十');
      final tens = parts.first.isEmpty ? 1 : digits[parts.first] ?? -1;
      final ones = parts.last.isEmpty ? 0 : digits[parts.last] ?? -1;
      return tens < 0 || ones < 0 ? -1 : tens * 10 + ones;
    }
    if (value.length == 1) return digits[value] ?? -1;
    var result = 0;
    for (final rune in value.runes) {
      final digit = digits[String.fromCharCode(rune)];
      if (digit == null) return -1;
      result = result * 10 + digit;
    }
    return result;
  }
}

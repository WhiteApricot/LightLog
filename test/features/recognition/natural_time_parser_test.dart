import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/natural_time_parser.dart';

void main() {
  const parser = NaturalTimeParser();

  test('parses relative days and documented daypart defaults', () {
    final now = DateTime(2026, 1, 1, 16, 45);
    final cases = {
      '今天早上早餐': DateTime(2026, 1, 1, 8),
      '昨晚电影': DateTime(2025, 12, 31, 20),
      '昨天中午吃饭': DateTime(2025, 12, 31, 12),
      '前天早上食堂': DateTime(2025, 12, 30, 8),
      '明天下午咖啡': DateTime(2026, 1, 2, 15),
      '凌晨打车': DateTime(2026, 1, 1, 2),
    };
    for (final entry in cases.entries) {
      expect(
        parser.parse(entry.key, now).value,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('parses current and previous weekdays across month and year', () {
    final now = DateTime(2026, 1, 1, 10, 20); // Thursday

    expect(parser.parse('本周一午餐', now).value, DateTime(2025, 12, 29, 12));
    expect(parser.parse('本周日午餐', now).value, DateTime(2026, 1, 4, 12));
    expect(parser.parse('上周五中午麦当劳', now).value, DateTime(2025, 12, 26, 12));
    expect(parser.parse('今天午饭', now).value, DateTime(2026, 1, 1, 12));
    expect(parser.parse('昨天晚饭', now).value, DateTime(2025, 12, 31, 20));
  });

  test('month start and end have stable documented defaults', () {
    final now = DateTime(2024, 2, 15, 13, 27);

    expect(parser.parse('这个月初房租', now).value, DateTime(2024, 2, 1, 9));
    expect(parser.parse('这个月底房租', now).value, DateTime(2024, 2, 29, 20));
  });

  test('explicit clocks override daypart defaults', () {
    final now = DateTime(2026, 10, 4, 12, 30);

    expect(
      parser.parse('昨晚 21:35 电影', now).value,
      DateTime(2026, 10, 3, 21, 35),
    );
    expect(parser.parse('今天18点晚餐', now).value, DateTime(2026, 10, 4, 18));
    expect(parser.parse('晚上八点半汉堡', now).value, DateTime(2026, 10, 4, 20, 30));
    expect(
      parser.parse('今晚 8:30 汉堡', now).value,
      DateTime(2026, 10, 4, 20, 30),
    );
    expect(parser.parse('上午十点咖啡', now).value, DateTime(2026, 10, 4, 10));
  });

  test('parses supported absolute date forms', () {
    final now = DateTime(2026, 10, 4, 12, 30);
    final cases = {
      '10月1日 午餐': DateTime(2026, 10, 1, 12),
      '10月1号 午餐': DateTime(2026, 10, 1, 12),
      '2026年9月30日 午餐': DateTime(2026, 9, 30, 12),
      '2026-10-03 午餐': DateTime(2026, 10, 3, 12),
      '2026/10/03 午餐': DateTime(2026, 10, 3, 12),
      '2026.10.03 午餐': DateTime(2026, 10, 3, 12),
    };
    for (final entry in cases.entries) {
      expect(
        parser.parse(entry.key, now).value,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test('transaction time wins over lower-priority business dates', () {
    final now = DateTime(2026, 10, 4, 12, 30);
    final result = parser.parse('乘车日期 2026-10-03 支付时间 2026-10-01 18:20', now);
    expect(result.value, DateTime(2026, 10, 1, 18, 20));
  });
}

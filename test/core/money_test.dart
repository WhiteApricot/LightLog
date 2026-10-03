import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/core/money.dart';

void main() {
  group('MoneyParser', () {
    test('parses yuan input into integer minor units', () {
      expect(MoneyParser.parseCnyMinor('15'), 1500);
      expect(MoneyParser.parseCnyMinor('15.6'), 1560);
      expect(MoneyParser.parseCnyMinor('15.06'), 1506);
    });

    test('rejects zero, negatives and excessive decimal places', () {
      expect(MoneyParser.parseCnyMinor('0'), isNull);
      expect(MoneyParser.parseCnyMinor('-1'), isNull);
      expect(MoneyParser.parseCnyMinor('1.001'), isNull);
      expect(MoneyParser.parseCnyMinor('1e2'), isNull);
    });

    test('formats integer minor units without floating point', () {
      expect(MoneyParser.formatCnyMinor(1506), '¥15.06');
      expect(MoneyParser.editableCny(1500), '15');
    });
  });
}

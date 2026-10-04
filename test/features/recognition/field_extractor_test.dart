import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

import 'recognition_test_fixture.dart';

void main() {
  group('protected numeric spans and amount scoring', () {
    final cases = <String, int>{
      '速度与激情8 20': 2000,
      '复仇者联盟4 35': 3500,
      '7-Eleven 15': 1500,
      '12306 553': 55300,
      '85度C 18': 1800,
      '2号线地铁 4': 400,
      '电影票2张80': 8000,
      '3个包子 6': 600,
      'iPhone 17 Pro Max 手机壳 49.9': 4990,
      'RTX 5090 15999': 1599900,
      '会员12个月 128': 12800,
      '三点五寸硬盘盒 39.9': 3990,
      '二十五元 早餐': 2500,
      '麦 当 劳 2 5 . 0 0': 2500,
      '前天赶时间打车花了18块6': 1860,
      '订单号2026100312345678 麦当劳 26.5': 2650,
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(
          recognizeForTest(entry.key).draft.amountMinor,
          entry.value,
          reason: entry.key,
        );
      });
    }
  });

  test('actual paid field outranks list price and discount', () {
    final result = recognizeForTest('原价 42 优惠 5 实付 37 麦当劳');
    expect(result.draft.amountMinor, 3700);
  });

  test('OCR field labels outrank identifiers, discounts and timestamps', () {
    final result = recognizeForTest(
      '支付宝 交易成功 商家：瑞幸咖啡 商品金额21.00 优惠5.00 '
      '付款金额16.00 付款时间2026-10-04 08:42 订单号202610040842991234',
    );
    expect(result.draft.amountMinor, 1600);
  });

  test('zero and invalid precision are not accepted as transaction amount', () {
    expect(
      recognizeForTest('商品 0 元').issueCodes,
      contains(RecognitionIssueCode.amountUnrecognized),
    );
    expect(recognizeForTest('商品 25.999 元').draft.amountMinor, isNot(2599));
  });

  test('failed, cancelled and non-transaction states are rejected', () {
    final cases = <String, TransactionStatus>{
      '支付失败 余额不足 麦当劳 26': TransactionStatus.failed,
      '订单已取消 麦当劳 26': TransactionStatus.cancelled,
      '银行卡余额 2600': TransactionStatus.nonTransaction,
    };
    for (final entry in cases.entries) {
      final result = recognizeForTest(entry.key);
      expect(result.status, entry.value);
      expect(result.resultStatus, RecognitionResultStatus.rejected);
    }
  });

  test('two transaction blocks are never merged', () {
    final result = recognizeForTest('支付成功 麦当劳 实付26 支付成功 星巴克 实付20');
    expect(result.multipleTransactionsDetected, isTrue);
    expect(result.confirmationLevel, ConfirmationLevel.blocked);
    expect(result.canQuickConfirm, isFalse);
  });
}

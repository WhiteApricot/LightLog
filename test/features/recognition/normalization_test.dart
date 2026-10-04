import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/domain/normalization.dart';

void main() {
  const normalizer = RecognitionNormalizer();

  test('preserves raw input while normalizing characters and safe noise', () {
    const raw = '  微信支付　星巴克（国贸店） 订单号：ABC123456 ２８．５  ';
    final result = normalizer.normalize(raw);

    expect(result.rawText, raw);
    expect(result.displayText, '微信支付 星巴克(国贸店) 订单号:ABC123456 28.5');
    expect(result.normalizedText, '微信支付 星巴克(国贸店) 订单号:abc123456 28.5');
    expect(result.normalizedContent, '星巴克(国贸店) 28.5');
    expect(result.normalizedMerchant, '星巴克 28.5');
  });

  test('removes only trailing company suffix and store number', () {
    final company = normalizer.normalize('瑞幸咖啡有限公司');
    final store = normalizer.normalize('瑞幸咖啡 #1024店');

    expect(company.normalizedMerchant, '瑞幸咖啡');
    expect(store.normalizedMerchant, '瑞幸咖啡');
    expect(normalizer.normalize('有限公司旁咖啡').normalizedMerchant, '有限公司旁咖啡');
  });
}

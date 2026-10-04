class NormalizedRecognitionText {
  const NormalizedRecognitionText({
    required this.rawText,
    required this.normalizedText,
    required this.normalizedContent,
    required this.normalizedMerchant,
  });

  final String rawText;
  final String normalizedText;
  final String normalizedContent;
  final String normalizedMerchant;
}

class RecognitionNormalizer {
  const RecognitionNormalizer();

  static final RegExp _platformNoise = RegExp(
    r'(?:微信支付|支付宝|财付通|银联商务|云闪付|付款成功|支付成功|收款方|商户名)\s*[:：]?',
    caseSensitive: false,
  );
  static final RegExp _orderNoise = RegExp(
    r'(?:订单号|交易号|商户单号)\s*[:：]?\s*[a-z0-9_-]{6,}',
    caseSensitive: false,
  );
  static final RegExp _addressParentheses = RegExp(
    r'[（(][^（）()]{0,30}(?:路|街|区|县|市|店|层|广场|中心)[^（）()]{0,20}[）)]',
  );
  static final RegExp _storeSuffix = RegExp(
    r'(?:[-—·\s]*(?:#?\d{2,6}号?店|[（(][^（）()]{0,20}店[）)]))$',
    caseSensitive: false,
  );
  static final RegExp _companySuffix = RegExp(r'(?:有限责任公司|股份有限公司|有限公司)$');

  NormalizedRecognitionText normalize(String input) {
    final normalized = normalizeCharacters(input);
    var content = normalized
        .replaceAll(_orderNoise, ' ')
        .replaceAll(_platformNoise, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    var merchant = content
        .replaceAll(_addressParentheses, ' ')
        .replaceAll(_storeSuffix, ' ')
        .replaceAll(_companySuffix, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (merchant.isEmpty) merchant = content;
    return NormalizedRecognitionText(
      rawText: input,
      normalizedText: normalized,
      normalizedContent: content,
      normalizedMerchant: merchant,
    );
  }

  static String normalizeCharacters(String input) {
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
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[，、；]'), ',')
        .replaceAll(RegExp(r'[。！]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String indexKey(String value) =>
      normalizeCharacters(value)
          .replaceAll(RegExp(r'[\s,.:：·_\-/\\]'), '')
          .trim();
}

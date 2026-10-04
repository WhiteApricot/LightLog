class NormalizedRecognitionText {
  const NormalizedRecognitionText({
    required this.rawText,
    required this.displayText,
    required this.matchingText,
    required this.normalizedContent,
    required this.normalizedMerchant,
  });

  final String rawText;
  final String displayText;
  final String matchingText;
  final String normalizedContent;
  final String normalizedMerchant;

  String get normalizedText => matchingText;
}

class RecognitionNormalizer {
  const RecognitionNormalizer();

  static final _platformLabels = RegExp(
    r'(?:微信支付|支付宝|财付通|银联商务|云闪付|付款成功|支付成功|收款方|商户名)\s*[:：]?',
    caseSensitive: false,
  );
  static final _orderField = RegExp(
    r'(?:订单号|交易号|商户单号|流水号)\s*[:：]?\s*[a-z0-9_-]{6,}',
    caseSensitive: false,
  );
  static final _addressParentheses = RegExp(
    r'[（(][^（）()]{0,30}(?:路|街|区|县|市|店|层|广场|中心)[^（）()]{0,20}[）)]',
  );
  static final _storeSuffix = RegExp(
    r'(?:[-—·\s]*(?:#?\d{2,6}号?店|[（(][^（）()]{0,20}店[）)]))$',
    caseSensitive: false,
  );
  static final _companySuffix = RegExp(r'(?:有限责任公司|股份有限公司|有限公司)$');

  NormalizedRecognitionText normalize(String input) {
    final display = normalizeDisplay(input);
    final matching = display.toLowerCase();
    var content = matching
        .replaceAll(_orderField, ' ')
        .replaceAll(_platformLabels, ' ')
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
      displayText: display,
      matchingText: matching,
      normalizedContent: content,
      normalizedMerchant: merchant,
    );
  }

  static String normalizeDisplay(String input) {
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
        .replaceAll(RegExp(r'[，、；]'), ',')
        .replaceAll(RegExp(r'[。！]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizeCharacters(String input) =>
      normalizeDisplay(input).toLowerCase();

  static String indexKey(String value) =>
      normalizeCharacters(value)
          .replaceAll(RegExp(r"[\s,.:：·_\-/\\'’]"), '')
          .trim();
}

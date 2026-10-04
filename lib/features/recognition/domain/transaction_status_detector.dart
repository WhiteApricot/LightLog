import 'recognition_models.dart';

class TransactionStatusDecision {
  const TransactionStatusDecision({
    required this.status,
    required this.spans,
    required this.multipleTransactionsDetected,
  });

  final TransactionStatus status;
  final List<RecognizedSpan> spans;
  final bool multipleTransactionsDetected;
}

class TransactionStatusDetector {
  const TransactionStatusDetector();

  TransactionStatusDecision detect(String text) {
    final patterns = <(TransactionStatus, RegExp)>[
      (TransactionStatus.failed, RegExp(r'支付失败|交易失败|付款失败|余额不足')),
      (TransactionStatus.cancelled, RegExp(r'订单已取消|交易取消|已关闭|已撤销')),
      (TransactionStatus.refund, RegExp(r'退款成功|已退款|退款到账')),
      (
        TransactionStatus.nonTransaction,
        RegExp(r'银行卡余额|账户余额|优惠券页面|卡券中心|验证码|账单首页'),
      ),
      (TransactionStatus.success, RegExp(r'支付成功|交易成功|付款成功|收款成功')),
    ];
    var status = TransactionStatus.unknown;
    final spans = <RecognizedSpan>[];
    for (final (candidateStatus, pattern) in patterns) {
      final matches = pattern.allMatches(text).toList();
      if (matches.isEmpty) continue;
      if (status == TransactionStatus.unknown) status = candidateStatus;
      for (final match in matches) {
        spans.add(
          RecognizedSpan(
            range: TextSpanRange(start: match.start, end: match.end),
            kind: 'status',
            text: match.group(0)!,
          ),
        );
      }
    }
    final successCount = RegExp(r'支付成功|交易成功|付款成功|收款成功').allMatches(text).length;
    final strongAmountCount = RegExp(r'实付\s*[:：]?\s*[￥¥]?\s*\d+(?:\.\d{1,2})?')
        .allMatches(text)
        .length;
    return TransactionStatusDecision(
      status: status,
      spans: List.unmodifiable(spans),
      multipleTransactionsDetected: successCount >= 2 || strongAmountCount >= 2,
    );
  }
}

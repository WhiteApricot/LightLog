import '../../../core/money.dart';
import 'recognition_models.dart';

class AmountExtractionResult {
  const AmountExtractionResult({
    required this.candidates,
    required this.selected,
    required this.ambiguous,
  });

  final List<AmountCandidate> candidates;
  final AmountCandidate? selected;
  final bool ambiguous;
}

class AmountExtractor {
  const AmountExtractor();

  static final _number = RegExp(
    r'(?<![\d.])([￥¥]?\s*[+-]?(?:\d(?:\s+\d)+\s*\.\s*\d(?:\s+\d)*|\d+(?:\.\d{1,2})?))(?:\s*(元|块))?(?![\d.])',
    caseSensitive: false,
  );
  static final _colloquial = RegExp(r'(?<!\d)(\d+)块(\d{1,2})(?!\d)');
  static final _chineseAmount = RegExp(
    r'(?<![零〇一二两三四五六七八九十百千万])([零〇一二两三四五六七八九十百千万]+)元(?![零〇一二两三四五六七八九十百千万])',
  );
  static final _strong = RegExp(
    r'(?:实付|支付金额|付款金额|实际支付|收款金额|花了|消费)\s*[:：]?\s*$',
  );
  static final _medium = RegExp(r'(?:应付|应收|到账|收入)\s*[:：]?\s*$');
  static final _weak = RegExp(r'(?:订单金额|商品金额|总金额|合计|金额|票价)\s*[:：]?\s*$');
  static final _negative = RegExp(
    r'(?:优惠(?:券)?|原价(?:其实是)?|余额|面额|退款金额|订单号|交易号|流水号|商户单号|手机号|车次|里程|时长|数量|验证码)\s*[:：]?\s*$',
  );

  AmountExtractionResult extract(
    String text, {
    List<RecognizedSpan> protectedSpans = const [],
  }) {
    final candidates = <AmountCandidate>[];
    final occupied = <TextSpanRange>[];
    for (final match in _colloquial.allMatches(text)) {
      final whole = match.group(1)!;
      final fraction = match.group(2)!;
      final minor = MoneyParser.parseCnyMinor('$whole.$fraction');
      candidates.add(
        AmountCandidate(
          raw: match.group(0)!,
          amountMinor: minor,
          start: match.start,
          end: match.end,
          score: 112,
          role: NumericRole.amount,
          reason: '中文口语金额',
          features: const ['colloquialAmount', 'currencyUnit'],
        ),
      );
      occupied.add(TextSpanRange(start: match.start, end: match.end));
    }
    for (final match in _chineseAmount.allMatches(text)) {
      final whole = _parseChineseInteger(match.group(1)!);
      if (whole == null || whole <= 0) continue;
      candidates.add(
        AmountCandidate(
          raw: match.group(0)!,
          amountMinor: whole * 100,
          start: match.start,
          end: match.end,
          score: 112,
          role: NumericRole.amount,
          reason: '中文金额',
          features: const ['chineseAmount', 'currencyUnit'],
        ),
      );
      occupied.add(TextSpanRange(start: match.start, end: match.end));
    }
    final matches = _number.allMatches(text).toList();
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final range = TextSpanRange(start: match.start, end: match.end);
      if (occupied.any(range.overlaps)) continue;
      final token = match.group(1)!.replaceAll(RegExp(r'[￥¥\s]'), '');
      final unsigned = token.replaceFirst(RegExp(r'^[+-]'), '');
      final amount = MoneyParser.parseCnyMinor(unsigned);
      final before = text.substring(0, match.start);
      final after = text.substring(match.end);
      final left = before.length > 18
          ? before.substring(before.length - 18)
          : before;
      final right = after.length > 12 ? after.substring(0, 12) : after;
      var score = 48.0;
      var role = NumericRole.amount;
      var reason = '独立数字';
      final features = <String>[];
      var hasPositiveLabel = false;
      final protectedBy = protectedSpans
          .where((span) => span.protected && span.range.overlaps(range))
          .firstOrNull;
      if (protectedBy != null) {
        score -= 150;
        role = protectedBy.kind == 'date' || protectedBy.kind == 'clock'
            ? NumericRole.dateTime
            : NumericRole.titleNumber;
        reason = '受保护的${protectedBy.kind}数字';
        features.add('protected:${protectedBy.kind}');
      } else if (_strong.hasMatch(left)) {
        score += 70;
        reason = '实付或交易金额字段';
        features.add('strongLabel');
        hasPositiveLabel = true;
      } else if (_medium.hasMatch(left)) {
        score += 45;
        reason = '应付或收入字段';
        features.add('mediumLabel');
        hasPositiveLabel = true;
      } else if (_weak.hasMatch(left)) {
        score += 28;
        reason = '金额字段';
        features.add('weakLabel');
        hasPositiveLabel = true;
      }
      if (protectedBy == null &&
          !hasPositiveLabel &&
          _negative.hasMatch(left)) {
        score -= 105;
        role = RegExp(r'订单号|交易号|流水号|商户单号').hasMatch(left)
            ? NumericRole.orderId
            : NumericRole.other;
        reason = '非支付金额字段';
        features.add('negativeLabel');
      }
      if (unsigned.length >= 8 && !unsigned.contains('.')) {
        score -= 120;
        role = RegExp(r'1[3-9]\d{9}$').hasMatch(unsigned)
            ? NumericRole.phoneNumber
            : NumericRole.orderId;
        reason = '长编号';
        features.add('longIdentifier');
      } else if (RegExp(r'^\s*(个|件|张|份|杯|瓶|盒|寸|月|年|次|公里|分钟|小时|号线)')
          .hasMatch(right)) {
        score -= 85;
        role = RegExp(r'^\s*(公里|分钟|小时|月|年|次|号线)').hasMatch(right)
            ? NumericRole.distanceDuration
            : right.trimLeft().startsWith('寸')
            ? NumericRole.modelVersion
            : NumericRole.quantity;
        reason = '数量或时长';
        features.add('unitRole');
      } else if (RegExp(r'^\s*度c', caseSensitive: false).hasMatch(right)) {
        score -= 80;
        role = NumericRole.titleNumber;
        reason = '品牌名称内数字';
      } else if (index < matches.length - 1 &&
          RegExp(
            r'(iphone|ipad|rtx|gtx|mate|小米|荣耀|型号)\s*$',
            caseSensitive: false,
          ).hasMatch(left)) {
        score -= 80;
        role = NumericRole.modelVersion;
        reason = '型号数字';
        features.add('modelPrefix');
      } else if (!hasPositiveLabel &&
          index < matches.length - 1 &&
          match.start > 0 &&
          !RegExp(r'[\s:：￥¥]').hasMatch(text[match.start - 1])) {
        score -= 60;
        role = NumericRole.titleNumber;
        reason = '标题内数字';
      }
      if (token.contains('.')) {
        score += 14;
        features.add('decimal');
      }
      if (match.group(2) != null || match.group(1)!.contains(RegExp(r'[￥¥]'))) {
        score += 24;
        features.add('currencyUnit');
      }
      if (index == matches.length - 1) {
        score += 12;
        features.add('trailing');
      }
      candidates.add(
        AmountCandidate(
          raw: token,
          amountMinor: amount,
          start: match.start,
          end: match.end,
          score: score,
          role: role,
          reason: reason,
          features: List.unmodifiable(features),
        ),
      );
    }
    final viable =
        candidates
            .where(
              (item) =>
                  item.role == NumericRole.amount && item.amountMinor != null,
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    final ambiguous =
        viable.length > 1 &&
        viable.first.amountMinor != viable[1].amountMinor &&
        viable.first.score - viable[1].score < 24;
    return AmountExtractionResult(
      candidates: List.unmodifiable(candidates),
      selected: viable.isEmpty || ambiguous ? null : viable.first,
      ambiguous: ambiguous,
    );
  }

  static int? _parseChineseInteger(String input) {
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
    const units = {'十': 10, '百': 100, '千': 1000, '万': 10000};
    var total = 0;
    var section = 0;
    var number = 0;
    for (final rune in input.runes) {
      final character = String.fromCharCode(rune);
      final digit = digits[character];
      if (digit != null) {
        number = digit;
        continue;
      }
      final unit = units[character];
      if (unit == null) return null;
      if (unit == 10000) {
        section = (section + number) * unit;
        total += section;
        section = 0;
      } else {
        section += (number == 0 ? 1 : number) * unit;
      }
      number = 0;
    }
    return total + section + number;
  }
}

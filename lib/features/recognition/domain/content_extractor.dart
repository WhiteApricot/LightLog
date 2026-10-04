import 'knowledge_models.dart';
import 'recognition_models.dart';

class ContentCandidate {
  const ContentCandidate({
    required this.displayText,
    required this.matchingText,
    required this.confidence,
    this.role = EvidenceRole.context,
    this.span,
  });

  final String displayText;
  final String matchingText;
  final double confidence;
  final EvidenceRole role;
  final TextSpanRange? span;
}

class ContentExtractor {
  const ContentExtractor();

  static final _labelValue = RegExp(
    r'(?:收款方|商户名?|商家|商品(?:名称|详情)?|订单详情)\s*[:：]\s*(.+?)(?=\s+(?:商品|订单金额|商品小计|配送费|服务费|票价|原价|优惠|红包|实付|支付金额|付款金额|交易时间|支付时间|退款时间|订单号|交易号|商户单号)\s*[:：]?|$)',
    caseSensitive: false,
  );

  ContentCandidate? extract({
    required String displayText,
    required String matchingText,
    required List<RecognizedSpan> removableSpans,
    required List<AmountCandidate> amountCandidates,
    required AmountCandidate? selectedAmount,
    required List<EntityMatch> entityMatches,
    required List<RecognitionEvidence> lexiconEvidence,
  }) {
    final labeled = _labelValue.firstMatch(displayText);
    if (labeled != null) {
      final value = _clean(labeled.group(1)!);
      if (value.isNotEmpty) {
        final start =
            labeled.start + labeled.group(0)!.indexOf(labeled.group(1)!);
        final end = start + labeled.group(1)!.length;
        final labeledMerchant = entityMatches
            .where(
              (match) =>
                  match.alias.entity.kind == EntityKind.merchant &&
                  match.range.start >= start &&
                  match.range.end <= end,
            )
            .firstOrNull;
        if (labeledMerchant != null) return _entityCandidate(labeledMerchant);
        return ContentCandidate(
          displayText: value,
          matchingText: value.toLowerCase(),
          confidence: 0.96,
          role: EvidenceRole.merchantType,
          span: TextSpanRange(start: start, end: end),
        );
      }
    }

    final chars = displayText.split('');
    void erase(TextSpanRange range) {
      final start = range.start.clamp(0, chars.length);
      final end = range.end.clamp(start, chars.length);
      for (var index = start; index < end; index++) {
        chars[index] = ' ';
      }
    }

    for (final span in removableSpans) {
      if (span.kind != 'entity') erase(span.range);
    }
    if (selectedAmount != null) erase(selectedAmount.range);
    for (final candidate in amountCandidates) {
      if (candidate == selectedAmount) continue;
      if (candidate.role == NumericRole.orderId ||
          candidate.role == NumericRole.phoneNumber) {
        erase(candidate.range);
      }
    }
    var content = chars.join();
    final platformMatches = entityMatches.where(
      (match) => match.alias.entity.kind == EntityKind.platform,
    );
    for (final platform in platformMatches) {
      final current = content.substring(
        platform.range.start.clamp(0, content.length),
        platform.range.end.clamp(0, content.length),
      );
      content = content.replaceRange(
        platform.range.start.clamp(0, content.length),
        platform.range.end.clamp(0, content.length),
        ' ' * current.length,
      );
    }
    content = _clean(content);

    final specificLexicon = lexiconEvidence.any(
      (item) =>
          !item.negative &&
          item.specificity == EvidenceSpecificity.specific &&
          (item.role == EvidenceRole.product ||
              item.role == EvidenceRole.action ||
              item.role == EvidenceRole.service),
    );
    final merchant = entityMatches
        .where(
          (match) =>
              match.alias.entity.kind == EntityKind.merchant &&
              match.alias.entity.breadth == EntityBreadth.specific,
        )
        .firstOrNull;
    final contentEntity = entityMatches.firstOrNull;
    final concreteEntity = entityMatches
        .where((match) => match.alias.entity.kind != EntityKind.platform)
        .firstOrNull;
    if (contentEntity != null &&
        RegExp(r'^(?:早餐|早饭|午餐|午饭|晚餐|晚饭|夜宵)').hasMatch(content)) {
      return _entityCandidate(contentEntity);
    }
    final onlyBroadServiceAfterEntity =
        contentEntity != null &&
        RegExp(r'^(?:会员|订阅|套餐)$').hasMatch(
          content
              .replaceFirst(
                displayText.substring(
                  contentEntity.range.start,
                  contentEntity.range.end,
                ),
                '',
              )
              .trim(),
        );
    if (onlyBroadServiceAfterEntity) {
      return _entityCandidate(contentEntity);
    }
    if (!specificLexicon &&
        merchant != null &&
        content.length > merchant.range.length + 8) {
      return _entityCandidate(merchant);
    }
    if (content.runes.length > 12 &&
        concreteEntity != null &&
        concreteEntity.alias.entity.breadth == EntityBreadth.specific) {
      return _entityCandidate(concreteEntity);
    }
    final narrativeMerchant = RegExp(
      r'(?:去|在)([\u4e00-\u9fffA-Za-z0-9·]{2,20}?)(?:买|吃|消费|看|住)',
    ).firstMatch(content);
    if (narrativeMerchant != null) {
      final value = narrativeMerchant
          .group(1)!
          .replaceFirst(RegExp(r'^(?:学校|公司|单位|小区|商场)'), '');
      return ContentCandidate(
        displayText: value,
        matchingText: value.toLowerCase(),
        confidence: 0.86,
        role: EvidenceRole.merchantType,
      );
    }
    final narrativeLexicon =
        lexiconEvidence
            .where(
              (item) =>
                  !item.negative &&
                  item.span != null &&
                  item.specificity == EvidenceSpecificity.specific &&
                  (item.role == EvidenceRole.product ||
                      item.role == EvidenceRole.service ||
                      item.role == EvidenceRole.action),
            )
            .toList()
          ..sort((a, b) => b.span!.length.compareTo(a.span!.length));
    if (content.runes.length > 12 &&
        RegExp(r'买|吃|花|给|一共|消费|支付').hasMatch(content) &&
        narrativeLexicon.isNotEmpty) {
      final evidence = narrativeLexicon.first;
      final value = displayText.substring(
        evidence.span!.start,
        evidence.span!.end,
      );
      return ContentCandidate(
        displayText: value,
        matchingText: value.toLowerCase(),
        confidence: 0.90,
        role: evidence.role,
        span: evidence.span,
      );
    }
    if (content.isEmpty && entityMatches.isNotEmpty) {
      return _entityCandidate(entityMatches.first);
    }
    if (content.isEmpty) return null;
    return ContentCandidate(
      displayText: content,
      matchingText: content.toLowerCase(),
      confidence: entityMatches.isNotEmpty || specificLexicon ? 0.9 : 0.72,
      role: specificLexicon ? EvidenceRole.product : EvidenceRole.context,
    );
  }

  static String _clean(String input) => input
      .replaceAll(RegExp(r'支付成功|交易成功|付款成功|收款成功'), ' ')
      .replaceAll(
        RegExp(
          r'(?:订单号|交易号|商户单号|流水号)\s*[:：]?\s*[a-z0-9_-]{6,}',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'(?:订单号|交易号|商户单号|流水号)\s*[:：]?'), ' ')
      .replaceAll(RegExp(r'实付|支付金额|付款金额|实际支付|应付|订单金额|商品金额|总金额|合计'), ' ')
      .replaceAll(
        RegExp(r'^\s*(?:(?:今天|昨天|前天|昨晚|今早|今晚|明天)|(?:早上|上午|中午|下午|晚上))+\s*'),
        ' ',
      )
      .replaceAll(RegExp(r'(?:\d+\s*)?(?:个|件|张|份|杯|瓶|盒)(?=\s|$)'), ' ')
      .replaceAll(
        RegExp(
          r'(?:[零一二两三四五六七八九十\d]+\s*)(?:个|件|张|份|杯|瓶|盒|袋)(?=[\u4e00-\u9fffA-Za-z])',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'(?:^|\s)支付(?=\s|$)'), ' ')
      .replaceAll(RegExp(r'[￥¥]'), ' ')
      .replaceAll(RegExp(r'^[\s,，。;；:：]+|[\s,，。;；:：]+$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static ContentCandidate _entityCandidate(EntityMatch match) {
    final value = match.alias.displayAlias;
    return ContentCandidate(
      displayText: value,
      matchingText: match.alias.normalizedAlias,
      confidence: 0.94,
      role: switch (match.alias.entity.kind) {
        EntityKind.merchant => EvidenceRole.merchantType,
        EntityKind.platform => EvidenceRole.platform,
        EntityKind.service => EvidenceRole.service,
        _ => EvidenceRole.product,
      },
      span: match.range,
    );
  }
}

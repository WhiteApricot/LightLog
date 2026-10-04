import 'knowledge_models.dart';
import 'normalization.dart';
import 'recognition_models.dart';

class EntityMatcher {
  const EntityMatcher(this.catalog);

  final KnowledgeCatalog catalog;

  List<EntityMatch> match(String matchingText) {
    final compact = _CompactText.from(matchingText);
    if (compact.value.isEmpty) return const [];
    final matches = <EntityMatch>[];
    final seen = <String>{};
    final candidateAliases = <EntityAlias>{};
    for (final rune in compact.value.runes.toSet()) {
      candidateAliases.addAll(
        catalog.aliasesByFirstCharacter[String.fromCharCode(rune)] ?? const [],
      );
    }
    for (final alias in candidateAliases) {
      final needle = alias.normalizedAlias;
      if (needle.isEmpty) continue;
      var start = compact.value.indexOf(needle);
      while (start >= 0) {
        final exact = start == 0 && needle.length == compact.value.length;
        final sourceRange = compact.sourceRange(start, start + needle.length);
        final exactToken = _hasTokenBoundaries(matchingText, sourceRange);
        if (exact ||
            exactToken ||
            _hasAllowedAttachedSuffix(matchingText, sourceRange) ||
            alias.matchPolicy != AliasMatchPolicy.exactOnly) {
          final key =
              '${alias.entity.canonicalName}:$start:${start + needle.length}';
          if (seen.add(key)) {
            matches.add(
              EntityMatch(
                alias: alias,
                range: sourceRange,
                matchType: exact
                    ? 'exact'
                    : exactToken &&
                          alias.matchPolicy == AliasMatchPolicy.exactOnly
                    ? 'exactToken'
                    : 'substring',
                score: (alias.entity.confidence - (exact ? 0 : 0.03)).clamp(
                  0,
                  0.99,
                ),
              ),
            );
          }
        }
        start = compact.value.indexOf(needle, start + 1);
      }
    }
    if (matches.isEmpty && compact.value.runes.length >= 4) {
      EntityAlias? fuzzy;
      final first = String.fromCharCode(compact.value.runes.first);
      for (final alias in catalog.aliasesByFirstCharacter[first] ?? const []) {
        if (alias.matchPolicy != AliasMatchPolicy.fuzzy ||
            alias.normalizedAlias.runes.length < 4 ||
            alias.normalizedAlias.runes.first != compact.value.runes.first) {
          continue;
        }
        if (_distanceAtMostOne(compact.value, alias.normalizedAlias)) {
          if (fuzzy != null && fuzzy.entity != alias.entity) return const [];
          fuzzy = alias;
        }
      }
      if (fuzzy != null) {
        matches.add(
          EntityMatch(
            alias: fuzzy,
            range: TextSpanRange(start: 0, end: matchingText.length),
            matchType: 'fuzzy',
            score: (fuzzy.entity.confidence - 0.12).clamp(0, 0.85),
          ),
        );
      }
    }
    matches.sort((a, b) {
      final specific = _specificity(b.alias.entity).index
          .compareTo(_specificity(a.alias.entity).index);
      if (specific != 0) return specific;
      final length = b.range.length.compareTo(a.range.length);
      return length != 0 ? length : b.score.compareTo(a.score);
    });
    return List.unmodifiable(matches);
  }

  List<RecognitionEvidence> evidence(List<EntityMatch> matches) => [
    for (final match in matches)
      if (match.alias.entity.semanticKey != null)
        RecognitionEvidence(
          field: 'category',
          source: RecognitionEvidenceSource.entityKnowledge,
          semanticKey: match.alias.entity.semanticKey,
          description:
              '实体${match.matchType}匹配“${match.alias.entity.canonicalName}”',
          score: match.score,
          role: _role(match.alias.entity.kind),
          specificity: _specificity(match.alias.entity),
          matchedText: match.alias.displayAlias,
          span: match.range,
          family: 'entity:${match.alias.entity.canonicalName}',
        ),
  ];

  List<RecognizedSpan> protectedNumericSpans(List<EntityMatch> matches) => [
    for (final match in matches)
      if (RegExp(r'\d').hasMatch(match.alias.displayAlias))
        RecognizedSpan(
          range: match.range,
          kind: 'entity',
          text: match.alias.displayAlias,
          protected: true,
          score: match.score,
        ),
  ];

  static EvidenceRole _role(EntityKind kind) => switch (kind) {
    EntityKind.platform => EvidenceRole.platform,
    EntityKind.service => EvidenceRole.service,
    EntityKind.mediaTitle ||
    EntityKind.gameTitle ||
    EntityKind.productBrand => EvidenceRole.product,
    EntityKind.merchant => EvidenceRole.merchantType,
  };

  static EvidenceSpecificity _specificity(EntityKnowledge entity) =>
      entity.kind == EntityKind.merchant ||
          entity.breadth == EntityBreadth.broad
      ? EvidenceSpecificity.broad
      : EvidenceSpecificity.specific;

  static bool _distanceAtMostOne(String left, String right) {
    final a = left.runes.toList();
    final b = right.runes.toList();
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0;
    var j = 0;
    var edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
      } else {
        if (++edits > 1) return false;
        if (a.length > b.length) {
          i++;
        } else if (b.length > a.length) {
          j++;
        } else {
          i++;
          j++;
        }
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }

  static bool _hasTokenBoundaries(String text, TextSpanRange range) {
    bool boundary(String character) =>
        RegExp(r'[\s,，。:：;；/\\()（）￥¥]').hasMatch(character);
    final left = range.start == 0 || boundary(text[range.start - 1]);
    final right = range.end == text.length || boundary(text[range.end]);
    return left && right;
  }

  static bool _hasAllowedAttachedSuffix(String text, TextSpanRange range) {
    if (range.start != 0 || range.end >= text.length) return false;
    final suffix = RecognitionNormalizer.indexKey(text.substring(range.end));
    if (RegExp(r'^[￥¥]?\d+(?:\.\d{1,2})?(?:元|块)?$').hasMatch(suffix)) {
      return true;
    }
    return RegExp(
      r'^(?:会员|套餐|订单)(?:号)?(?:[:：#_-]?[a-z0-9_-]+)?(?:[￥¥]?\d+(?:\.\d{1,2})?(?:元|块)?)?$',
      caseSensitive: false,
    ).hasMatch(suffix);
  }
}

class _CompactText {
  const _CompactText(this.value, this.sourceOffsets);

  factory _CompactText.from(String source) {
    final value = StringBuffer();
    final offsets = <int>[];
    for (var index = 0; index < source.length; index++) {
      final character = source[index];
      if (RegExp(r"[\s,.:：·_\-/\\'’]").hasMatch(character)) continue;
      value.write(character);
      offsets.add(index);
    }
    return _CompactText(value.toString(), offsets);
  }

  final String value;
  final List<int> sourceOffsets;

  TextSpanRange sourceRange(int start, int end) => TextSpanRange(
    start: sourceOffsets[start],
    end: sourceOffsets[end - 1] + 1,
  );
}

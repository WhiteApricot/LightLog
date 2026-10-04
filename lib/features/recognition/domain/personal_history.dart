import 'recognition_models.dart';

class PersonalHistoryMatcher {
  const PersonalHistoryMatcher();

  List<RecognitionEvidence> match({
    required String normalizedContent,
    required List<PersonalHistoryRecord> records,
    required DateTime now,
  }) {
    return [
      for (final record in records)
        if (record.normalizedContent == normalizedContent &&
            record.hitCount > record.correctionCount &&
            record.hitCount >= 2)
          RecognitionEvidence(
            field: 'category',
            source: RecognitionEvidenceSource.personalHistory,
            semanticKey: record.semanticKey,
            description:
                '个人历史命中 ${record.hitCount} 次，纠正 ${record.correctionCount} 次',
            score: _score(record, now),
            role: EvidenceRole.context,
            specificity: EvidenceSpecificity.specific,
            family: 'history:${record.normalizedContent}',
          ),
    ];
  }

  double _score(PersonalHistoryRecord record, DateTime now) {
    final total = record.hitCount + record.correctionCount;
    final correctionRate = total == 0 ? 1.0 : record.correctionCount / total;
    final age = now.millisecondsSinceEpoch - record.lastUsedAt;
    final recentBonus = age <= const Duration(days: 30).inMilliseconds
        ? 0.03
        : 0.0;
    return (0.84 +
            (record.hitCount.clamp(0, 6) * 0.02) -
            (correctionRate * 0.30) +
            recentBonus)
        .clamp(0.55, 0.99);
  }
}

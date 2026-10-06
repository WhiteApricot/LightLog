import 'recognition_models.dart';

class TypeInference {
  const TypeInference();

  static final _income = RegExp(r'收款(?!方)|到账|收入|退回|收益\s*[:：]?\s*[￥¥]?\s*\d');
  static final _expense = RegExp(r'实付|支付|付款(?!方)|消费|花了|购买|买了|缴费|充值');

  TypeDecision withStatisticalDirection(
    TypeDecision preliminary,
    double incomeProbability,
    double threshold,
  ) {
    if (preliminary.type == RecognitionTransactionType.refund ||
        preliminary.hasConflict ||
        (!preliminary.isDefault &&
            preliminary.type != null &&
            preliminary.confidence >= .70)) {
      return preliminary;
    }
    final confidence = incomeProbability >= .5
        ? incomeProbability
        : 1 - incomeProbability;
    if (confidence <= .5 || confidence < threshold) return preliminary;
    return TypeDecision(
      type: incomeProbability >= .5
          ? RecognitionTransactionType.income
          : RecognitionTransactionType.expense,
      confidence: .69,
      evidence: [
        ...preliminary.evidence,
        const RecognitionEvidence(
          field: 'type',
          description: '本地方向模型校正弱方向（需确认）',
          score: .69,
          source: RecognitionEvidenceSource.ngram,
          family: 'statisticalDirection',
        ),
      ],
    );
  }

  TypeDecision inferPreliminary({
    required String matchingText,
    required TransactionStatus status,
    required AmountCandidate? amount,
    required bool hasContent,
  }) {
    final evidence = <RecognitionEvidence>[];
    if (status == TransactionStatus.refund) {
      return TypeDecision(
        type: RecognitionTransactionType.refund,
        confidence: 0.99,
        evidence: const [
          RecognitionEvidence(
            field: 'type',
            description: '交易状态明确为退款',
            score: 0.99,
          ),
        ],
      );
    }
    if (amount?.raw.startsWith('+') ?? false) {
      evidence.add(
        const RecognitionEvidence(
          field: 'type',
          description: '金额带显式正号',
          score: 0.98,
        ),
      );
      return TypeDecision(
        type: RecognitionTransactionType.income,
        confidence: 0.98,
        evidence: evidence,
      );
    }
    if (amount?.raw.startsWith('-') ?? false) {
      evidence.add(
        const RecognitionEvidence(
          field: 'type',
          description: '金额带显式负号',
          score: 0.98,
        ),
      );
      return TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: 0.98,
        evidence: evidence,
      );
    }
    final income = _income.hasMatch(matchingText);
    final expense = _expense.hasMatch(matchingText);
    if (income && expense && RegExp(r'到账|收入|退回').hasMatch(matchingText)) {
      return const TypeDecision(
        type: RecognitionTransactionType.income,
        confidence: 0.94,
        evidence: [
          RecognitionEvidence(
            field: 'type',
            description: '明确入账动作优先于内容中的支出名词',
            score: 0.94,
          ),
        ],
      );
    }
    if (income && expense) {
      return const TypeDecision(
        type: null,
        confidence: 0.45,
        evidence: [],
        hasConflict: true,
      );
    }
    if (income) {
      evidence.add(
        const RecognitionEvidence(
          field: 'type',
          description: '命中明确收入动作或字段',
          score: 0.94,
        ),
      );
      return TypeDecision(
        type: RecognitionTransactionType.income,
        confidence: 0.94,
        evidence: evidence,
      );
    }
    if (expense) {
      evidence.add(
        const RecognitionEvidence(
          field: 'type',
          description: '命中明确支出动作或字段',
          score: 0.94,
        ),
      );
      return TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: 0.94,
        evidence: evidence,
      );
    }
    if (amount != null &&
        hasContent &&
        status != TransactionStatus.nonTransaction) {
      evidence.add(
        const RecognitionEvidence(
          field: 'type',
          description: '金额与消费内容共同提供普通支出证据',
          score: 0.88,
        ),
      );
      return TypeDecision(
        type: RecognitionTransactionType.expense,
        isDefault: true,
        confidence: 0.88,
        evidence: evidence,
      );
    }
    return const TypeDecision(type: null, confidence: 0, evidence: []);
  }

  TypeDecision reconcile(
    TypeDecision preliminary,
    String? semanticKey,
    List<RecognitionEvidence> winningEvidence, {
    double statisticalParentConfidence = 0,
  }) {
    if (preliminary.type == RecognitionTransactionType.refund ||
        semanticKey == null) {
      return preliminary;
    }
    final semanticType = semanticKey.startsWith('income.')
        ? RecognitionTransactionType.income
        : RecognitionTransactionType.expense;
    final support = winningEvidence.where(
      (e) => !e.negative && e.semanticKey == semanticKey,
    );
    final statistical = support.any(
      (e) => e.source == RecognitionEvidenceSource.ngram,
    );
    final strong =
        support.any((e) => e.score >= .70) ||
        (statistical && statisticalParentConfidence >= .85);
    if (!strong) return preliminary;
    if (semanticKey.startsWith('income.refund.')) {
      if (statistical) return preliminary;
      return TypeDecision(
        type: RecognitionTransactionType.refund,
        confidence: .90,
        evidence: [
          ...preliminary.evidence,
          const RecognitionEvidence(
            field: 'type',
            description: '退款语义要求关联原账目',
            score: .90,
          ),
        ],
      );
    }
    if (preliminary.isDefault ||
        (preliminary.type == null && !preliminary.hasConflict)) {
      return TypeDecision(
        type: semanticType,
        confidence: statistical ? .69 : .90,
        evidence: [
          ...preliminary.evidence,
          RecognitionEvidence(
            field: 'type',
            description: '语义证据校正初步账务方向',
            score: statistical ? .69 : .90,
          ),
        ],
      );
    }
    if (preliminary.type != semanticType) {
      return TypeDecision(
        type: preliminary.type,
        confidence: preliminary.confidence,
        evidence: preliminary.evidence,
        hasConflict: true,
      );
    }
    return preliminary;
  }
}

import 'recognition_models.dart';

class TypeInference {
  const TypeInference();

  static final _income = RegExp(
    r'工资|薪资|奖金|津贴|补贴|绩效|报销|稿费|劳务|兼职|私单|接单收入|讲课费|红包收入|收到红包|二手出售|卖旧|卖二手|存款利息|利息到账|分红|租金收入|返现|赔偿|押金退回|收款(?!方)|到账|收入',
  );
  static final _expense = RegExp(
    r'实付|支付|付款|消费|花了|购买|买了|缴费|充值|打车|吃了|订阅|维修|房租|水费|电费|燃气费',
  );

  TypeDecision infer({
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
    if (RegExp(r'给(?:家里|家人|爸妈|父母).{0,4}补贴').hasMatch(matchingText)) {
      return const TypeDecision(
        type: RecognitionTransactionType.expense,
        confidence: 0.94,
        evidence: [
          RecognitionEvidence(
            field: 'type',
            description: '给家人补贴表示支出',
            score: 0.94,
          ),
        ],
      );
    }
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
        confidence: 0.88,
        evidence: evidence,
      );
    }
    return const TypeDecision(type: null, confidence: 0, evidence: []);
  }
}

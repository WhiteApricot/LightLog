import '../../../data/database/database.dart';

enum LedgerTransactionType {
  expense('expense', '支出'),
  income('income', '收入'),
  transfer('transfer', '转账'),
  refund('refund', '退款');

  const LedgerTransactionType(this.value, this.label);
  final String value;
  final String label;

  static LedgerTransactionType fromValue(String value) => values.firstWhere(
    (type) => type.value == value,
    orElse: () => throw ArgumentError.value(value, 'value', '未知账务类型'),
  );
}

class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.categoryId,
    required this.subcategoryId,
    required this.content,
    required this.amountMinor,
    required this.occurredAtLocal,
    required this.timezoneOffsetMinutes,
    required this.accountId,
    this.note,
    this.destinationAccountId,
    this.relatedTransactionId,
  });

  final LedgerTransactionType type;
  final String categoryId;
  final String subcategoryId;
  final String content;
  final String? note;
  final int amountMinor;
  final DateTime occurredAtLocal;
  final int timezoneOffsetMinutes;
  final String accountId;
  final String? destinationAccountId;
  final String? relatedTransactionId;
}

class LedgerEntry {
  const LedgerEntry({
    required this.transaction,
    required this.category,
    required this.subcategory,
    required this.account,
  });

  final Transaction transaction;
  final Category category;
  final Category subcategory;
  final Account account;
}

class LedgerValidationException implements Exception {
  const LedgerValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

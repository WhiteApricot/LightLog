import '../../../data/database/database.dart';
import '../../../core/occurrence_time.dart';

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
    this.source = 'manual',
    this.confidence,
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
  final String source;
  final double? confidence;
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

class MonthlyOverview {
  const MonthlyOverview({
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final int incomeMinor;
  final int expenseMinor;
  int get balanceMinor => incomeMinor - expenseMinor;

  factory MonthlyOverview.fromEntries(
    Iterable<LedgerEntry> entries, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final entryList = entries.toList(growable: false);
    final entriesById = {
      for (final entry in entryList) entry.transaction.id: entry,
    };
    var income = 0;
    var expense = 0;
    for (final entry in entryList) {
      final transaction = entry.transaction;
      final wallTime = OccurrenceTime.restoreWallTime(
        utcMilliseconds: transaction.occurredAt,
        timezoneOffsetMinutes: transaction.timezoneOffsetMinutes,
      );
      if (wallTime.year != current.year || wallTime.month != current.month) {
        continue;
      }
      if (transaction.type == LedgerTransactionType.income.value) {
        income += transaction.amountMinor;
      } else if (transaction.type == LedgerTransactionType.expense.value) {
        expense += transaction.amountMinor;
      } else if (transaction.type == LedgerTransactionType.refund.value) {
        final original =
            entriesById[transaction.relatedTransactionId]?.transaction;
        if (original?.type == LedgerTransactionType.expense.value) {
          expense -= transaction.amountMinor;
        } else if (original?.type == LedgerTransactionType.income.value) {
          income -= transaction.amountMinor;
        }
      }
    }
    return MonthlyOverview(incomeMinor: income, expenseMinor: expense);
  }
}

class LedgerValidationException implements Exception {
  const LedgerValidationException(this.message);
  final String message;

  @override
  String toString() => message;
}

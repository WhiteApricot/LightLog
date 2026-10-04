import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/core/occurrence_time.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';

void main() {
  test('monthly overview uses each transaction occurrence offset', () {
    final entries = [
      _entry(
        id: 'income-current',
        type: 'income',
        amountMinor: 500000,
        wallTime: DateTime(2026, 10, 1, 0, 5),
        offsetMinutes: 480,
      ),
      _entry(
        id: 'expense-current',
        type: 'expense',
        amountMinor: 12550,
        wallTime: DateTime(2026, 10, 31, 23, 55),
        offsetMinutes: -300,
      ),
      _entry(
        id: 'expense-previous',
        type: 'expense',
        amountMinor: 9999,
        wallTime: DateTime(2026, 9, 30, 23, 59),
        offsetMinutes: 480,
      ),
      _entry(
        id: 'transfer-current',
        type: 'transfer',
        amountMinor: 100000,
        wallTime: DateTime(2026, 10, 15, 12),
        offsetMinutes: 480,
      ),
      _entry(
        id: 'refund-current',
        type: 'refund',
        amountMinor: 550,
        wallTime: DateTime(2026, 10, 20, 12),
        offsetMinutes: 480,
        relatedTransactionId: 'expense-current',
      ),
    ];

    final overview = MonthlyOverview.fromEntries(
      entries,
      now: DateTime(2026, 10, 4),
    );

    expect(overview.incomeMinor, 500000);
    expect(overview.expenseMinor, 12000);
    expect(overview.balanceMinor, 488000);
  });

  test('ledger day groups use wall dates and calculate daily totals', () {
    final entries = [
      _entry(
        id: 'late-expense',
        type: 'expense',
        amountMinor: 2500,
        wallTime: DateTime(2026, 10, 4, 23, 50),
        offsetMinutes: -300,
      ),
      _entry(
        id: 'income',
        type: 'income',
        amountMinor: 1000,
        wallTime: DateTime(2026, 10, 4, 9),
        offsetMinutes: 480,
      ),
      _entry(
        id: 'previous',
        type: 'expense',
        amountMinor: 800,
        wallTime: DateTime(2026, 10, 3, 8),
        offsetMinutes: 480,
      ),
    ];

    final groups = LedgerDayGroup.group(entries);

    expect(groups, hasLength(2));
    expect(groups.first.date, DateTime(2026, 10, 4));
    expect(groups.first.entries.map((entry) => entry.transaction.id), [
      'late-expense',
      'income',
    ]);
    expect(groups.first.totals.incomeMinor, 1000);
    expect(groups.first.totals.expenseMinor, 2500);
    expect(groups.last.date, DateTime(2026, 10, 3));
  });
}

LedgerEntry _entry({
  required String id,
  required String type,
  required int amountMinor,
  required DateTime wallTime,
  required int offsetMinutes,
  String? relatedTransactionId,
}) {
  const category = Category(
    id: 'category',
    name: '分类',
    type: 'expense',
    iconAsset: 'assets/icons/categories/expense-other.svg',
    sortOrder: 1,
    isActive: true,
    isSystem: true,
    createdAt: 0,
    updatedAt: 0,
  );
  const subcategory = Category(
    id: 'subcategory',
    parentId: 'category',
    name: '子分类',
    type: 'expense',
    iconAsset: 'assets/icons/categories/expense-other-general.svg',
    sortOrder: 1,
    isActive: true,
    isSystem: true,
    createdAt: 0,
    updatedAt: 0,
  );
  const account = Account(
    id: 'account',
    name: '现金',
    type: 'cash',
    iconAsset: 'assets/icons/accounts/account-cash.svg',
    isActive: true,
    sortOrder: 1,
    createdAt: 0,
    updatedAt: 0,
  );
  return LedgerEntry(
    transaction: Transaction(
      id: id,
      type: type,
      categoryId: category.id,
      subcategoryId: subcategory.id,
      content: id,
      amountMinor: amountMinor,
      currency: 'CNY',
      occurredAt: OccurrenceTime.toUtcMilliseconds(
        wallTime: wallTime,
        timezoneOffsetMinutes: offsetMinutes,
      ),
      timezoneOffsetMinutes: offsetMinutes,
      accountId: account.id,
      relatedTransactionId: relatedTransactionId,
      source: 'manual',
      createdAt: 0,
      updatedAt: 0,
      syncVersion: 1,
    ),
    category: category,
    subcategory: subcategory,
    account: account,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/app/light_log_app.dart';
import 'package:light_log/app/providers.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/features/ledger/data/ledger_repository.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';

void main() {
  testWidgets('empty ledger opens the manual transaction editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ledgerRepositoryProvider.overrideWithValue(_FakeLedgerRepository()),
        ],
        child: const LightLogApp(),
      ),
    );
    await tester.pump();

    expect(find.text('还没有账目'), findsOneWidget);
    expect(find.text('记一笔'), findsOneWidget);

    await tester.tap(find.text('记一笔'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('新增账目'), findsOneWidget);
    expect(find.text('金额（元）'), findsOneWidget);
    expect(find.text('一级分类'), findsOneWidget);
    expect(find.text('账户 / 支付方式'), findsOneWidget);
    expect(find.text('发生时间'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('transaction-save-button')),
      findsAtLeastNWidgets(1),
    );
  });
}

class _FakeLedgerRepository implements LedgerRepository {
  @override
  Stream<List<LedgerEntry>> watchEntries() => Stream.value(const []);

  @override
  Stream<List<Category>> watchCategories() => Stream.value(const [
    Category(
      id: 'expense-food',
      name: '餐饮',
      type: 'expense',
      sortOrder: 10,
      isActive: true,
      createdAt: 0,
      updatedAt: 0,
    ),
    Category(
      id: 'expense-food-other',
      parentId: 'expense-food',
      name: '其他餐饮',
      type: 'expense',
      sortOrder: 10,
      isActive: true,
      createdAt: 0,
      updatedAt: 0,
    ),
  ]);

  @override
  Stream<List<Account>> watchAccounts() => Stream.value(const [
    Account(
      id: 'account-cash',
      name: '现金',
      type: 'cash',
      isActive: true,
      sortOrder: 10,
      createdAt: 0,
      updatedAt: 0,
    ),
  ]);

  @override
  Future<String> create(TransactionDraft draft) => throw UnimplementedError();

  @override
  Future<void> update(String id, TransactionDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> softDelete(String id) => throw UnimplementedError();

  @override
  Future<void> restore(String id) => throw UnimplementedError();
}

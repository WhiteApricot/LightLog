import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/app/light_log_app.dart';
import 'package:light_log/app/providers.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/features/ledger/data/ledger_repository.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';

void main() {
  testWidgets('single entry action offers manual and text modes', (
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

    expect(find.text('选择录入方式'), findsOneWidget);
    expect(find.text('手动记账'), findsOneWidget);
    expect(find.text('智能文字记账'), findsOneWidget);

    await tester.tap(find.text('手动记账'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('新增账目'), findsOneWidget);
    expect(find.text('金额（元）'), findsOneWidget);
    expect(find.text('一级分类'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pump();
    expect(find.text('账户 / 支付方式'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-save-button')),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('text candidate must be confirmed before repository write', (
    tester,
  ) async {
    final repository = _FakeLedgerRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [ledgerRepositoryProvider.overrideWithValue(repository)],
        child: const LightLogApp(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('记一笔'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('智能文字记账'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.byKey(const ValueKey('text-entry-input')),
      '12:30 二食堂 15',
    );
    await tester.tap(find.byKey(const ValueKey('text-entry-parse-button')));
    await tester.pump();

    expect(find.text('候选结果'), findsOneWidget);
    expect(find.text('金额：¥15.00'), findsOneWidget);
    expect(find.text('分类：餐饮 · 午餐'), findsOneWidget);
    expect(repository.createdDraft, isNull);

    final confirm = find.byKey(const ValueKey('text-entry-confirm-button'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('确认文字账目'), findsOneWidget);
    expect(find.text('请确认或修改识别结果后保存'), findsOneWidget);
    final save = find.byKey(const ValueKey('transaction-save-button'));
    await tester.drag(find.byType(ListView).last, const Offset(0, -900));
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(repository.createdDraft?.source, 'text');
    expect(repository.createdDraft?.amountMinor, 1500);
    expect(repository.createdDraft?.content, '二食堂');
    expect(repository.createdDraft?.categoryId, 'expense-food');
    expect(repository.createdDraft?.subcategoryId, 'expense-food-lunch');
    expect(find.text('轻记'), findsOneWidget);
    expect(find.text('文字记账'), findsNothing);
  });
}

class _FakeLedgerRepository implements LedgerRepository {
  TransactionDraft? createdDraft;

  @override
  Stream<List<LedgerEntry>> watchEntries() => Stream.value(const []);

  @override
  Stream<List<Category>> watchCategories() => Stream.value(const [
    Category(
      id: 'expense-food',
      name: '餐饮',
      type: 'expense',
      iconAsset: 'assets/icons/categories/food.svg',
      sortOrder: 10,
      isActive: true,
      createdAt: 0,
      updatedAt: 0,
    ),
    Category(
      id: 'expense-food-lunch',
      parentId: 'expense-food',
      name: '午餐',
      type: 'expense',
      iconAsset: 'assets/icons/categories/meal.svg',
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
  Future<String> create(TransactionDraft draft) async {
    createdDraft = draft;
    return 'transaction-1';
  }

  @override
  Future<void> update(String id, TransactionDraft draft) =>
      throw UnimplementedError();

  @override
  Future<void> softDelete(String id) => throw UnimplementedError();

  @override
  Future<void> restore(String id) => throw UnimplementedError();
}

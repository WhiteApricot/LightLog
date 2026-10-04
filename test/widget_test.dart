import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/app/light_log_app.dart';
import 'package:light_log/app/providers.dart';
import 'package:light_log/core/occurrence_time.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/features/ledger/data/ledger_repository.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';

void main() {
  testWidgets('entry page combines smart input and manual form', (
    tester,
  ) async {
    final repository = _FakeLedgerRepository();
    await _pumpApp(tester, repository);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unified-smart-input')), findsOneWidget);
    expect(find.text('手动记账'), findsOneWidget);
    expect(find.text('金额（元）'), findsOneWidget);
    expect(find.text('选择录入方式'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('unified-smart-input')),
      '12:30 二食堂 15',
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const ValueKey('unified-smart-success')), findsNothing);
    expect(repository.createdDraft, isNull);

    await tester.tap(find.byKey(const ValueKey('unified-smart-parse-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('unified-smart-success')), findsOneWidget);
    expect(find.text('自动分类'), findsOneWidget);
    expect(find.text('时间'), findsOneWidget);
    expect(find.text('金额'), findsOneWidget);
    expect(find.text('内容 / 商户'), findsOneWidget);
    expect(find.text('餐饮 · 午餐'), findsOneWidget);
    expect(find.text('¥15.00'), findsOneWidget);
    expect(find.text('二食堂'), findsWidgets);
    await tester.tap(
      find.byKey(const ValueKey('smart-confirm-transaction-button')),
    );
    await tester.pumpAndSettle();

    expect(repository.createdDraft?.source, 'text');
    expect(repository.createdDraft?.amountMinor, 1500);
    expect(repository.createdDraft?.subcategoryId, 'expense-food-lunch');
    expect(find.text('轻记'), findsOneWidget);
  });

  testWidgets(
    'category groups are vertical, collapsible, and use child icons',
    (tester) async {
      await _pumpApp(tester, _FakeLedgerRepository());
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const ValueKey('child-category-icon-image-expense-food-lunch'),
        ),
        findsNothing,
      );
      final parentTile = find.byKey(
        const ValueKey('category-icon-expense-food'),
      );
      await tester.ensureVisible(parentTile);
      await tester.pumpAndSettle();
      await tester.tap(parentTile);
      await tester.pumpAndSettle();

      final childIcon = find.byKey(
        const ValueKey('child-category-icon-image-expense-food-lunch'),
      );
      expect(childIcon, findsOneWidget);
      final picture = tester.widget<SvgPicture>(childIcon);
      expect(
        (picture.bytesLoader as SvgAssetLoader).assetName,
        'assets/icons/categories/expense-food-lunch.svg',
      );

      await tester.tap(parentTile);
      await tester.pumpAndSettle();
      expect(childIcon, findsNothing);
      expect(find.byType(GridView), findsNWidgets(2));
    },
  );

  testWidgets('accounts use database-backed icon choices', (tester) async {
    await _pumpApp(tester, _FakeLedgerRepository());
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final alipay = find.byKey(const ValueKey('account-icon-account-alipay'));
    expect(alipay, findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    final picture = tester.widget<SvgPicture>(
      find.byKey(const ValueKey('account-icon-image-account-alipay')),
    );
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/accounts/account-alipay.svg',
    );
    await tester.tap(alipay);
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(
            find.ancestor(of: alipay, matching: find.byType(Semantics)).first,
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('time picker uses looping 24-hour wheels', (tester) async {
    await _pumpApp(tester, _FakeLedgerRepository());
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -1200));
    await tester.pumpAndSettle();
    final occurredTime = find.text('发生时间');
    await tester.tap(occurredTime);
    await tester.pumpAndSettle();

    final pickers = tester.widgetList<CupertinoPicker>(
      find.byType(CupertinoPicker),
    );
    expect(pickers, hasLength(2));
    for (final picker in pickers) {
      expect(picker.childDelegate, isA<ListWheelChildLoopingListDelegate>());
    }
    expect(find.text('选择时间（24 小时制）'), findsOneWidget);
  });

  testWidgets('ledger groups by date and supports long-press bulk delete', (
    tester,
  ) async {
    final repository = _FakeLedgerRepository(
      entries: [
        _entry(
          id: 'today-expense',
          content: '午餐',
          type: 'expense',
          amountMinor: 2500,
          wallTime: DateTime(2026, 10, 4, 12, 30),
        ),
        _entry(
          id: 'today-income',
          content: '报销',
          type: 'income',
          amountMinor: 1000,
          wallTime: DateTime(2026, 10, 4, 10),
        ),
        _entry(
          id: 'yesterday-expense',
          content: '早餐',
          type: 'expense',
          amountMinor: 800,
          wallTime: DateTime(2026, 10, 3, 8),
        ),
      ],
    );
    await _pumpApp(tester, repository);

    expect(find.text('10月4日 星期日'), findsOneWidget);
    expect(find.text('收入 ¥10.00  支出 ¥25.00'), findsOneWidget);
    expect(find.text('10月3日 星期六'), findsOneWidget);
    final ledgerIcon = find.byKey(
      const ValueKey('ledger-subcategory-icon-today-expense'),
    );
    final picture = tester.widget<SvgPicture>(ledgerIcon);
    expect(
      (picture.bytesLoader as SvgAssetLoader).assetName,
      'assets/icons/categories/expense-food-lunch.svg',
    );

    await tester.longPress(
      find.byKey(const ValueKey('ledger-entry-today-expense')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 项'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ledger-entry-today-income')));
    await tester.pump();
    expect(find.text('已选择 2 项'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('delete-selected-transactions')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-selected-transactions')),
    );
    await tester.pumpAndSettle();

    expect(repository.deletedMany, {'today-expense', 'today-income'});
  });

  testWidgets('existing transaction is deleted from editor action', (
    tester,
  ) async {
    final repository = _FakeLedgerRepository(
      entries: [
        _entry(
          id: 'editable',
          content: '待删除账目',
          type: 'expense',
          amountMinor: 1200,
          wallTime: DateTime(2026, 10, 4, 9),
        ),
      ],
    );
    await _pumpApp(tester, repository);

    await tester.tap(find.byKey(const ValueKey('ledger-entry-editable')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transaction-delete-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-transaction-delete')));
    await tester.pumpAndSettle();

    expect(repository.deletedMany, {'editable'});
    expect(find.text('轻记'), findsOneWidget);
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  _FakeLedgerRepository repository,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [ledgerRepositoryProvider.overrideWithValue(repository)],
      child: const LightLogApp(),
    ),
  );
  await tester.pump();
}

class _FakeLedgerRepository implements LedgerRepository {
  _FakeLedgerRepository({this.entries = const []});

  final List<LedgerEntry> entries;
  TransactionDraft? createdDraft;
  Set<String>? deletedMany;
  Set<String>? restoredMany;

  @override
  Stream<List<LedgerEntry>> watchEntries() => Stream.value(entries);

  @override
  Stream<List<Category>> watchCategories() => Stream.value(const [
    Category(
      id: 'expense-food',
      name: '餐饮',
      type: 'expense',
      iconAsset: 'assets/icons/categories/expense-food.svg',
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
      iconAsset: 'assets/icons/categories/expense-food-lunch.svg',
      sortOrder: 10,
      isActive: true,
      createdAt: 0,
      updatedAt: 0,
    ),
    Category(
      id: 'income-other',
      name: '其他收入',
      type: 'income',
      iconAsset: 'assets/icons/categories/income-other.svg',
      sortOrder: 10,
      isActive: true,
      createdAt: 0,
      updatedAt: 0,
    ),
    Category(
      id: 'income-other-general',
      parentId: 'income-other',
      name: '未分类收入',
      type: 'income',
      iconAsset: 'assets/icons/categories/income-other-general.svg',
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
      iconAsset: 'assets/icons/accounts/account-cash.svg',
      isActive: true,
      sortOrder: 10,
      createdAt: 0,
      updatedAt: 0,
    ),
    Account(
      id: 'account-alipay',
      name: '支付宝',
      type: 'alipay',
      iconAsset: 'assets/icons/accounts/account-alipay.svg',
      isActive: true,
      sortOrder: 20,
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
  Future<void> update(String id, TransactionDraft draft) async {}

  @override
  Future<void> softDelete(String id) => softDeleteMany({id});

  @override
  Future<void> softDeleteMany(Set<String> ids) async {
    deletedMany = Set.of(ids);
  }

  @override
  Future<void> restore(String id) => restoreMany({id});

  @override
  Future<void> restoreMany(Set<String> ids) async {
    restoredMany = Set.of(ids);
  }
}

LedgerEntry _entry({
  required String id,
  required String content,
  required String type,
  required int amountMinor,
  required DateTime wallTime,
}) {
  final isIncome = type == 'income';
  final category = isIncome ? _incomeCategory : _expenseCategory;
  final subcategory = isIncome ? _incomeSubcategory : _expenseSubcategory;
  return LedgerEntry(
    transaction: Transaction(
      id: id,
      type: type,
      categoryId: category.id,
      subcategoryId: subcategory.id,
      content: content,
      amountMinor: amountMinor,
      currency: 'CNY',
      occurredAt: OccurrenceTime.toUtcMilliseconds(
        wallTime: wallTime,
        timezoneOffsetMinutes: 480,
      ),
      timezoneOffsetMinutes: 480,
      accountId: _account.id,
      source: 'manual',
      createdAt: 0,
      updatedAt: 0,
      syncVersion: 1,
    ),
    category: category,
    subcategory: subcategory,
    account: _account,
  );
}

const _expenseCategory = Category(
  id: 'expense-food',
  name: '餐饮',
  type: 'expense',
  iconAsset: 'assets/icons/categories/expense-food.svg',
  sortOrder: 10,
  isActive: true,
  createdAt: 0,
  updatedAt: 0,
);

const _expenseSubcategory = Category(
  id: 'expense-food-lunch',
  parentId: 'expense-food',
  name: '午餐',
  type: 'expense',
  iconAsset: 'assets/icons/categories/expense-food-lunch.svg',
  sortOrder: 10,
  isActive: true,
  createdAt: 0,
  updatedAt: 0,
);

const _incomeCategory = Category(
  id: 'income-other',
  name: '其他收入',
  type: 'income',
  iconAsset: 'assets/icons/categories/income-other.svg',
  sortOrder: 10,
  isActive: true,
  createdAt: 0,
  updatedAt: 0,
);

const _incomeSubcategory = Category(
  id: 'income-other-general',
  parentId: 'income-other',
  name: '未分类收入',
  type: 'income',
  iconAsset: 'assets/icons/categories/income-other-general.svg',
  sortOrder: 10,
  isActive: true,
  createdAt: 0,
  updatedAt: 0,
);

const _account = Account(
  id: 'account-cash',
  name: '现金',
  type: 'cash',
  iconAsset: 'assets/icons/accounts/account-cash.svg',
  isActive: true,
  sortOrder: 10,
  createdAt: 0,
  updatedAt: 0,
);

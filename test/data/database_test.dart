import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/ledger/data/ledger_repository.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';

void main() {
  late AppDatabase database;
  late LocalLedgerRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LocalLedgerRepository(database);
  });

  tearDown(() => database.close());

  test('schema v1 seeds categories and accounts idempotently', () async {
    expect(
      await database.select(database.categories).get(),
      hasLength(defaultCategories.length),
    );
    expect(
      await database.select(database.accounts).get(),
      hasLength(defaultAccounts.length),
    );

    await database.seedDefaults();

    expect(
      await database.select(database.categories).get(),
      hasLength(defaultCategories.length),
    );
    expect(
      await database.select(database.accounts).get(),
      hasLength(defaultAccounts.length),
    );
  });

  test('initial database streams can be subscribed concurrently', () async {
    final results = await Future.wait([
      repository.watchEntries().first,
      repository.watchCategories().first,
      repository.watchAccounts().first,
    ]);

    expect(results[0], isEmpty);
    expect(results[1], hasLength(defaultCategories.length));
    expect(results[2], hasLength(defaultAccounts.length));
  });

  test(
    'repository creates, edits, soft deletes and restores reactively',
    () async {
      final id = await repository.create(
        transactionDraft(content: '二食堂', amountMinor: 1500),
      );
      var entries = await repository.watchEntries().first;
      expect(entries, hasLength(1));
      expect(entries.single.transaction.id, id);
      expect(entries.single.category.name, '餐饮');
      expect(entries.single.subcategory.name, '午餐');

      await repository.update(
        id,
        transactionDraft(content: '一食堂', amountMinor: 1680),
      );
      entries = await repository.watchEntries().first;
      expect(entries.single.transaction.content, '一食堂');
      expect(entries.single.transaction.amountMinor, 1680);

      await repository.softDelete(id);
      expect(await repository.watchEntries().first, isEmpty);
      expect(
        (await database.select(database.transactions).getSingle()).deletedAt,
        isNotNull,
      );

      await repository.restore(id);
      expect(await repository.watchEntries().first, hasLength(1));
    },
  );

  test('repository rejects mismatched category hierarchy', () async {
    final invalid = TransactionDraft(
      type: LedgerTransactionType.expense,
      categoryId: 'expense-food',
      subcategoryId: 'expense-transport-taxi',
      content: '错误分类',
      amountMinor: 100,
      occurredAtLocal: DateTime(2026, 10, 3, 12),
      accountId: 'account-cash',
    );

    await expectLater(
      repository.create(invalid),
      throwsA(isA<LedgerValidationException>()),
    );
  });
}

TransactionDraft transactionDraft({
  required String content,
  required int amountMinor,
}) {
  return TransactionDraft(
    type: LedgerTransactionType.expense,
    categoryId: 'expense-food',
    subcategoryId: 'expense-food-lunch',
    content: content,
    amountMinor: amountMinor,
    occurredAtLocal: DateTime(2026, 10, 3, 12, 30),
    accountId: 'account-wechat',
  );
}

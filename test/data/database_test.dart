import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/ledger/data/ledger_repository.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';

void main() {
  late AppDatabase database;
  late LocalLedgerRepository repository;
  var databaseClosed = false;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = LocalLedgerRepository(database);
    databaseClosed = false;
  });

  tearDown(() async {
    if (!databaseClosed) await database.close();
  });

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
      timezoneOffsetMinutes: 480,
      accountId: 'account-cash',
    );

    await expectLater(
      repository.create(invalid),
      throwsA(isA<LedgerValidationException>()),
    );
  });

  test('editing preserves the supplied occurrence timezone offset', () async {
    final id = await repository.create(
      transactionDraft(
        content: '尼泊尔早餐',
        amountMinor: 1200,
        occurredAtLocal: DateTime.utc(2026, 6, 8, 9, 7),
        timezoneOffsetMinutes: 345,
      ),
    );

    await repository.update(
      id,
      transactionDraft(
        content: '尼泊尔早餐（已编辑）',
        amountMinor: 1200,
        occurredAtLocal: DateTime.utc(2026, 6, 8, 9, 8),
        timezoneOffsetMinutes: 345,
      ),
    );

    final saved = await database.select(database.transactions).getSingle();
    expect(saved.timezoneOffsetMinutes, 345);
    expect(
      saved.occurredAt,
      DateTime.utc(2026, 6, 8, 3, 23).millisecondsSinceEpoch,
    );
  });

  test('transaction survives closing and reopening a file database', () async {
    await database.close();
    databaseClosed = true;
    final tempDirectory = await Directory.systemTemp.createTemp(
      'light_log_database_test_',
    );
    final databaseFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}ledger.sqlite',
    );
    AppDatabase? fileDatabase;
    try {
      fileDatabase = AppDatabase(NativeDatabase(databaseFile));
      final fileRepository = LocalLedgerRepository(fileDatabase);
      final id = await fileRepository.create(
        transactionDraft(content: '持久化账目', amountMinor: 2500),
      );
      await fileDatabase.close();
      fileDatabase = null;

      fileDatabase = AppDatabase(NativeDatabase(databaseFile));
      final reopenedRepository = LocalLedgerRepository(fileDatabase);
      final entries = await reopenedRepository.watchEntries().first;

      expect(entries, hasLength(1));
      expect(entries.single.transaction.id, id);
      expect(entries.single.transaction.content, '持久化账目');
      expect(entries.single.transaction.amountMinor, 2500);
    } finally {
      await fileDatabase?.close();
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    }
  });
}

TransactionDraft transactionDraft({
  required String content,
  required int amountMinor,
  DateTime? occurredAtLocal,
  int timezoneOffsetMinutes = 480,
}) {
  return TransactionDraft(
    type: LedgerTransactionType.expense,
    categoryId: 'expense-food',
    subcategoryId: 'expense-food-lunch',
    content: content,
    amountMinor: amountMinor,
    occurredAtLocal: occurredAtLocal ?? DateTime.utc(2026, 10, 3, 12, 30),
    timezoneOffsetMinutes: timezoneOffsetMinutes,
    accountId: 'account-wechat',
  );
}

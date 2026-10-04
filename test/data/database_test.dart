import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/database.dart';
import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/ledger/data/ledger_repository.dart';
import 'package:light_log/features/ledger/domain/ledger_models.dart';
import 'package:light_log/features/recognition/data/recognition_repository.dart';

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

  test(
    'schema v4 seeds semantic system categories and icon-backed accounts',
    () async {
      expect(
        await database.select(database.categories).get(),
        hasLength(defaultCategories.length),
      );
      expect(
        await database.select(database.accounts).get(),
        hasLength(defaultAccounts.length),
      );
      final categories = await database.select(database.categories).get();
      expect(categories, hasLength(141));
      expect(
        categories.every(
          (category) =>
              category.iconAsset.startsWith('assets/icons/categories/'),
        ),
        isTrue,
      );
      expect(
        categories.every(
          (category) => category.isSystem && category.semanticKey != null,
        ),
        isTrue,
      );
      for (final category in categories) {
        expect(
          File(category.iconAsset).existsSync(),
          isTrue,
          reason: '${category.name} 缺少图标 ${category.iconAsset}',
        );
      }
      final accounts = await database.select(database.accounts).get();
      expect(
        accounts.every(
          (account) => account.iconAsset.startsWith('assets/icons/accounts/'),
        ),
        isTrue,
      );
      for (final account in accounts) {
        expect(
          File(account.iconAsset).existsSync(),
          isTrue,
          reason: '${account.name} 缺少图标 ${account.iconAsset}',
        );
      }

      await database.seedDefaults();

      expect(
        await database.select(database.categories).get(),
        hasLength(defaultCategories.length),
      );
      expect(
        await database.select(database.accounts).get(),
        hasLength(defaultAccounts.length),
      );
    },
  );

  test(
    'migrates schema v1 through semantic categories and recognition rules',
    () async {
      await database.close();
      databaseClosed = true;
      final executor = NativeDatabase.memory(
        setup: (rawDatabase) {
          rawDatabase.execute('''
          CREATE TABLE categories (
            id TEXT NOT NULL PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
          rawDatabase.execute('''
          CREATE TABLE accounts (
            id TEXT NOT NULL PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            is_active INTEGER NOT NULL DEFAULT 1,
            sort_order INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
          rawDatabase.execute(
            "INSERT INTO categories VALUES "
            "('expense-food-drink', 'expense-food', '饮料', 'expense', 40, 1, 0, 0)",
          );
          rawDatabase.execute(
            "INSERT INTO accounts VALUES "
            "('account-cash', '现金', 'cash', 1, 40, 0, 0)",
          );
          rawDatabase.execute('PRAGMA user_version = 1');
        },
      );
      final migrated = AppDatabase(executor);
      try {
        final category = await (migrated.select(
          migrated.categories,
        )..where((table) => table.id.equals('expense-food-drink'))).getSingle();
        expect(category.name, '饮品');
        expect(
          category.iconAsset,
          'assets/icons/categories/expense-food-drink.svg',
        );
        expect(category.semanticKey, 'expense.food.drink');
        expect(category.isSystem, isTrue);
        expect(await migrated.select(migrated.recognitionRules).get(), isEmpty);
        final account = await (migrated.select(
          migrated.accounts,
        )..where((table) => table.id.equals('account-cash'))).getSingle();
        expect(account.iconAsset, 'assets/icons/accounts/account-cash.svg');
      } finally {
        await migrated.close();
      }
    },
  );

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

  test('repository bulk soft deletes and restores atomically', () async {
    final first = await repository.create(
      transactionDraft(content: '第一笔', amountMinor: 100),
    );
    final second = await repository.create(
      transactionDraft(content: '第二笔', amountMinor: 200),
    );

    await repository.softDeleteMany({first, second});
    expect(await repository.watchEntries().first, isEmpty);

    await repository.restoreMany({first, second});
    expect(await repository.watchEntries().first, hasLength(2));

    await expectLater(
      repository.softDeleteMany({first, 'missing'}),
      throwsA(isA<LedgerValidationException>()),
    );
    expect(await repository.watchEntries().first, hasLength(2));
  });

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

  test('repository persists and validates recognition metadata', () async {
    await repository.create(
      transactionDraft(
        content: '文字账目',
        amountMinor: 1500,
        source: 'text',
        confidence: 0.8,
      ),
    );

    final saved = await database.select(database.transactions).getSingle();
    expect(saved.source, 'text');
    expect(saved.confidence, 0.8);

    await expectLater(
      repository.create(
        transactionDraft(
          content: '无效置信度',
          amountMinor: 1500,
          source: 'text',
          confidence: 1.1,
        ),
      ),
      throwsA(isA<LedgerValidationException>()),
    );
  });

  test('recognition feedback records hits and explicit corrections', () async {
    final recognitionRepository = LocalRecognitionRepository(database);
    await recognitionRepository.recordFeedback(
      normalizedContent: '星巴克',
      predictedSemanticKey: 'expense.food.drink',
      finalCategoryId: 'expense-food-drink',
    );
    await recognitionRepository.recordFeedback(
      normalizedContent: '星巴克',
      predictedSemanticKey: 'expense.food.drink',
      finalCategoryId: 'expense-food-dinner',
    );

    final records = await recognitionRepository.loadHistory();
    final drink = records.singleWhere(
      (item) => item.semanticKey == 'expense.food.drink',
    );
    final dinner = records.singleWhere(
      (item) => item.semanticKey == 'expense.food.dinner',
    );
    expect(drink.hitCount, 1);
    expect(drink.correctionCount, 1);
    expect(dinner.hitCount, 1);
    expect(dinner.correctionCount, 0);
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
  String source = 'manual',
  double? confidence,
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
    source: source,
    confidence: confidence,
  );
}

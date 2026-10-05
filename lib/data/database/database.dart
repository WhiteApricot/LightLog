import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'seed_data.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Transactions, Categories, Accounts, RecognitionRules])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(categories, categories.iconAsset);
        await customStatement(
          "UPDATE categories SET name = '饮品' WHERE id = 'expense-food-drink'",
        );
        await customStatement(
          "UPDATE categories SET name = '公交地铁' WHERE id = 'expense-transport-public'",
        );
        await customStatement(
          "UPDATE categories SET is_active = 0 WHERE id = 'expense-shopping-daily'",
        );
        await customStatement(
          "UPDATE categories SET name = '未分类支出' WHERE id = 'expense-other-general'",
        );
        await customStatement(
          "UPDATE categories SET name = '工资奖金' WHERE id = 'income-salary'",
        );
        await customStatement(
          "UPDATE categories SET name = '基本工资' WHERE id = 'income-salary-monthly'",
        );
        await customStatement(
          "UPDATE categories SET name = '未分类收入' WHERE id = 'income-other-general'",
        );
      }
      if (from < 3) {
        await migrator.addColumn(accounts, accounts.iconAsset);
        for (final category in defaultCategories) {
          await (update(
            categories,
          )..where((table) => table.id.equals(category.id))).write(
            CategoriesCompanion(
              iconAsset: Value(category.iconAsset),
              updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            ),
          );
        }
        for (final account in defaultAccounts) {
          await (update(
            accounts,
          )..where((table) => table.id.equals(account.id))).write(
            AccountsCompanion(
              iconAsset: Value(account.iconAsset),
              updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            ),
          );
        }
      }
      if (from < 4) {
        await migrator.addColumn(categories, categories.semanticKey);
        await migrator.addColumn(categories, categories.isSystem);
        await migrator.createTable(recognitionRules);
        for (final category in defaultCategories) {
          await (update(
            categories,
          )..where((table) => table.id.equals(category.id))).write(
            CategoriesCompanion(
              semanticKey: Value(category.semanticKey),
              isSystem: const Value(true),
              updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            ),
          );
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await seedDefaults();
    },
  );

  Future<void> seedDefaults() => transaction(() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    // Data-only taxonomy migration: retain historical IDs and foreign keys.
    await (update(categories)..where(
          (table) =>
              table.id.isIn(retiredDefaultCategoryIds) &
              (table.isActive.equals(true) | table.semanticKey.isNotNull()),
        ))
        .write(
          CategoriesCompanion(
            isActive: const Value(false),
            semanticKey: const Value(null),
            updatedAt: Value(now),
          ),
        );
    await (update(categories)..where(
          (table) =>
              table.semanticKey.isNotNull() &
              table.semanticKey.isNotIn(categorySemanticKeys.values),
        ))
        .write(
          CategoriesCompanion(
            semanticKey: const Value(null),
            updatedAt: Value(now),
          ),
        );
    for (final category in defaultCategories) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: category.id,
          parentId: Value(category.parentId),
          name: category.name,
          type: category.type,
          iconAsset: Value(category.iconAsset),
          semanticKey: Value(category.semanticKey),
          isSystem: const Value(true),
          sortOrder: category.sortOrder,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await (update(categories)..where(
            (table) =>
                table.id.equals(category.id) &
                (table.iconAsset.equals('assets/icons/categories/other.svg') |
                    table.iconAsset.equals(
                      'assets/icons/categories/category-default.svg',
                    )),
          ))
          .write(
            CategoriesCompanion(
              iconAsset: Value(category.iconAsset),
              semanticKey: Value(category.semanticKey),
              isSystem: const Value(true),
            ),
          );
    }
    for (final account in defaultAccounts) {
      await into(accounts).insert(
        AccountsCompanion.insert(
          id: account.id,
          name: account.name,
          type: account.type,
          iconAsset: Value(account.iconAsset),
          sortOrder: account.sortOrder,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      await (update(accounts)..where(
            (table) =>
                table.id.equals(account.id) &
                table.iconAsset.equals(
                  'assets/icons/accounts/account-other.svg',
                ),
          ))
          .write(AccountsCompanion(iconAsset: Value(account.iconAsset)));
    }
  });

  static QueryExecutor _openConnection() => driftDatabase(name: 'light_log');
}

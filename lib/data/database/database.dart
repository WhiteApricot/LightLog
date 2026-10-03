import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'seed_data.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Transactions, Categories, Accounts])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await seedDefaults();
    },
  );

  Future<void> seedDefaults() => transaction(() async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final category in defaultCategories) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: category.id,
          parentId: Value(category.parentId),
          name: category.name,
          type: category.type,
          sortOrder: category.sortOrder,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
    for (final account in defaultAccounts) {
      await into(accounts).insert(
        AccountsCompanion.insert(
          id: account.id,
          name: account.name,
          type: account.type,
          sortOrder: account.sortOrder,
          createdAt: now,
          updatedAt: now,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  });

  static QueryExecutor _openConnection() => driftDatabase(name: 'light_log');
}

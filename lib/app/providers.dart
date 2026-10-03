import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../features/ledger/data/ledger_repository.dart';
import '../features/ledger/domain/ledger_models.dart';
import '../features/recognition/domain/text_entry_parser.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LocalLedgerRepository(ref.watch(databaseProvider));
});

final textEntryParserProvider = Provider<TextEntryParser>((ref) {
  return const TextEntryParser();
});

final ledgerEntriesProvider = StreamProvider<List<LedgerEntry>>((ref) {
  return ref.watch(ledgerRepositoryProvider).watchEntries();
});

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(ledgerRepositoryProvider).watchCategories();
});

final accountsProvider = StreamProvider<List<Account>>((ref) {
  return ref.watch(ledgerRepositoryProvider).watchAccounts();
});

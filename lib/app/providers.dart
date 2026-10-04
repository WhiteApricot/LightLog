import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../data/database/database.dart';
import '../features/ledger/data/ledger_repository.dart';
import '../features/ledger/domain/ledger_models.dart';
import '../features/recognition/domain/text_entry_parser.dart';
import '../features/recognition/data/knowledge_loader.dart';
import '../features/recognition/data/recognition_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return LocalLedgerRepository(ref.watch(databaseProvider));
});

final recognitionRepositoryProvider = Provider<RecognitionRepository>((ref) {
  return LocalRecognitionRepository(ref.watch(databaseProvider));
});

final textEntryParserProvider = FutureProvider<TextEntryParser>((ref) async {
  final knowledge = await KnowledgeLoader(rootBundle).load();
  return TextEntryParser(knowledge: knowledge);
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

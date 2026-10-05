import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../data/database/database.dart';
import '../features/ledger/data/ledger_repository.dart';
import '../features/ledger/domain/ledger_models.dart';
import '../features/recognition/application/recognition_coordinator.dart';
import '../features/recognition/data/knowledge_loader.dart';
import '../features/recognition/data/recognition_repository.dart';
import '../features/recognition/domain/recognizer.dart';
import '../features/recognition/domain/ngram_classifier.dart';
import '../features/recognition/domain/ngram_model.dart';

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

final localRecognizerProvider = FutureProvider<LocalRecognizer>((ref) async {
  final knowledge = await KnowledgeLoader(rootBundle).load();
  final bytes = await rootBundle.load('assets/knowledge/ngram.bin');
  return LocalRecognizer(
    knowledge: knowledge,
    ngram: NgramClassifier(
      NgramModel.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    ),
  );
});

final recognitionCoordinatorProvider = FutureProvider<RecognitionCoordinator>((
  ref,
) async {
  return RecognitionCoordinator(
    await ref.watch(localRecognizerProvider.future),
    ref.watch(recognitionRepositoryProvider),
  );
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

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/occurrence_time.dart';
import '../../../data/database/database.dart';
import '../domain/ledger_models.dart';

abstract interface class LedgerRepository {
  Stream<List<LedgerEntry>> watchEntries();
  Stream<List<Category>> watchCategories();
  Stream<List<Account>> watchAccounts();
  Future<String> create(TransactionDraft draft);
  Future<void> update(String id, TransactionDraft draft);
  Future<void> softDelete(String id);
  Future<void> restore(String id);
}

class LocalLedgerRepository implements LedgerRepository {
  LocalLedgerRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  @override
  Stream<List<LedgerEntry>> watchEntries() {
    final parent = _database.alias(_database.categories, 'parent_category');
    final child = _database.alias(_database.categories, 'child_category');
    final query =
        _database.select(_database.transactions).join([
            innerJoin(
              parent,
              parent.id.equalsExp(_database.transactions.categoryId),
            ),
            innerJoin(
              child,
              child.id.equalsExp(_database.transactions.subcategoryId),
            ),
            innerJoin(
              _database.accounts,
              _database.accounts.id.equalsExp(_database.transactions.accountId),
            ),
          ])
          ..where(_database.transactions.deletedAt.isNull())
          ..orderBy([OrderingTerm.desc(_database.transactions.occurredAt)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => LedgerEntry(
              transaction: row.readTable(_database.transactions),
              category: row.readTable(parent),
              subcategory: row.readTable(child),
              account: row.readTable(_database.accounts),
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Stream<List<Category>> watchCategories() =>
      (_database.select(_database.categories)
            ..where((table) => table.isActive.equals(true))
            ..orderBy([
              (table) => OrderingTerm.asc(table.sortOrder),
              (table) => OrderingTerm.asc(table.name),
            ]))
          .watch();

  @override
  Stream<List<Account>> watchAccounts() =>
      (_database.select(_database.accounts)
            ..where((table) => table.isActive.equals(true))
            ..orderBy([(table) => OrderingTerm.asc(table.sortOrder)]))
          .watch();

  @override
  Future<String> create(TransactionDraft draft) async {
    await _validateDraft(draft);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _database
        .into(_database.transactions)
        .insert(
          _companion(id: id, draft: draft, createdAt: now, updatedAt: now),
        );
    return id;
  }

  @override
  Future<void> update(String id, TransactionDraft draft) async {
    await _validateDraft(draft);
    final existing = await (_database.select(
      _database.transactions,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (existing == null || existing.deletedAt != null) {
      throw const LedgerValidationException('账目不存在或已删除');
    }
    final changed =
        await (_database.update(
          _database.transactions,
        )..where((table) => table.id.equals(id))).write(
          _companion(
            id: id,
            draft: draft,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
    if (changed != 1) throw const LedgerValidationException('更新账目失败');
  }

  @override
  Future<void> softDelete(String id) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final changed =
        await (_database.update(
              _database.transactions,
            )..where((table) => table.id.equals(id) & table.deletedAt.isNull()))
            .write(
              TransactionsCompanion(
                deletedAt: Value(now),
                updatedAt: Value(now),
              ),
            );
    if (changed != 1) throw const LedgerValidationException('账目不存在或已删除');
  }

  @override
  Future<void> restore(String id) async {
    final changed =
        await (_database.update(_database.transactions)..where(
              (table) => table.id.equals(id) & table.deletedAt.isNotNull(),
            ))
            .write(
              TransactionsCompanion(
                deletedAt: const Value(null),
                updatedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
              ),
            );
    if (changed != 1) throw const LedgerValidationException('已删除账目不存在');
  }

  TransactionsCompanion _companion({
    required String id,
    required TransactionDraft draft,
    required int createdAt,
    required int updatedAt,
  }) {
    final occurredAt = OccurrenceTime.toUtcMilliseconds(
      wallTime: draft.occurredAtLocal,
      timezoneOffsetMinutes: draft.timezoneOffsetMinutes,
    );
    return TransactionsCompanion.insert(
      id: id,
      type: draft.type.value,
      categoryId: draft.categoryId,
      subcategoryId: draft.subcategoryId,
      content: draft.content.trim(),
      note: Value(_nullableTrimmed(draft.note)),
      amountMinor: draft.amountMinor,
      occurredAt: occurredAt,
      timezoneOffsetMinutes: draft.timezoneOffsetMinutes,
      accountId: draft.accountId,
      destinationAccountId: Value(draft.destinationAccountId),
      relatedTransactionId: Value(draft.relatedTransactionId),
      source: Value(draft.source),
      confidence: Value(draft.confidence),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Future<void> _validateDraft(TransactionDraft draft) async {
    if (draft.content.trim().isEmpty) {
      throw const LedgerValidationException('内容不能为空');
    }
    if (draft.amountMinor <= 0) {
      throw const LedgerValidationException('金额必须大于零');
    }
    if (draft.timezoneOffsetMinutes < -840 ||
        draft.timezoneOffsetMinutes > 840) {
      throw const LedgerValidationException('时区偏移无效');
    }
    if (!const {'manual', 'text', 'image', 'import'}.contains(draft.source)) {
      throw const LedgerValidationException('账目来源无效');
    }
    if (draft.confidence != null &&
        (draft.confidence! < 0 || draft.confidence! > 1)) {
      throw const LedgerValidationException('识别置信度无效');
    }
    final category =
        await (_database.select(_database.categories)..where(
              (table) =>
                  table.id.equals(draft.categoryId) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    final subcategory =
        await (_database.select(_database.categories)..where(
              (table) =>
                  table.id.equals(draft.subcategoryId) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (category == null || category.parentId != null) {
      throw const LedgerValidationException('一级分类无效');
    }
    if (subcategory == null || subcategory.parentId != category.id) {
      throw const LedgerValidationException('二级分类与一级分类不匹配');
    }
    if (category.type != draft.type.value ||
        subcategory.type != draft.type.value) {
      throw const LedgerValidationException('分类与账务类型不匹配');
    }
    final account =
        await (_database.select(_database.accounts)..where(
              (table) =>
                  table.id.equals(draft.accountId) &
                  table.isActive.equals(true),
            ))
            .getSingleOrNull();
    if (account == null) throw const LedgerValidationException('账户无效');
    if (draft.type == LedgerTransactionType.transfer &&
        (draft.destinationAccountId == null ||
            draft.destinationAccountId == draft.accountId)) {
      throw const LedgerValidationException('转账必须选择不同的转入账户');
    }
    if (draft.type == LedgerTransactionType.refund &&
        draft.relatedTransactionId == null) {
      throw const LedgerValidationException('退款必须关联原账目');
    }
  }

  static String? _nullableTrimmed(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

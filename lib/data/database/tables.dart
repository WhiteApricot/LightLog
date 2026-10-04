import 'package:drift/drift.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text().nullable().references(Categories, #id)();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get type => text()();
  TextColumn get iconAsset => text().withDefault(
    const Constant('assets/icons/categories/category-default.svg'),
  )();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (type IN ('expense', 'income', 'transfer', 'refund'))",
  ];
}

class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 40)();
  TextColumn get type => text()();
  TextColumn get iconAsset => text().withDefault(
    const Constant('assets/icons/accounts/account-other.svg'),
  )();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (type IN ('wechat', 'alipay', 'bank_card', 'cash', 'other'))",
  ];
}

@TableIndex(name: 'transactions_occurred_at', columns: {#occurredAt})
@TableIndex(name: 'transactions_deleted_at', columns: {#deletedAt})
@TableIndex(
  name: 'transactions_type_occurred_at',
  columns: {#type, #occurredAt},
)
@TableIndex(name: 'transactions_fingerprint', columns: {#fingerprint})
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get subcategoryId => text().references(Categories, #id)();
  TextColumn get content => text().withLength(min: 1, max: 120)();
  TextColumn get note => text().nullable()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => text().withDefault(const Constant('CNY'))();
  IntColumn get occurredAt => integer()();
  IntColumn get timezoneOffsetMinutes => integer()();
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get destinationAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get relatedTransactionId =>
      text().nullable().references(Transactions, #id)();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  RealColumn get confidence => real().nullable()();
  TextColumn get fingerprint => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();
  IntColumn get syncVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (type IN ('expense', 'income', 'transfer', 'refund'))",
    'CHECK (amount_minor > 0)',
    'CHECK (timezone_offset_minutes BETWEEN -840 AND 840)',
    "CHECK (currency = 'CNY')",
    "CHECK (source IN ('manual', 'text', 'image', 'import'))",
    "CHECK (type != 'transfer' OR (destination_account_id IS NOT NULL AND destination_account_id != account_id))",
    "CHECK (type != 'refund' OR related_transaction_id IS NOT NULL)",
  ];
}

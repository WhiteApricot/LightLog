import '../../../data/database/database.dart';
import '../../ledger/domain/ledger_models.dart';

class ResolvedCategory {
  const ResolvedCategory({required this.parent, required this.child});

  final Category parent;
  final Category child;
}

class CategoryResolver {
  const CategoryResolver();

  ResolvedCategory? resolve({
    required String semanticKey,
    required LedgerTransactionType type,
    required List<Category> categories,
  }) {
    final candidates =
        categories
            .where(
              (item) =>
                  item.isActive &&
                  item.type == type.value &&
                  item.parentId != null &&
                  item.semanticKey == semanticKey,
            )
            .toList()
          ..sort((a, b) {
            if (a.isSystem != b.isSystem) return a.isSystem ? 1 : -1;
            return a.sortOrder.compareTo(b.sortOrder);
          });
    if (candidates.isEmpty) return null;
    final child = candidates.first;
    final parent = categories
        .where(
          (item) =>
              item.id == child.parentId &&
              item.isActive &&
              item.type == type.value,
        )
        .firstOrNull;
    return parent == null
        ? null
        : ResolvedCategory(parent: parent, child: child);
  }
}

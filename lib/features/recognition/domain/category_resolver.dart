import 'recognition_models.dart';

class ResolvedCategory {
  const ResolvedCategory({required this.parent, required this.child});

  final RecognitionCategory parent;
  final RecognitionCategory child;
}

class CategoryResolver {
  const CategoryResolver();

  ResolvedCategory? resolve({
    required String semanticKey,
    required RecognitionTransactionType type,
    required List<RecognitionCategory> categories,
  }) {
    final candidates =
        categories
            .where(
              (item) =>
                  item.isActive &&
                  item.type == type &&
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
              item.id == child.parentId && item.isActive && item.type == type,
        )
        .firstOrNull;
    return parent == null
        ? null
        : ResolvedCategory(parent: parent, child: child);
  }
}

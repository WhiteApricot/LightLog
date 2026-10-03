import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/database/database.dart';

class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.title,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.errorText,
    this.rows = 2,
  });

  final String title;
  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<Category> onSelected;
  final String? errorText;
  final int rows;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          height: rows == 1 ? 84 : 172,
          child: GridView.builder(
            key: ValueKey('$title-${categories.firstOrNull?.parentId}'),
            scrollDirection: Axis.horizontal,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: rows,
              mainAxisExtent: 82,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final selected = category.id == selectedId;
              return Semantics(
                button: true,
                selected: selected,
                label: '$title ${category.name}',
                child: InkWell(
                  key: ValueKey('category-icon-${category.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(category),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primaryContainer
                          : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? colors.primary
                            : colors.outlineVariant,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          category.iconAsset,
                          width: 28,
                          height: 28,
                          colorFilter: ColorFilter.mode(
                            selected ? colors.primary : colors.onSurfaceVariant,
                            BlendMode.srcIn,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: selected
                                    ? colors.onPrimaryContainer
                                    : colors.onSurface,
                                fontWeight: selected ? FontWeight.w700 : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.error),
            ),
          ),
        ],
      ],
    );
  }
}

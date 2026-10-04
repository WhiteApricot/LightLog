import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/database/database.dart';

class CategoryPicker extends StatefulWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedParentId,
    required this.selectedChildId,
    required this.onParentSelected,
    required this.onChildSelected,
    this.errorText,
  });

  final List<Category> categories;
  final String? selectedParentId;
  final String? selectedChildId;
  final ValueChanged<Category> onParentSelected;
  final ValueChanged<Category> onChildSelected;
  final String? errorText;

  @override
  State<CategoryPicker> createState() => _CategoryPickerState();
}

class _CategoryPickerState extends State<CategoryPicker> {
  String? _expandedParentId;

  @override
  void initState() {
    super.initState();
    _expandedParentId = _parentIdForSelectedChild();
  }

  @override
  void didUpdateWidget(covariant CategoryPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedChildId != oldWidget.selectedChildId &&
        widget.selectedChildId != null) {
      _expandedParentId = _parentIdForSelectedChild();
    }
    if (widget.selectedParentId != oldWidget.selectedParentId &&
        widget.selectedChildId == null &&
        _expandedParentId != widget.selectedParentId) {
      _expandedParentId = null;
    }
  }

  String? _parentIdForSelectedChild() => widget.categories
      .where((item) => item.id == widget.selectedChildId)
      .firstOrNull
      ?.parentId;

  @override
  Widget build(BuildContext context) {
    final parents = widget.categories
        .where((category) => category.parentId == null)
        .toList(growable: false);
    final children = widget.categories
        .where((category) => category.parentId == _expandedParentId)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('分类', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _CategoryGrid(
          categories: parents,
          selectedId: widget.selectedParentId,
          imageKeyPrefix: 'parent-category-icon-image',
          onSelected: (category) {
            final collapse = _expandedParentId == category.id;
            widget.onParentSelected(category);
            setState(() {
              _expandedParentId = collapse ? null : category.id;
            });
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: _expandedParentId == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 6),
                        child: Text(
                          '二级分类',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ),
                      _CategoryGrid(
                        key: ValueKey('children-$_expandedParentId'),
                        categories: children,
                        selectedId: widget.selectedChildId,
                        imageKeyPrefix: 'child-category-icon-image',
                        onSelected: widget.onChildSelected,
                      ),
                    ],
                  ),
                ),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              widget.errorText!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.imageKeyPrefix,
    required this.onSelected,
  });

  final List<Category> categories;
  final String? selectedId;
  final String imageKeyPrefix;
  final ValueChanged<Category> onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 8 : 6;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 60,
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
        ),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          return _CategoryTile(
            category: category,
            selected: category.id == selectedId,
            imageKey: ValueKey('$imageKeyPrefix-${category.id}'),
            onTap: () => onSelected(category),
          );
        },
      );
    },
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.imageKey,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final Key imageKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      child: InkWell(
        key: ValueKey('category-icon-${category.id}'),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                category.iconAsset,
                key: imageKey,
                width: 19,
                height: 19,
                colorFilter: ColorFilter.mode(
                  selected ? colors.primary : colors.onSurfaceVariant,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
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
  }
}

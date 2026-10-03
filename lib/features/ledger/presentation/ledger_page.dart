import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../core/occurrence_time.dart';
import '../../entry/presentation/entry_page.dart';
import '../../entry/presentation/transaction_editor_page.dart';
import '../domain/ledger_models.dart';

class LedgerPage extends ConsumerStatefulWidget {
  const LedgerPage({super.key});

  @override
  ConsumerState<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends ConsumerState<LedgerPage> {
  final Set<String> _selectedIds = {};

  bool get _selecting => _selectedIds.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(ledgerEntriesProvider);
    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                tooltip: '退出多选',
                onPressed: () => setState(_selectedIds.clear),
                icon: const Icon(Icons.close),
              ),
              title: Text('已选择 ${_selectedIds.length} 项'),
              actions: [
                IconButton(
                  key: const ValueKey('delete-selected-transactions'),
                  tooltip: '删除所选账目',
                  onPressed: _deleteSelected,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            )
          : AppBar(title: const Text('轻记')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LedgerError(
          message: '账本加载失败：$error',
          onRetry: () => ref.invalidate(ledgerEntriesProvider),
        ),
        data: (items) => _LedgerBody(
          items: items,
          selectedIds: _selectedIds,
          onTap: (entry) {
            if (_selecting) {
              _toggleSelection(entry.transaction.id);
            } else {
              _openEditor(entry);
            }
          },
          onLongPress: (entry) => _toggleSelection(entry.transaction.id),
        ),
      ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const EntryPage()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('记一笔'),
            ),
    );
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  Future<void> _openEditor(LedgerEntry entry) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransactionEditorPage(entry: entry)),
    );
  }

  Future<void> _deleteSelected() async {
    final ids = Set<String>.of(_selectedIds);
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除所选 ${ids.length} 笔账目？'),
        content: const Text('所选账目将移入已删除状态，可立即撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-selected-transactions'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repository = ref.read(ledgerRepositoryProvider);
    try {
      await repository.softDeleteMany(ids);
      if (!mounted) return;
      setState(_selectedIds.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除 ${ids.length} 笔账目'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              try {
                await repository.restoreMany(ids);
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('撤销失败：$error')));
                }
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    }
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({
    required this.items,
    required this.selectedIds,
    required this.onTap,
    required this.onLongPress,
  });

  final List<LedgerEntry> items;
  final Set<String> selectedIds;
  final ValueChanged<LedgerEntry> onTap;
  final ValueChanged<LedgerEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    final overview = MonthlyOverview.fromEntries(items);
    final groups = LedgerDayGroup.group(items);
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        _MonthlyOverviewCard(overview: overview),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Text('账目明细', style: Theme.of(context).textTheme.titleMedium),
        ),
        if (items.isEmpty)
          const _EmptyLedger()
        else
          for (final group in groups) ...[
            _DayHeader(group: group),
            for (final entry in group.entries)
              _LedgerTile(
                entry: entry,
                selected: selectedIds.contains(entry.transaction.id),
                selectionMode: selectedIds.isNotEmpty,
                onTap: () => onTap(entry),
                onLongPress: () => onLongPress(entry),
              ),
          ],
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group});

  final LedgerDayGroup group;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey(
        'ledger-day-${group.date.year}-${group.date.month}-${group.date.day}',
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      color: colors.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${group.date.month}月${group.date.day}日 '
              '${weekdays[group.date.weekday - 1]}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(
            '收入 ${MoneyParser.formatSignedCnyMinor(group.totals.incomeMinor)}  '
            '支出 ${MoneyParser.formatSignedCnyMinor(group.totals.expenseMinor)}',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MonthlyOverviewCard extends StatelessWidget {
  const _MonthlyOverviewCard({required this.overview});

  final MonthlyOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本月概览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            Row(
              children: [
                _OverviewValue(label: '收入', valueMinor: overview.incomeMinor),
                _OverviewValue(label: '支出', valueMinor: overview.expenseMinor),
                _OverviewValue(label: '结余', valueMinor: overview.balanceMinor),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.savings_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('本月预算'),
                  Spacer(),
                  Text('未设置'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewValue extends StatelessWidget {
  const _OverviewValue({required this.label, required this.valueMinor});

  final String label;
  final int valueMinor;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            MoneyParser.formatSignedCnyMinor(valueMinor),
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({
    required this.entry,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  final LedgerEntry entry;
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final transaction = entry.transaction;
    final isExpense = transaction.type == LedgerTransactionType.expense.value;
    final localTime = OccurrenceTime.restoreWallTime(
      utcMilliseconds: transaction.occurredAt,
      timezoneOffsetMinutes: transaction.timezoneOffsetMinutes,
    );
    return ListTile(
      key: ValueKey('ledger-entry-${transaction.id}'),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      onTap: onTap,
      onLongPress: onLongPress,
      leading: selectionMode
          ? Checkbox(value: selected, onChanged: (_) => onTap())
          : CircleAvatar(
              child: SvgPicture.asset(
                entry.subcategory.iconAsset,
                key: ValueKey('ledger-subcategory-icon-${transaction.id}'),
                width: 24,
                height: 24,
                colorFilter: ColorFilter.mode(
                  Theme.of(context).colorScheme.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
      title: Text(transaction.content),
      subtitle: Text(
        '${entry.category.name} · ${entry.subcategory.name} · ${entry.account.name}\n'
        '${_two(localTime.hour)}:${_two(localTime.minute)}',
      ),
      isThreeLine: true,
      trailing: Text(
        '${isExpense ? '-' : '+'}${MoneyParser.formatCnyMinor(transaction.amountMinor)}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: isExpense
              ? Theme.of(context).colorScheme.error
              : Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text('还没有账目', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('点击“记一笔”开始记录'),
        ],
      ),
    ),
  );
}

class _LedgerError extends StatelessWidget {
  const _LedgerError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: onRetry, child: const Text('重试')),
      ],
    ),
  );
}

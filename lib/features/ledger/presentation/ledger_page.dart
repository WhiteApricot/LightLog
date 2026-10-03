import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../core/occurrence_time.dart';
import '../../entry/presentation/entry_page.dart';
import '../../entry/presentation/transaction_editor_page.dart';
import '../domain/ledger_models.dart';

class LedgerPage extends ConsumerWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(ledgerEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('轻记')),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LedgerError(
          message: '账本加载失败：$error',
          onRetry: () => ref.invalidate(ledgerEntriesProvider),
        ),
        data: (items) => _LedgerBody(
          items: items,
          onEdit: (entry) => _openEditor(context, entry),
          onDelete: (entry) => _delete(context, ref, entry),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => const EntryPage())),
        icon: const Icon(Icons.add),
        label: const Text('记一笔'),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, LedgerEntry? entry) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TransactionEditorPage(entry: entry)),
    );
  }

  Future<bool> _delete(
    BuildContext context,
    WidgetRef ref,
    LedgerEntry entry,
  ) async {
    try {
      final repository = ref.read(ledgerRepositoryProvider);
      await repository.softDelete(entry.transaction.id);
      if (!context.mounted) return true;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除“${entry.transaction.content}”'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              try {
                await repository.restore(entry.transaction.id);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('撤销失败：$error')));
                }
              }
            },
          ),
        ),
      );
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
      return false;
    }
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<LedgerEntry> items;
  final ValueChanged<LedgerEntry> onEdit;
  final Future<bool> Function(LedgerEntry) onDelete;

  @override
  Widget build(BuildContext context) {
    final overview = MonthlyOverview.fromEntries(items);
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
          for (final entry in items) ...[
            _LedgerTile(
              entry: entry,
              onEdit: () => onEdit(entry),
              onDelete: () => onDelete(entry),
            ),
            const Divider(height: 1),
          ],
      ],
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
    required this.onEdit,
    required this.onDelete,
  });

  final LedgerEntry entry;
  final VoidCallback onEdit;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final transaction = entry.transaction;
    final isExpense = transaction.type == LedgerTransactionType.expense.value;
    final localTime = OccurrenceTime.restoreWallTime(
      utcMilliseconds: transaction.occurredAt,
      timezoneOffsetMinutes: transaction.timezoneOffsetMinutes,
    );
    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => onDelete(),
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
      child: ListTile(
        onTap: onEdit,
        leading: CircleAvatar(
          child: SvgPicture.asset(
            entry.subcategory.iconAsset,
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
          '${localTime.month}月${localTime.day}日 ${_two(localTime.hour)}:${_two(localTime.minute)}',
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

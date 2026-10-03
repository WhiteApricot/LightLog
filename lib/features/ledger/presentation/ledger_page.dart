import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../core/occurrence_time.dart';
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
        data: (items) => items.isEmpty
            ? const _EmptyLedger()
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _LedgerTile(
                  entry: items[index],
                  onEdit: () => _openEditor(context, items[index]),
                  onDelete: () => _delete(context, ref, items[index]),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
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
          child: Icon(isExpense ? Icons.arrow_upward : Icons.arrow_downward),
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

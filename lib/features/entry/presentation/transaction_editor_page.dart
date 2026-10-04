import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../core/occurrence_time.dart';
import '../../../data/database/database.dart';
import '../../ledger/domain/ledger_models.dart';
import '../../recognition/domain/recognition_models.dart';
import 'account_picker.dart';
import 'category_picker.dart';
import 'wheel_time_picker.dart';

class TransactionEditorPage extends ConsumerStatefulWidget {
  const TransactionEditorPage({
    super.key,
    this.entry,
    this.initialDraft,
    this.contextMessage,
    this.evidence = const [],
    this.showSmartInput = false,
  }) : assert(entry == null || initialDraft == null);

  final LedgerEntry? entry;
  final TransactionDraft? initialDraft;
  final String? contextMessage;
  final List<String> evidence;
  final bool showSmartInput;

  @override
  ConsumerState<TransactionEditorPage> createState() =>
      _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _contentController;
  late final TextEditingController _noteController;
  late final TextEditingController _smartInputController;
  late LedgerTransactionType _type;
  late DateTime _occurredAtLocal;
  late int _timezoneOffsetMinutes;
  String? _categoryId;
  String? _subcategoryId;
  String? _accountId;
  late String _source;
  double? _confidence;
  bool _saving = false;
  bool _categoryValidationRequested = false;
  RecognitionCandidate? _smartCandidate;

  @override
  void initState() {
    super.initState();
    final transaction = widget.entry?.transaction;
    final initialDraft = widget.initialDraft;
    _type = transaction != null
        ? LedgerTransactionType.fromValue(transaction.type)
        : initialDraft?.type ?? LedgerTransactionType.expense;
    _amountController = TextEditingController(
      text: transaction != null
          ? MoneyParser.editableCny(transaction.amountMinor)
          : initialDraft == null
          ? ''
          : MoneyParser.editableCny(initialDraft.amountMinor),
    );
    _contentController = TextEditingController(
      text: transaction?.content ?? initialDraft?.content,
    );
    _noteController = TextEditingController(
      text: transaction?.note ?? initialDraft?.note,
    );
    _smartInputController = TextEditingController();
    if (transaction != null) {
      _occurredAtLocal = OccurrenceTime.restoreWallTime(
        utcMilliseconds: transaction.occurredAt,
        timezoneOffsetMinutes: transaction.timezoneOffsetMinutes,
      );
      _timezoneOffsetMinutes = transaction.timezoneOffsetMinutes;
    } else if (initialDraft != null) {
      _occurredAtLocal = initialDraft.occurredAtLocal;
      _timezoneOffsetMinutes = initialDraft.timezoneOffsetMinutes;
    } else {
      final now = DateTime.now();
      _occurredAtLocal = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      );
      _timezoneOffsetMinutes = _occurredAtLocal.timeZoneOffset.inMinutes;
    }
    _categoryId = transaction?.categoryId ?? initialDraft?.categoryId;
    _subcategoryId = transaction?.subcategoryId ?? initialDraft?.subcategoryId;
    _accountId = transaction?.accountId ?? initialDraft?.accountId;
    _source = transaction?.source ?? initialDraft?.source ?? 'manual';
    _confidence = transaction?.confidence ?? initialDraft?.confidence;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _contentController.dispose();
    _noteController.dispose();
    _smartInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (widget.entry != null)
            IconButton(
              key: const ValueKey('transaction-delete-button'),
              tooltip: '删除账目',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(message: '分类加载失败：$error'),
        data: (categoryItems) => accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _LoadError(message: '账户加载失败：$error'),
          data: (accountItems) => _buildForm(categoryItems, accountItems),
        ),
      ),
    );
  }

  Widget _buildForm(List<Category> categories, List<Account> accounts) {
    final typedCategories = categories
        .where((item) => item.type == _type.value)
        .toList(growable: false);
    final parentCategories = typedCategories
        .where((item) => item.parentId == null)
        .toList(growable: false);
    if (!parentCategories.any((item) => item.id == _categoryId)) {
      _categoryId = parentCategories.firstOrNull?.id;
    }
    if (!typedCategories.any(
      (item) => item.id == _subcategoryId && item.parentId == _categoryId,
    )) {
      _subcategoryId = null;
    }
    if (!accounts.any((item) => item.id == _accountId)) {
      _accountId = accounts.firstOrNull?.id;
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.contextMessage != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contextMessage!,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    for (final item in widget.evidence) ...[
                      const SizedBox(height: 6),
                      Text('• $item'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (widget.showSmartInput && widget.entry == null) ...[
            _buildSmartInput(categories),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            Text('手动记账', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
          ],
          SegmentedButton<LedgerTransactionType>(
            segments: const [
              ButtonSegment(
                value: LedgerTransactionType.expense,
                label: Text('支出'),
                icon: Icon(Icons.arrow_upward),
              ),
              ButtonSegment(
                value: LedgerTransactionType.income,
                label: Text('收入'),
                icon: Icon(Icons.arrow_downward),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (selection) => setState(() {
              _type = selection.single;
              _categoryId = null;
              _subcategoryId = null;
            }),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _amountController,
            autofocus:
                widget.entry == null &&
                widget.initialDraft == null &&
                !widget.showSmartInput,
            decoration: const InputDecoration(
              labelText: '金额（元）',
              prefixText: '¥ ',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            validator: (value) => MoneyParser.parseCnyMinor(value ?? '') == null
                ? '请输入大于 0、最多两位小数的金额'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contentController,
            maxLength: 120,
            decoration: const InputDecoration(
              labelText: '内容 / 商户',
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? '请输入内容或商户' : null,
          ),
          const SizedBox(height: 4),
          CategoryPicker(
            categories: typedCategories,
            selectedParentId: _categoryId,
            selectedChildId: _subcategoryId,
            errorText: _categoryValidationRequested && _categoryId == null
                ? '请选择一级分类'
                : _categoryValidationRequested && _subcategoryId == null
                ? '请选择二级分类'
                : null,
            onParentSelected: (category) => setState(() {
              if (_categoryId != category.id) {
                _categoryId = category.id;
                _subcategoryId = null;
              }
            }),
            onChildSelected: (category) =>
                setState(() => _subcategoryId = category.id),
          ),
          const SizedBox(height: 12),
          AccountPicker(
            accounts: accounts,
            selectedId: _accountId,
            onSelected: (account) => setState(() => _accountId = account.id),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('发生日期'),
            subtitle: Text(_formatDate(_occurredAtLocal)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('发生时间'),
            subtitle: Text(_formatTime(_occurredAtLocal)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickTime,
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const ValueKey('transaction-save-button'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartInput(List<Category> categories) {
    final candidate = _smartCandidate;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('智能文字记账', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('unified-smart-input'),
              controller: _smartInputController,
              autofocus: true,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: '例如：二食堂 15',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.auto_awesome),
              ),
              onChanged: (_) {
                if (_smartCandidate != null) {
                  setState(() => _smartCandidate = null);
                }
              },
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: const ValueKey('unified-smart-parse-button'),
                onPressed: () => _parseSmartInput(categories),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('识别'),
              ),
            ),
            if (candidate != null) ...[
              const SizedBox(height: 8),
              if (candidate.isComplete)
                _SmartCandidateResult(
                  candidate: candidate,
                  saving: _saving,
                  onConfirm: _save,
                )
              else
                for (final issue in candidate.issues)
                  Text(
                    '• $issue',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  void _parseSmartInput(List<Category> categories) {
    if (_smartInputController.text.trim().isEmpty) {
      setState(() => _smartCandidate = null);
      return;
    }
    final candidate = ref
        .read(textEntryParserProvider)
        .parse(
          rawText: _smartInputController.text,
          categories: categories,
          now: DateTime.now(),
        );
    setState(() {
      _smartCandidate = candidate;
      if (!candidate.isComplete) return;
      final draft = candidate.draft;
      _type = draft.type!;
      _amountController.text = MoneyParser.editableCny(draft.amountMinor!);
      _contentController.text = draft.content!;
      _occurredAtLocal = draft.occurredAtLocal!;
      _timezoneOffsetMinutes = draft.timezoneOffsetMinutes!;
      _categoryId = candidate.categoryId;
      _subcategoryId = candidate.subcategoryId;
      _source = 'text';
      _confidence = candidate.confidence;
      _categoryValidationRequested = false;
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _occurredAtLocal,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected == null) return;
    setState(() {
      _occurredAtLocal = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _occurredAtLocal.hour,
        _occurredAtLocal.minute,
        _occurredAtLocal.second,
        _occurredAtLocal.millisecond,
      );
      _updateOffsetForNewEntry();
    });
  }

  Future<void> _pickTime() async {
    final selected = await showWheelTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAtLocal),
    );
    if (selected == null) return;
    setState(() {
      _occurredAtLocal = DateTime(
        _occurredAtLocal.year,
        _occurredAtLocal.month,
        _occurredAtLocal.day,
        selected.hour,
        selected.minute,
      );
      _updateOffsetForNewEntry();
    });
  }

  void _updateOffsetForNewEntry() {
    if (widget.entry == null) {
      _timezoneOffsetMinutes = _occurredAtLocal.timeZoneOffset.inMinutes;
    }
  }

  Future<void> _save() async {
    final fieldsValid = _formKey.currentState!.validate();
    if (_categoryId == null || _subcategoryId == null) {
      setState(() => _categoryValidationRequested = true);
      return;
    }
    if (!fieldsValid) return;
    setState(() => _saving = true);
    try {
      final draft = TransactionDraft(
        type: _type,
        categoryId: _categoryId!,
        subcategoryId: _subcategoryId!,
        content: _contentController.text,
        note: _noteController.text,
        amountMinor: MoneyParser.parseCnyMinor(_amountController.text)!,
        occurredAtLocal: _occurredAtLocal,
        timezoneOffsetMinutes: _timezoneOffsetMinutes,
        accountId: _accountId!,
        source: _source,
        confidence: _confidence,
      );
      final repository = ref.read(ledgerRepositoryProvider);
      if (widget.entry == null) {
        await repository.create(draft);
      } else {
        await repository.update(widget.entry!.transaction.id, draft);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    if (entry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这笔账目？'),
        content: Text('“${entry.transaction.content}”将移入已删除状态，可立即撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-transaction-delete'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final repository = ref.read(ledgerRepositoryProvider);
    try {
      await repository.softDelete(entry.transaction.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除“${entry.transaction.content}”'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              try {
                await repository.restore(entry.transaction.id);
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
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
        setState(() => _saving = false);
      }
    }
  }

  static String _formatDate(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  String get _title {
    if (widget.entry != null) return '编辑账目';
    if (widget.initialDraft != null) return '确认文字账目';
    if (widget.showSmartInput) return '记一笔';
    return '新增账目';
  }

  static String _formatTime(DateTime value) =>
      '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _SmartCandidateResult extends StatelessWidget {
  const _SmartCandidateResult({
    required this.candidate,
    required this.saving,
    required this.onConfirm,
  });

  final RecognitionCandidate candidate;
  final bool saving;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final draft = candidate.draft;
    final occurredAt = draft.occurredAtLocal!;
    return Container(
      key: const ValueKey('unified-smart-success'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('识别结果', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _CandidateLine(
            icon: Icons.category_outlined,
            label: '自动分类',
            value: '${candidate.categoryName} · ${candidate.subcategoryName}',
          ),
          _CandidateLine(
            icon: Icons.schedule_outlined,
            label: '时间',
            value:
                '${occurredAt.month}月${occurredAt.day}日 '
                '${_two(occurredAt.hour)}:${_two(occurredAt.minute)}',
          ),
          _CandidateLine(
            icon: Icons.payments_outlined,
            label: '金额',
            value: MoneyParser.formatCnyMinor(draft.amountMinor!),
          ),
          _CandidateLine(
            icon: Icons.storefront_outlined,
            label: '内容 / 商户',
            value: draft.content!,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('smart-confirm-transaction-button'),
              onPressed: saving ? null : onConfirm,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(saving ? '入账中…' : '确认入账'),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _CandidateLine extends StatelessWidget {
  const _CandidateLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 7),
        SizedBox(
          width: 70,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(child: Text(message));
}

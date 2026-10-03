import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../core/occurrence_time.dart';
import '../../../data/database/database.dart';
import '../../ledger/domain/ledger_models.dart';
import 'category_picker.dart';
import 'wheel_time_picker.dart';

class TransactionEditorPage extends ConsumerStatefulWidget {
  const TransactionEditorPage({
    super.key,
    this.entry,
    this.initialDraft,
    this.contextMessage,
    this.evidence = const [],
  }) : assert(entry == null || initialDraft == null);

  final LedgerEntry? entry;
  final TransactionDraft? initialDraft;
  final String? contextMessage;
  final List<String> evidence;

  @override
  ConsumerState<TransactionEditorPage> createState() =>
      _TransactionEditorPageState();
}

class _TransactionEditorPageState extends ConsumerState<TransactionEditorPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _contentController;
  late final TextEditingController _noteController;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
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
    final parentCategories = categories
        .where((item) => item.parentId == null && item.type == _type.value)
        .toList(growable: false);
    if (!parentCategories.any((item) => item.id == _categoryId)) {
      _categoryId = parentCategories.firstOrNull?.id;
    }
    final childCategories = categories
        .where(
          (item) => item.parentId == _categoryId && item.type == _type.value,
        )
        .toList(growable: false);
    if (!childCategories.any((item) => item.id == _subcategoryId)) {
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
            autofocus: widget.entry == null && widget.initialDraft == null,
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
            title: '一级分类',
            categories: parentCategories,
            selectedId: _categoryId,
            errorText: _categoryValidationRequested && _categoryId == null
                ? '请选择一级分类'
                : null,
            onSelected: (category) => setState(() {
              if (_categoryId != category.id) {
                _categoryId = category.id;
                _subcategoryId = null;
              }
            }),
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: CategoryPicker(
              key: ValueKey('subcategory-$_categoryId'),
              title: '二级分类',
              categories: childCategories,
              selectedId: _subcategoryId,
              rows: 1,
              errorText: _categoryValidationRequested && _subcategoryId == null
                  ? '请选择二级分类'
                  : null,
              onSelected: (category) => setState(() {
                _subcategoryId = category.id;
              }),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(
              labelText: '账户 / 支付方式',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final item in accounts)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) => setState(() => _accountId = value),
            validator: (value) => value == null ? '请选择账户' : null,
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

  static String _formatDate(DateTime value) =>
      '${value.year}年${value.month}月${value.day}日';

  String get _title {
    if (widget.entry != null) return '编辑账目';
    if (widget.initialDraft != null) return '确认文字账目';
    return '新增账目';
  }

  static String _formatTime(DateTime value) =>
      '${_twoDigits(value.hour)}:${_twoDigits(value.minute)}';

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Center(child: Text(message));
}

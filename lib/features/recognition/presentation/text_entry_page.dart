import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/money.dart';
import '../../../data/database/database.dart';
import '../../entry/presentation/transaction_editor_page.dart';
import '../domain/recognition_models.dart';

class TextEntryPage extends ConsumerStatefulWidget {
  const TextEntryPage({super.key});

  @override
  ConsumerState<TextEntryPage> createState() => _TextEntryPageState();
}

class _TextEntryPageState extends ConsumerState<TextEntryPage> {
  final _controller = TextEditingController();
  RecognitionCandidate? _candidate;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('文字记账')),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('分类加载失败：$error')),
        data: (categoryItems) => accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('账户加载失败：$error')),
          data: (accountItems) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                key: const ValueKey('text-entry-input'),
                controller: _controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '描述这笔账',
                  hintText: '例如：二食堂 15',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _parse(categoryItems),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('text-entry-parse-button'),
                onPressed: () => _parse(categoryItems),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('解析'),
              ),
              if (_candidate case final candidate?) ...[
                const SizedBox(height: 20),
                _CandidateCard(
                  candidate: candidate,
                  canContinue: candidate.isComplete && accountItems.isNotEmpty,
                  onContinue: () => _continue(candidate, accountItems.first.id),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _parse(List<Category> categories) {
    setState(() {
      _candidate = ref
          .read(textEntryParserProvider)
          .parse(
            rawText: _controller.text,
            categories: categories,
            now: DateTime.now(),
          );
    });
  }

  Future<void> _continue(
    RecognitionCandidate candidate,
    String accountId,
  ) async {
    final draft = candidate.toTransactionDraft(accountId: accountId);
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialDraft: draft,
          contextMessage: '请确认或修改识别结果后保存',
          evidence: [for (final item in candidate.evidence) item.description],
        ),
      ),
    );
    if (saved == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.candidate,
    required this.canContinue,
    required this.onContinue,
  });

  final RecognitionCandidate candidate;
  final bool canContinue;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final draft = candidate.draft;
    final occurredAt = draft.occurredAtLocal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('候选结果', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _line('类型', draft.type?.label ?? '未识别'),
            _line(
              '金额',
              draft.amountMinor == null
                  ? '未识别'
                  : MoneyParser.formatCnyMinor(draft.amountMinor!),
            ),
            _line('内容', draft.content ?? '未识别'),
            _line(
              '分类',
              candidate.categoryName == null
                  ? '未识别'
                  : '${candidate.categoryName} · ${candidate.subcategoryName}',
            ),
            _line(
              '时间',
              occurredAt == null
                  ? '未识别'
                  : '${occurredAt.year}-${_two(occurredAt.month)}-${_two(occurredAt.day)} '
                        '${_two(occurredAt.hour)}:${_two(occurredAt.minute)}',
            ),
            _line('置信度', '${(candidate.confidence * 100).round()}%'),
            const SizedBox(height: 8),
            for (final item in candidate.evidence)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${item.description}'),
              ),
            for (final issue in candidate.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $issue',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('text-entry-confirm-button'),
                onPressed: canContinue ? onContinue : null,
                child: const Text('确认并继续'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text('$label：$value'),
  );

  static String _two(int value) => value.toString().padLeft(2, '0');
}

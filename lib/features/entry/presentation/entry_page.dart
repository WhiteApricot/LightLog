import 'package:flutter/material.dart';

import '../../recognition/presentation/text_entry_page.dart';
import 'transaction_editor_page.dart';

class EntryPage extends StatelessWidget {
  const EntryPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('记一笔')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('选择录入方式', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _EntryModeCard(
          key: const ValueKey('manual-entry-mode'),
          icon: Icons.edit_note,
          title: '手动记账',
          description: '直接填写金额、分类、时间和账户',
          onTap: () => _openManual(context),
        ),
        const SizedBox(height: 12),
        _EntryModeCard(
          key: const ValueKey('text-entry-mode'),
          icon: Icons.auto_awesome,
          title: '智能文字记账',
          description: '输入“二食堂 15”等描述，识别后确认保存',
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const TextEntryPage()),
          ),
        ),
      ],
    ),
  );

  Future<void> _openManual(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TransactionEditorPage()),
    );
    if (saved == true && context.mounted) Navigator.of(context).pop();
  }
}

class _EntryModeCard extends StatelessWidget {
  const _EntryModeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(radius: 25, child: Icon(icon, size: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(description),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

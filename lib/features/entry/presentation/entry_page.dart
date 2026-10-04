import 'package:flutter/material.dart';

import 'transaction_editor_page.dart';

class EntryPage extends StatelessWidget {
  const EntryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const TransactionEditorPage(showSmartInput: true);
}

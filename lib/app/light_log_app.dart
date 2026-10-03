import 'package:flutter/material.dart';

import '../features/ledger/presentation/ledger_page.dart';

class LightLogApp extends StatelessWidget {
  const LightLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '轻记',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F6F52)),
        useMaterial3: true,
      ),
      home: const LedgerPage(),
    );
  }
}

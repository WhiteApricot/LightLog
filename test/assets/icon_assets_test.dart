import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/data/database/seed_data.dart';

void main() {
  test('every default category has a distinct lightweight 24px SVG', () {
    final paths = defaultCategories.map((item) => item.iconAsset).toList();
    expect(paths.toSet(), hasLength(defaultCategories.length));

    final signatures = <String, String>{};
    for (final category in defaultCategories) {
      final file = File(category.iconAsset);
      expect(file.existsSync(), isTrue, reason: '缺少 ${category.iconAsset}');
      expect(file.lengthSync(), lessThan(2048), reason: category.iconAsset);
      final source = file.readAsStringSync();
      expect(source, contains('viewBox="0 0 24 24"'));
      final signature = _geometrySignature(source);
      expect(
        signatures[signature],
        isNull,
        reason: '${category.iconAsset} 与 ${signatures[signature]} 的实际图形重复',
      );
      signatures[signature] = category.iconAsset;
    }
  });

  test('every default account has a distinct lightweight 24px SVG', () {
    final paths = defaultAccounts.map((item) => item.iconAsset).toList();
    expect(paths.toSet(), hasLength(defaultAccounts.length));

    final signatures = <String>{};
    for (final account in defaultAccounts) {
      final file = File(account.iconAsset);
      expect(file.existsSync(), isTrue, reason: '缺少 ${account.iconAsset}');
      expect(file.lengthSync(), lessThan(2048), reason: account.iconAsset);
      final source = file.readAsStringSync();
      expect(source, contains('viewBox="0 0 24 24"'));
      expect(signatures.add(_geometrySignature(source)), isTrue);
    }
  });
}

String _geometrySignature(String source) => source
    .replaceAll(RegExp(r'<title>.*?</title>', dotAll: true), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

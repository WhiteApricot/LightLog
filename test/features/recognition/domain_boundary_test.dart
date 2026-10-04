import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognition domain stays pure Dart', () {
    final files = Directory('lib/features/recognition/domain')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: file.path);
      expect(source, isNot(contains('package:drift/')), reason: file.path);
      expect(source, isNot(contains("import 'dart:io'")), reason: file.path);
      expect(source, isNot(contains('/data/database/')), reason: file.path);
    }
  });

  test('App and CLI adapters reference the same production recognizer', () {
    final provider = File('lib/app/providers.dart').readAsStringSync();
    final coordinator = File(
      'lib/features/recognition/application/recognition_coordinator.dart',
    ).readAsStringSync();
    final harness = File('tools/recognition_tool_harness.dart')
        .readAsStringSync();
    for (final source in [provider, coordinator, harness]) {
      expect(source, isNot(contains('TextEntryParser')));
    }
    expect(provider, contains('LocalRecognizer'));
    expect(coordinator, contains('Recognizer'));
    expect(harness, contains('LocalRecognizer'));
  });
}

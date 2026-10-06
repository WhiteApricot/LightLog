import 'dart:convert';
import 'dart:io';

import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';
import 'package:light_log/features/recognition/domain/ngram_classifier.dart';

import '../recognition_tool_harness.dart';

void main() {
  if (File('tools/ngram/final96/production_freeze.json').existsSync()) {
    throw StateError('Production frozen: training feature export forbidden');
  }
  final h = RecognitionToolHarness(useNgram: false);
  final categories = RecognitionToolHarness.categories;
  final parents = {
    for (final c in categories)
      if (c.parentId == null) c.id: c.semanticKey,
  };
  final taxonomy = {
    for (final c in categories)
      if (c.parentId != null) c.semanticKey!: parents[c.parentId]!,
  };
  File('tools/ngram/taxonomy.json').writeAsStringSync(jsonEncode(taxonomy));
  for (final split in ['train', 'dev']) {
    final rows = File('tools/ngram/data/ngram_${split}_v2.jsonl')
        .readAsLinesSync();
    final out = File('tools/ngram/${split}_pipeline.jsonl')
        .openSync(mode: FileMode.write);
    for (final line in rows) {
      final row = jsonDecode(line) as Map;
      final raw = row['text'] as String;
      final original = h.recognize(raw, now: DateTime(2026, 10, 5, 12));
      final text = original.draft.amountMinor == null ? '$raw 37' : raw;
      h.recognizer.recognize(
        RecognitionInput(
          rawText: text,
          nowLocal: DateTime(2026, 10, 5, 12),
          timezoneOffsetMinutes: 480,
          activeCategories: categories,
        ),
        onSemanticDecision: (d, t, eligible, meal) {
          out.writeStringSync(
            '${jsonEncode({'id': row['id'], 'text': text, 'semanticKey': d.semanticKey, 'confidence': d.confidence, 'level': const EvidenceFusion().statisticalLevel(d), 'type': t.type?.value, 'defaultType': t.isDefault, 'typeConflict': t.hasConflict, 'eligible': eligible, 'meal': meal != null, 'features': NgramClassifier.structuredFeatures(t, d.winningEvidence, taxonomy)})}\n',
          );
        },
      );
    }
    out.closeSync();
    stdout.writeln('$split pipeline exported: ${rows.length}');
  }
}

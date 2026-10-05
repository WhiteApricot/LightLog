import 'dart:convert';
import 'dart:io';

import 'package:light_log/features/recognition/domain/evidence_fusion.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

import '../recognition_tool_harness.dart';

void main() {
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
            '${jsonEncode({
              'id': row['id'],
              'text': text,
              'semanticKey': d.semanticKey,
              'confidence': d.confidence,
              'level': const EvidenceFusion().statisticalLevel(d),
              'type': t.type?.value,
              'defaultType': t.isDefault,
              'typeConflict': t.hasConflict,
              'eligible': eligible,
              'meal': meal != null,
              'features': [
                'type:${t.type?.value}',
                'direction:${t.isDefault ? 'default' : t.type?.value}',
                for (final e in d.winningEvidence) ...['source:${e.source.name}', 'role:${e.role.name}', if (e.family != null) 'family:${e.family}', if (e.semanticKey != null) 'parent:${taxonomy[e.semanticKey]}'],
              ],
            })}\n',
          );
        },
      );
    }
    out.closeSync();
    stdout.writeln('$split pipeline exported: ${rows.length}');
  }
}

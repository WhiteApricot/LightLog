import 'dart:convert';
import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';
import 'package:light_log/features/recognition/domain/normalization.dart';

void main() {
  final validSemantics = defaultCategories
      .map((item) => item.semanticKey)
      .toSet();
  final merchants = _read('tools/knowledge/merchants_source.json');
  final lexicon = _read('tools/knowledge/category_lexicon_source.json');
  final aliases = <String, String>{};
  final canonicalNames = <String>{};

  for (final raw in merchants['records']! as List<Object?>) {
    final item = raw! as Map<String, Object?>;
    final canonical = item['canonicalName']! as String;
    final primary = item['primarySemanticKey']! as String;
    final semantic = item['semanticKey']! as String;
    final confidence = (item['confidence']! as num).toDouble();
    if (!canonicalNames.add(_normalize(canonical))) {
      throw FormatException('重复 canonicalName: $canonical');
    }
    if (!validSemantics.contains(primary) ||
        !validSemantics.contains(semantic)) {
      throw FormatException('$canonical 使用无效 taxonomy: $primary / $semantic');
    }
    if (confidence < 0.70 || confidence > 0.99) {
      throw FormatException('$canonical confidence 超出 0.70..0.99');
    }
    for (final alias in <String>[
      canonical,
      ...(item['aliases']! as List<Object?>).cast<String>(),
    ]) {
      final key = _normalize(alias);
      if (key.isEmpty) throw FormatException('$canonical 存在空 alias');
      final previous = aliases[key];
      if (previous != null && previous != canonical) {
        throw FormatException('alias 冲突: $alias -> $previous / $canonical');
      }
      aliases[key] = canonical;
    }
  }

  final terms = <String, String>{};
  for (final raw in lexicon['entries']! as List<Object?>) {
    final item = raw! as Map<String, Object?>;
    final semantic = item['semanticKey']! as String;
    final score = (item['score']! as num).toDouble();
    if (!validSemantics.contains(semantic)) {
      throw FormatException('词典使用无效 taxonomy: $semantic');
    }
    if (score < 0.40 || score > 0.90) {
      throw FormatException('$semantic score 超出 0.40..0.90');
    }
    for (final term in <String>[
      ...(item['keywords']! as List<Object?>).cast<String>(),
      ...(item['aliases'] as List<Object?>? ?? const []).cast<String>(),
    ]) {
      final key = _normalize(term);
      final previous = terms[key];
      if (previous != null && previous != semantic) {
        throw FormatException('词典词冲突: $term -> $previous / $semantic');
      }
      terms[key] = semantic;
    }
  }

  Directory('assets/knowledge').createSync(recursive: true);
  _write('assets/knowledge/merchants.json', merchants);
  _write('assets/knowledge/category_lexicon.json', lexicon);
  stdout.writeln(
    'validated ${(merchants['records']! as List).length} merchants, '
    '${aliases.length} merchant aliases, '
    '${(lexicon['entries']! as List).length} lexicon entries, ${terms.length} terms',
  );
}

Map<String, Object?> _read(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

void _write(String path, Map<String, Object?> value) =>
    File(path).writeAsStringSync(jsonEncode(value));

String _normalize(String value) => RecognitionNormalizer.indexKey(value);

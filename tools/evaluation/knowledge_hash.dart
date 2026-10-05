import 'dart:io';

const recognitionKnowledgePaths = [
  'assets/knowledge/merchants.json',
  'assets/knowledge/category_lexicon.json',
  'assets/knowledge/lexical_families.json',
  'assets/knowledge/composition_rules.json',
];

/// Stable FNV-1a fingerprint of all four ordered production knowledge assets.
String knowledgeHash({List<String> paths = recognitionKnowledgePaths}) {
  var hash = 0x811c9dc5;
  for (final path in paths) {
    for (final byte in File(path).readAsBytesSync()) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

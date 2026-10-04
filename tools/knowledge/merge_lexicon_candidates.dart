import 'dart:convert';
import 'dart:io';

const _sourceId = 'phase3CandidateLexiconV1';

void main(List<String> args) {
  final options = _options(args);
  final reviewPath = options['review'];
  final targetPath = options['target'];
  if (reviewPath == null || targetPath == null) {
    throw ArgumentError(
      'Usage: dart tools/knowledge/merge_lexicon_candidates.dart '
      '--review <review.json> --target <lexicon_expansion_source.json>',
    );
  }
  final review = _read(reviewPath);
  if (review['sourceId'] != _sourceId) {
    throw StateError('Unexpected candidate review sourceId.');
  }
  final target = _read(targetPath);
  final existing = (target['entries']! as List)
      .cast<Map<String, Object?>>()
      .where((entry) => entry['sourceId'] != _sourceId)
      .toList();
  final accepted = (review['acceptedGroups']! as List)
      .cast<Map<String, Object?>>();
  if (accepted.isEmpty) throw StateError('Review contains no accepted groups.');
  final merged = <String, Object?>{
    ...target,
    'entries': [
      ...existing,
      for (final entry in accepted) {...entry, 'sourceId': _sourceId},
    ],
  };
  File(targetPath).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(merged)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'sourceId': _sourceId,
      'retainedEntries': existing.length,
      'mergedEntries': accepted.length,
      'totalEntries': existing.length + accepted.length,
    }),
  );
}

Map<String, String> _options(List<String> args) {
  final result = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--review' || argument == '--target') {
      if (index + 1 >= args.length) {
        throw ArgumentError('Missing value for $argument');
      }
      result[argument.substring(2)] = args[++index];
    }
  }
  return result;
}

Map<String, Object?> _read(String path) => (jsonDecode(
  File(path).readAsStringSync().replaceFirst('\uFEFF', ''),
) as Map).cast<String, Object?>();

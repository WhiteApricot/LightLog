import 'package:flutter/services.dart';

import '../domain/knowledge_models.dart';
import 'knowledge_decoder.dart';

class KnowledgeLoader {
  const KnowledgeLoader(this.bundle);

  final AssetBundle bundle;

  Future<KnowledgeCatalog> load() async {
    final values = await Future.wait([
      bundle.loadString('assets/knowledge/merchants.json'),
      bundle.loadString('assets/knowledge/category_lexicon.json'),
    ]);
    return const KnowledgeDecoder().decode(
      entitiesJson: values[0],
      lexiconJson: values[1],
    );
  }
}

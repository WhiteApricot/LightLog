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
      bundle.loadString('assets/knowledge/lexical_families.json'),
      bundle.loadString('assets/knowledge/composition_rules.json'),
    ]);
    return const KnowledgeDecoder().decode(
      entitiesJson: values[0],
      lexiconJson: values[1],
      lexicalFamiliesJson: values[2],
      compositionRulesJson: values[3],
    );
  }
}

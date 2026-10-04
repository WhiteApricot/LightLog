import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:light_log/features/recognition/data/knowledge_loader.dart';
import 'package:light_log/features/recognition/domain/entity_matcher.dart';
import 'package:light_log/features/recognition/domain/lexicon_matcher.dart';
import 'package:light_log/features/recognition/domain/recognition_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('packaged knowledge assets load and build runtime indexes', () async {
    final knowledge = await KnowledgeLoader(rootBundle).load();

    final merchant = EntityMatcher(knowledge)
        .evidence(EntityMatcher(knowledge).match('starbucks'))
        .first;
    final lexicon = LexiconMatcher(knowledge).match('幸福大药房');
    expect(merchant.semanticKey, 'expense.food.drink');
    expect(merchant.source, RecognitionEvidenceSource.entityKnowledge);
    expect(
      lexicon.map((item) => item.semanticKey),
      contains('expense.medical.medicine'),
    );
  });
}

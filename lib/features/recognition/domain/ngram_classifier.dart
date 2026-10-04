import 'recognition_models.dart';

abstract interface class NgramClassifier {
  List<RecognitionEvidence> classify({
    required String normalizedText,
    required String normalizedMerchant,
  });
}

class DisabledNgramClassifier implements NgramClassifier {
  const DisabledNgramClassifier();

  @override
  List<RecognitionEvidence> classify({
    required String normalizedText,
    required String normalizedMerchant,
  }) => const [];
}

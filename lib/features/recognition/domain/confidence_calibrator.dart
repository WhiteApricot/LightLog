import 'recognition_models.dart';

class ConfidenceCalibrator {
  const ConfidenceCalibrator();

  double overall({
    required FieldConfidence fields,
    required Set<RecognitionIssueCode> issues,
  }) {
    var value = [
      fields.amount,
      fields.type,
      fields.category,
      fields.content,
    ].reduce((left, right) => left < right ? left : right);
    if (issues.contains(RecognitionIssueCode.categoryAmbiguous) ||
        issues.contains(RecognitionIssueCode.typeConflict)) {
      value = value.clamp(0, 0.64);
    }
    if (issues.any(_critical)) value = value.clamp(0, 0.49);
    return value.clamp(0, 0.99);
  }

  static bool _critical(RecognitionIssueCode code) => switch (code) {
    RecognitionIssueCode.emptyInput ||
    RecognitionIssueCode.amountUnrecognized ||
    RecognitionIssueCode.ambiguousAmount ||
    RecognitionIssueCode.contentUnrecognized ||
    RecognitionIssueCode.typeLowConfidence ||
    RecognitionIssueCode.categoryLowConfidence ||
    RecognitionIssueCode.categoryMappingMissing ||
    RecognitionIssueCode.ambiguousWeekday ||
    RecognitionIssueCode.transactionNotCompleted ||
    RecognitionIssueCode.transactionCancelled ||
    RecognitionIssueCode.noTransactionEvidence ||
    RecognitionIssueCode.relatedTransactionRequired ||
    RecognitionIssueCode.multipleTransactionsDetected => true,
    RecognitionIssueCode.typeConflict ||
    RecognitionIssueCode.categoryAmbiguous => false,
  };
}

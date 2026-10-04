import 'amount_extractor.dart';
import 'content_extractor.dart';
import 'knowledge_models.dart';
import 'natural_time_parser.dart';
import 'recognition_models.dart';
import 'transaction_status_detector.dart';

class FieldExtractionResult {
  const FieldExtractionResult({
    required this.status,
    required this.time,
    required this.amountCandidates,
    required this.selectedAmount,
    required this.content,
    required this.multipleTransactionsDetected,
    required this.issueCodes,
    required this.spans,
  });

  final TransactionStatus status;
  final ParsedNaturalTime time;
  final List<AmountCandidate> amountCandidates;
  final AmountCandidate? selectedAmount;
  final ContentCandidate? content;
  final bool multipleTransactionsDetected;
  final Set<RecognitionIssueCode> issueCodes;
  final List<RecognizedSpan> spans;
}

class FieldExtractor {
  const FieldExtractor();

  static const _timeParser = NaturalTimeParser();
  static const _statusDetector = TransactionStatusDetector();
  static const _amountExtractor = AmountExtractor();
  static const _contentExtractor = ContentExtractor();

  FieldExtractionResult extract({
    required String displayText,
    required String matchingText,
    required DateTime nowLocal,
    required List<EntityMatch> entityMatches,
    required List<RecognitionEvidence> lexiconEvidence,
    required List<RecognizedSpan> entityProtectedSpans,
  }) {
    final status = _statusDetector.detect(matchingText);
    final time = _timeParser.parse(matchingText, nowLocal);
    final protected = [...time.spans, ...entityProtectedSpans];
    final amount = _amountExtractor.extract(
      matchingText,
      protectedSpans: protected,
    );
    final issueCodes = <RecognitionIssueCode>{};
    if (displayText.trim().isEmpty) {
      issueCodes.add(RecognitionIssueCode.emptyInput);
    }
    if (RegExp(r'(?<!本|上)周[一二三四五六日天]').hasMatch(matchingText)) {
      issueCodes.add(RecognitionIssueCode.ambiguousWeekday);
    }
    if (amount.candidates
        .where(
          (item) => item.role == NumericRole.amount && item.amountMinor != null,
        )
        .isEmpty) {
      issueCodes.add(RecognitionIssueCode.amountUnrecognized);
    } else if (amount.ambiguous) {
      issueCodes.add(RecognitionIssueCode.ambiguousAmount);
    }
    if (status.status == TransactionStatus.failed) {
      issueCodes.add(RecognitionIssueCode.transactionNotCompleted);
    } else if (status.status == TransactionStatus.cancelled) {
      issueCodes.add(RecognitionIssueCode.transactionCancelled);
    } else if (status.status == TransactionStatus.nonTransaction) {
      issueCodes.add(RecognitionIssueCode.noTransactionEvidence);
    } else if (status.status == TransactionStatus.refund) {
      issueCodes.add(RecognitionIssueCode.relatedTransactionRequired);
    }
    if (status.multipleTransactionsDetected) {
      issueCodes.add(RecognitionIssueCode.multipleTransactionsDetected);
    }
    final removable = [...status.spans, ...time.spans];
    final content = _contentExtractor.extract(
      displayText: displayText,
      matchingText: matchingText,
      removableSpans: removable,
      amountCandidates: amount.candidates,
      selectedAmount: amount.selected,
      entityMatches: entityMatches,
      lexiconEvidence: lexiconEvidence,
    );
    if (content == null) {
      issueCodes.add(RecognitionIssueCode.contentUnrecognized);
    }
    return FieldExtractionResult(
      status: status.status,
      time: time,
      amountCandidates: amount.candidates,
      selectedAmount: amount.selected,
      content: content,
      multipleTransactionsDetected: status.multipleTransactionsDetected,
      issueCodes: Set.unmodifiable(issueCodes),
      spans: List.unmodifiable([...removable, ...protected]),
    );
  }
}

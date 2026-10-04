import '../../ledger/domain/ledger_models.dart';
import '../domain/recognition_models.dart';

class RecognitionResultMapper {
  const RecognitionResultMapper._();

  static LedgerTransactionType ledgerType(RecognitionTransactionType type) =>
      LedgerTransactionType.fromValue(type.value);

  static TransactionDraft toTransactionDraft({
    required RecognitionResult result,
    required String accountId,
    String? note,
  }) {
    if (!result.canQuickConfirm) {
      throw StateError('识别候选不完整，不能写入账本');
    }
    final draft = result.draft;
    return TransactionDraft(
      type: ledgerType(draft.type!),
      categoryId: result.categoryId!,
      subcategoryId: result.subcategoryId!,
      content: draft.content!,
      amountMinor: draft.amountMinor!,
      occurredAtLocal: draft.occurredAtLocal!,
      timezoneOffsetMinutes: draft.timezoneOffsetMinutes!,
      accountId: accountId,
      note: note,
      source: 'text',
      confidence: result.confidence,
    );
  }
}

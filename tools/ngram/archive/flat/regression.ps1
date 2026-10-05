$ErrorActionPreference = 'Stop'
$corpora = [ordered]@{
  original190 = 'lightlog_phase3_recognition_test_cases.json'
  v2 = 'lightlog_phase3_stress_holdout_v2.json'
  v3 = 'lightlog_phase3_compositional_holdout_v3.json'
  v4 = 'lightlog_phase3_family_generalization_holdout_v4.json'
  v5 = 'lightlog_phase3_semantic_routing_holdout_v5.json'
}
foreach ($entry in $corpora.GetEnumerator()) {
  foreach ($mode in @('before', 'after')) {
    $disabled = if ($mode -eq 'before') { 'true' } else { 'false' }
    $reportPath = "tools/ngram/regression/$($entry.Key)_$mode.json"
    & dart "-DDISABLE_NGRAM=$disabled" tools/evaluation/evaluate_recognition.dart --corpus "tools/evaluation/$($entry.Value)" --report $reportPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Evaluation failed: $($entry.Key) $mode" }
    $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
    Write-Output "$($entry.Key) $mode category=$($report.categoryAccuracy) null=$($report.categoryNullCount) wrong=$($report.highConfidenceWrongPredictionCount) P2=$($report.p2SafeRejectionRate)"
  }
}
& dart tools/benchmark/benchmark_recognition.dart | Set-Content -Encoding utf8 tools/ngram/benchmark_report.json
if ($LASTEXITCODE -ne 0) { throw 'Benchmark failed' }

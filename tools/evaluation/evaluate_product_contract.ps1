# Run from repository root, only AFTER production freeze. Never reopens v6.
$ErrorActionPreference = 'Stop'
$freezePath = 'tools/evaluation/phase3_product_contract_production_freeze.json'
if (!(Test-Path -LiteralPath $freezePath)) { throw 'Production is not frozen' }
$freeze = Get-Content -LiteralPath $freezePath -Raw | ConvertFrom-Json
foreach ($entry in $freeze.sha256.PSObject.Properties) {
  $actual = (Get-FileHash -LiteralPath $entry.Name -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $entry.Value) { throw "Frozen production changed: $($entry.Name)" }
}
$reportRoot = 'tools/evaluation/reports/phase3_product_contract'
$firstRun = "$reportRoot/v6_first_run_initial.json"
if (Test-Path -LiteralPath $firstRun) { throw 'v6 first-run is immutable; the suite has already run' }
$manifest = Get-Content -LiteralPath tools/evaluation/oracle_migration_freeze.json -Raw | ConvertFrom-Json
$names = @('original190', 'v2', 'v3', 'v4', 'v5')
for ($i = 0; $i -lt $manifest.corpora.Count; $i++) {
  $corpus = $manifest.corpora[$i]
  $actual = (Get-FileHash -LiteralPath $corpus.target -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -ne $corpus.sha256) { throw "Sealed oracle changed: $($corpus.target)" }
  & dart tools/evaluation/evaluate_recognition.dart --corpus $corpus.target --report "$reportRoot/$($names[$i])_104class_final.json" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Evaluation failed: $($names[$i])" }
  Write-Output "$($names[$i]) migrated-104 evaluation saved"
}
# First access to v6 content occurs here, after the entire production is frozen.
& dart tools/evaluation/evaluate_recognition.dart --corpus lightlog_phase3_104class_generalization_v6.json --report $firstRun | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'v6 first-run failed' }
Write-Output 'v6 immutable first-run saved; no subsequent production changes permitted'

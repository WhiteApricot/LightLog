"""One-time blind acceptance, after final source/model/data hashes are verified."""
import json,hashlib,subprocess,shutil,sys
from pathlib import Path
from train import ROOT,HERE
freeze=json.loads((HERE/'final_freeze.json').read_text(encoding='utf-8'))
for group in ['productionSha256','datasetSha256']:
 for name,sha in freeze[group].items():
  if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=sha:raise SystemExit('Frozen input changed: '+name)
report=HERE/'v7_acceptance_initial.json'
if report.exists():raise SystemExit('v7 first-run is immutable')
corpus=ROOT/freeze['userCorpusPath']
manifest=dict(sourcePath=freeze['userCorpusPath'],sha256=hashlib.sha256(corpus.read_bytes()).hexdigest(),freezeSha256=hashlib.sha256((HERE/'final_freeze.json').read_bytes()).hexdigest(),purpose='Independent acceptance after final production freeze; never used for selection')
if '--normalize-red-packet-keys' in sys.argv:
 aliases={'expense.social.red_packet':'expense.social.red.packet','income.other.red_packet':'income.other.red.packet'}
 data=json.loads(corpus.read_text(encoding='utf-8-sig'));changed=[]
 for case in data['cases']:
  expected=case['expected'];key=expected.get('semanticKey')
  if key in aliases:
   expected['semanticKey']=aliases[key];changed.append(dict(id=case['id'],original=key,canonical=aliases[key]))
 normalized=HERE/'v7_evaluation_copy.json'
 normalized.write_text(json.dumps(data,ensure_ascii=False)+'\n',encoding='utf-8')
 manifest['canonicalization']=changed;manifest['evaluationCopySha256']=hashlib.sha256(normalized.read_bytes()).hexdigest();manifest['approval']='User approved the two exact naming conversions; all inputs and label meanings unchanged'
 corpus=normalized
(HERE/'v7_acceptance_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
with (HERE/'acceptance_runner.log').open('w',encoding='utf-8') as log:
 subprocess.run([shutil.which('dart') or 'dart','tools/evaluation/evaluate_recognition.dart','--corpus',str(corpus.relative_to(ROOT)),'--report',str(report.relative_to(ROOT))],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
r=json.loads(report.read_text(encoding='utf-8'));keys=['totalCases','categoryAccuracy','parentCategoryAccuracy','typeAccuracy','specificCategoryCoverage','specificCategoryAccuracy','falseFallbackRate','otherGeneralCategoryRate','childConditionalAccuracy','mealRoutingAccuracy','highConfidenceWrongPredictionCount','p2SafeRejectionRate','ordinaryValidCategoryNullCount','latencyMicroseconds','failureDecomposition','statisticalAcceptedCoverage','statisticalAcceptedAccuracy','sameParentRerankAccuracy','crossParentStatisticalAccuracy']
summary={k:r[k] for k in keys};summary['p2Count']=r['priority']['P2']['total'];summary['modelBytes']=(ROOT/'assets/knowledge/ngram.bin').stat().st_size
(HERE/'v7_acceptance_summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(summary,ensure_ascii=False))
for name,sha in freeze['productionSha256'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==sha
(HERE/'acceptance_runner.log').unlink()

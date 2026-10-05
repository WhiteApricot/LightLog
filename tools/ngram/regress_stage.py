"""Freeze first, then historical regression. Never select using these outputs."""
import json,hashlib,subprocess,sys,shutil
from pathlib import Path
from train import ROOT,HERE
stage=sys.argv[1].lower(); out=HERE/'stages'/stage
if (out/'freeze.json').exists(): raise SystemExit('Frozen stage reports are immutable; use a new report directory in a separate experiment')
out.mkdir(parents=True,exist_ok=True)
files=list((ROOT/'lib/features/recognition').rglob('*.dart'))+list((ROOT/'assets/knowledge').glob('*'))
freeze=dict(stage=stage,sha256={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()},selection='train/dev only; no historical failures inspected for selection',acceptance='v7 withheld until final production freeze; historical results are regression only')
(out/'freeze.json').write_text(json.dumps(freeze,indent=2)+'\n',encoding='utf-8')
corpora=ROOT/'tools/evaluation/corpora/phase3_104class'
manifest=json.loads((ROOT/'tools/evaluation/oracle_migration_freeze.json').read_text(encoding='utf-8'))
paths=[(x['target'], n) for x,n in zip(manifest['corpora'],['original190','v2','v3','v4','v5'])]+[(str((corpora/'lightlog_phase3_104class_generalization_v6.json').relative_to(ROOT)),'v6')]
summary={}
for path,name in paths:
 report=out/(name+'.json')
 with (out/'runner.log').open('w',encoding='utf-8') as log:
  subprocess.run([shutil.which('dart') or 'dart','tools/evaluation/evaluate_recognition.dart','--corpus',path,'--report',str(report.relative_to(ROOT))],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
 r=json.loads(report.read_text(encoding='utf-8')); summary[name]={k:r[k] for k in ['totalCases','categoryAccuracy','parentCategoryAccuracy','typeAccuracy','highConfidenceWrongPredictionCount','p2SafeRejectionRate','otherGeneralFallbackCount','otherGeneralCategoryCount','mealRoutingAccuracy','latencyMicroseconds','routingFailureBreakdown']}
 print(name,json.dumps(summary[name]),flush=True)
(out/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
(out/'runner.log').unlink()
for path,sha in freeze['sha256'].items():
 assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==sha,'Production changed during regression'

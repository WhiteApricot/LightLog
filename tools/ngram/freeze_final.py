"""Seal final production and frozen data before opening the independent blind."""
from pathlib import Path
import json,hashlib
from train import ROOT,HERE
if (HERE/'final_freeze.json').exists():raise SystemExit('Final freeze is immutable')
files=list((ROOT/'lib/features/recognition').rglob('*.dart'))+list((ROOT/'assets/knowledge').glob('*'))+[ROOT/n for n in ['tools/recognition_tool_harness.dart','tools/evaluation/evaluate_recognition.dart','tools/ngram/export_pipeline.dart','tools/ngram/train_hierarchical.py','tools/ngram/train.py','tools/ngram/select_routing.py']]
r=dict(selected='B',rule='No production or parameter changes after freeze; v7 one-time acceptance only',productionSha256={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()},datasetSha256={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in (HERE/'data').glob('*')},userCorpusPath='lightlog_phase3_104class_realworld_holdout_v7.json',v7PredictedBeforeFreeze=False,v7SchemaValidatedBeforeThisSeal=(HERE/'v7_validation_error.json').exists(),v7InputsInspectedForSelection=False)
(HERE/'final_freeze.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
print('Final production/data sealed; v7 predictions have not run')

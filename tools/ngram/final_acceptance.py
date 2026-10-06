"""Freeze -> historical regression -> exactly one v7 prediction run."""
import json,hashlib,subprocess,shutil,sys,datetime
from train import ROOT,HERE
OUT=HERE/'final96'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write(p,data):
 assert not p.exists(),'Immutable artifact exists: '+str(p)
 p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def verify():
 freeze=json.loads((OUT/'production_freeze.json').read_text(encoding='utf-8'))
 for group in ['production','dataset','oracles']:
  for name,digest in freeze[group].items():assert sha(ROOT/name)==digest,'Frozen bytes changed: '+name
 return freeze
def run_corpus(entry,name):
 report=OUT/(name+'_initial.json');assert not report.exists(),'First-run immutable'
 # Claim before launch so an interruption never permits a second blind run.
 claim=OUT/(name+'_run_claim.json');write(claim,{'corpus':entry['target'],'sha256':entry['sha256'],'frozenSha256':sha(OUT/'production_freeze.json'),'claimedAt':datetime.datetime.now(datetime.timezone.utc).isoformat()})
 with (OUT/(name+'_runner.log')).open('w',encoding='utf-8') as log:
  subprocess.run([shutil.which('dart'),'tools/evaluation/evaluate_recognition.dart','--corpus',entry['target'],'--report',report.relative_to(ROOT).as_posix()],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
 r=json.loads(report.read_text(encoding='utf-8'));keys=['totalCases','categoryAccuracy','parentCategoryAccuracy','typeAccuracy','p2SafeRejectionRate','highConfidenceWrongPredictionCount','ordinaryValidCategoryNullCount','falseFallbackRate','mealRoutingAccuracy','latencyMicroseconds','failureDecomposition']
 return {**{k:r[k] for k in keys},'p2Count':r['priority'].get('P2',{}).get('total',0),'reportSha256':sha(report)}
def main():
 mode=sys.argv[1];seal=json.loads((HERE/'final_oracle_seal.json').read_text(encoding='utf-8'))
 if mode=='freeze':
  assert not (OUT/'production_freeze.json').exists()
  validation=json.loads((OUT/'validation.json').read_text(encoding='utf-8'));dev=json.loads((HERE/'stage_contract_direction_fields_pipeline_dev.json').read_text(encoding='utf-8'));checks=json.loads((OUT/'verification.json').read_text(encoding='utf-8'))
  assert validation['splitGroupLeakage']==0 and validation['obsoleteRuntimeSemanticReferenceCount']==0 and dev['highConfidenceWrong']==0
  assert all(x['exitCode']==0 for x in checks['commands'])
  files=list((ROOT/'lib').rglob('*.dart'))+list((ROOT/'assets/knowledge').glob('*'))+[ROOT/p for p in ['tools/evaluation/evaluate_recognition.dart','tools/recognition_tool_harness.dart','tools/ngram/export_pipeline.dart','tools/ngram/train_final.py','tools/ngram/select_final.py','tools/ngram/reference.py','tools/ngram/final_acceptance.py']]
  model=ROOT/'assets/knowledge/ngram.bin';b=model.read_bytes();import struct;n=struct.unpack('<I',b[4:8])[0];h=json.loads(b[8:8+n]);config={k:h[k] for k in ['grams','fusion','parentPrior','parentThreshold','parentMargin','childCalibration','directionThreshold','preparedMealThreshold']}
  freeze={'frozenAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'production':{p.relative_to(ROOT).as_posix():sha(p) for p in files if p.is_file()},'dataset':{p.relative_to(ROOT).as_posix():sha(p) for p in (HERE/'data').glob('*')},'oracles':{e['target']:e['sha256'] for e in seal['corpora']},'modelSha256':sha(model),'config':config,'configSha256':hashlib.sha256(json.dumps(config,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'dev':dev,'protocol':'train/dev only before freeze; no algorithm changes after freeze; historical regression then one v7 first-run; no tuning using holdout outcomes'}
  freeze['productionSourceSha256']=hashlib.sha256(json.dumps(freeze['production'],sort_keys=True,separators=(',',':')).encode()).hexdigest()
  write(OUT/'production_freeze.json',freeze);verify();print('PRODUCTION FROZEN',freeze['productionSourceSha256']);return
 freeze=verify()
 if mode=='regression':
  assert not (OUT/'regression_summary.json').exists()
  ordered=[('recognition_test_cases','original190'),('stress_holdout_v2','v2'),('compositional_holdout_v3','v3'),('family_generalization_holdout_v4','v4'),('semantic_routing_holdout_v5','v5'),('generalization_v6','v6')];summary={}
  for pattern,name in ordered:
   entry=next(e for e in seal['corpora'] if pattern in e['target']);summary[name]=run_corpus(entry,name);verify();print(name,json.dumps(summary[name]),flush=True)
  write(OUT/'regression_summary.json',summary);return
 if mode=='v7':
  assert (OUT/'regression_summary.json').exists(),'Historical regression first'
  entry=next(e for e in seal['corpora'] if 'holdout_v7' in e['target']);result=run_corpus(entry,'v7');verify();write(OUT/'v7_summary.json',result);print('v7 FIRST RUN',json.dumps(result),flush=True);return
 raise SystemExit('Modes: freeze, regression, v7')
if __name__=='__main__':main()

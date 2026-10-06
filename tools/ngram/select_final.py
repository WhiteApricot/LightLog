"""Bounded full-production dev selection, never opens any holdout."""
import json,struct,subprocess,shutil
from pathlib import Path
from train import ROOT,HERE
OUT=HERE/'final96/corrected'
def configure(path,**changes):
 b=path.read_bytes();n=struct.unpack('<I',b[4:8])[0];h=json.loads(b[8:8+n]);h.update(changes);raw=json.dumps(h,ensure_ascii=False,separators=(',',':')).encode();(ROOT/'assets/knowledge/ngram.bin').write_bytes(b'LLNG'+struct.pack('<I',len(raw))+raw+b[8+n:])
def evaluate(name):
 report=HERE/f'stage_{name}_pipeline_dev.json';assert not report.exists(),'Immutable experiment name already used'
 subprocess.run([shutil.which('dart'),'tools/ngram/evaluate_pipeline.dart',name],cwd=ROOT,check=True)
 return json.loads(report.read_text(encoding='utf-8'))
def main():
 assert not (HERE/'final96/production_freeze.json').exists(),'Production frozen: selection forbidden'
 assert not (OUT/'selection.json').exists(),'Selection is immutable; use a fresh experiment directory'
 results=[]
 # Eight already-trained candidates; full pipeline Category first, Parent next, size last.
 for p in sorted(OUT.glob('*.bin')):
  configure(p,fusion='F1');r=evaluate('contract_f1_'+p.stem.replace('.','p'));results.append({'model':p.name,'fusion':'F1','prior':0,'threshold':.25,'report':r})
 best=max(results,key=lambda r:(r['report']['categoryAccuracy'],r['report']['parentAccuracy'],-(OUT/r['model']).stat().st_size))
 p=OUT/best['model']
 stop=lambda r:r['categoryAccuracy']>=.90 and r['parentAccuracy']>=.94 and r['typeAccuracy']>=.98 and r['falseFallbackRate']<=.02 and r['highConfidenceWrong']==0
 if not stop(best['report']):
  for prior in [.05,.15]:
   configure(p,fusion='F2',parentPrior=prior);r=evaluate('contract_f2_'+str(prior).replace('.','p'));results.append({'model':p.name,'fusion':'F2','prior':prior,'threshold':.25,'report':r})
  best=max(results,key=lambda r:(r['report']['categoryAccuracy'],r['report']['parentAccuracy'],-(OUT/r['model']).stat().st_size))
 if not stop(best['report']):
  for threshold in [0.,.10]:
   configure(p,fusion='F3',parentThreshold=threshold);r=evaluate('contract_f3_'+str(threshold).replace('.','p'));results.append({'model':p.name,'fusion':'F3','prior':0,'threshold':threshold,'report':r})
 best=max(results,key=lambda r:(r['report']['categoryAccuracy'],r['report']['parentAccuracy'],-(OUT/r['model']).stat().st_size))
 configure(OUT/best['model'],fusion=best['fusion'],parentPrior=best['prior'],parentThreshold=best['threshold'])
 shutil.copy2(ROOT/'assets/knowledge/ngram.bin',OUT/'selected.bin')
 (OUT/'selection.json').write_text(json.dumps({'selection':'full production dev Category, then Parent, then size; no holdout access','best':best,'trials':results},indent=2)+'\n',encoding='utf-8')
 print('SELECTED',json.dumps(best),flush=True)
if __name__=='__main__':main()

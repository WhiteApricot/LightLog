"""Validate active taxonomy/data/model without opening any holdout content."""
import json,struct,hashlib,collections,re,unicodedata
from train import ROOT,HERE,load
from migrate_final import MAPPING
def main():
 tax=json.loads((HERE/'taxonomy.json').read_text(encoding='utf-8-sig'));assert len(tax)==96
 assert sum(s.startswith('expense.') for s in tax)==72;assert sum(s.startswith('income.') for s in tax)==24
 rows={name:load(f'ngram_{name}_v2.jsonl') for name in ['train','dev','training_corpus']}
 report={}
 for name,rs in rows.items():
  assert {r['semanticKey'] for r in rs}==set(tax)
  exact=collections.Counter(r['text'] for r in rs);norm=collections.Counter(re.sub(r'\s+',' ',unicodedata.normalize('NFKC',r['text']).lower()).strip() for r in rs)
  assert max(exact.values())==1 and max(norm.values())==1
  originals={r['id']:r for r in [json.loads(l) for l in (HERE/f'archive/104-final/ngram_{name}_v2.jsonl').read_text(encoding='utf-8').splitlines()]}
  for r in rs:assert {k:v for k,v in r.items() if k!='semanticKey'}=={k:v for k,v in originals[r['id']].items() if k!='semanticKey'}
  report[name]={'rows':len(rs),'classes':96,'exactDuplicates':0,'normalizedDuplicates':0,'metadataPreserved':True,'sha256':hashlib.sha256((HERE/f'data/ngram_{name}_v2.jsonl').read_bytes()).hexdigest()}
 assert not {r['splitGroup'] for r in rows['train']}&{r['splitGroup'] for r in rows['dev']}
 assert {r['id'] for r in rows['train']+rows['dev']}=={r['id'] for r in rows['training_corpus']}
 # Runtime strings, not archives or the intentional legacy migration ID map.
 def semantics(o):
  if isinstance(o,dict):
   for k,v in o.items():
    if k in ['semanticKey','semanticPrior'] and isinstance(v,str):yield v
    else:yield from semantics(v)
  elif isinstance(o,list):
   for x in o:yield from semantics(x)
 invalid=[]
 for p in (ROOT/'assets/knowledge').glob('*.json'):
  invalid += [(p.name,s) for s in semantics(json.loads(p.read_text(encoding='utf-8'))) if s not in tax]
 assert not invalid,invalid
 b=(ROOT/'assets/knowledge/ngram.bin').read_bytes();n=struct.unpack('<I',b[4:8])[0];h=json.loads(b[8:8+n]);assert set(h['labels'])==set(tax) and h['parentByChild']==tax
 assert not any(f.startswith(('type:','direction:')) for f in h['structuredVocabulary'])
 assert set(h['childCalibration'])==set(tax.values());assert len(b)<=4*1024*1024
 report.update({'taxonomy':{'expense':72,'income':24,'total':96,'parents':len(set(tax.values()))},'splitGroupLeakage':0,'labelConflicts':0,'obsoleteRuntimeSemanticReferenceCount':0,'modelBytes':len(b),'modelSha256':hashlib.sha256(b).hexdigest(),'auxiliaryHeads':[head['parent'] for head in h['heads'] if head.get('parent','').startswith('@')],'structuredTypeLeakage':0})
 (HERE/'final96/validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 print(json.dumps(report),flush=True)
 # Replace the active review view; original reviewer provenance remains archived.
 review=json.loads((HERE/'archive/104-final/ngram_dataset_review_report_v2.json').read_text(encoding='utf-8'))
 review['taxonomy']={'count':96,'source':'lib/data/database/seed_data.dart','semanticKeys':sorted(tax)}
 review['perSemanticKey']={s:{'corpus':sum(r['semanticKey']==s for r in rows['training_corpus']),'train':sum(r['semanticKey']==s for r in rows['train']),'dev':sum(r['semanticKey']==s for r in rows['dev']),'splitGroups':len({r['splitGroup'] for r in rows['training_corpus'] if r['semanticKey']==s})} for s in sorted(tax)}
 review['checks']={'96SemanticKeysCovered':True,'devAll96Classes':True,'exactDuplicateCount':0,'normalizedDuplicateCount':0,'splitGroupLeakage':0,'obsoleteSemanticKeyCount':0,'metadataPreserved':True}
 review['final96Migration']='Contract migration only; original 104 reviewer report/provenance preserved in archive/104-final; no new text or holdout training.'
 def migrate(o):
  if isinstance(o,str):return MAPPING.get(o,o)
  if isinstance(o,list):return [migrate(v) for v in o]
  if isinstance(o,dict):return {MAPPING.get(k,k):migrate(v) for k,v in o.items()}
  return o
 (HERE/'data/ngram_dataset_review_report_v2.json').write_text(json.dumps(migrate(review),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()

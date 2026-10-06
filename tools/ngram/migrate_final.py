"""One-time contract migration. No predictions, new text, or holdout training."""
import hashlib,json,re,shutil,subprocess,unicodedata
from pathlib import Path
from train import ROOT,HERE

MAPPING={
 'expense.shopping.beauty':'expense.shopping.personal',
 'expense.daily.personal':'expense.shopping.personal',
 'expense.daily.household':'expense.shopping.home',
 'expense.daily.haircut':'expense.daily.grooming',
 'expense.shopping.gift':'expense.social.gift',
 'expense.social.relationship':'expense.social.gift',
 'expense.entertainment.movie':'expense.entertainment.performance',
 'expense.entertainment.music':'expense.entertainment.media',
 'expense.entertainment.subscription':'expense.entertainment.media',
 'expense.entertainment.hobby':'expense.entertainment.activity',
 'expense.communication.cloud':'expense.digital.software',
 'income.parttime.freelance':'income.parttime.service',
 'income.parttime.project':'income.parttime.service',
 'income.parttime.consulting':'income.parttime.service',
 'income.investment.fund':'income.investment.capital_gain',
 'expense.social.red_packet':'expense.social.red.packet',
 'income.other.red_packet':'income.other.red.packet',
}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def canonical(key,text=''):
 key=MAPPING.get(key,key)
 if key=='expense.sports.equipment' and re.search(r'跑鞋|运动鞋|球鞋|运动服|瑜伽服|球衣|泳衣|泳裤|运动裤|运动袜',text):return 'expense.shopping.clothing'
 if key=='expense.food.dinner' and '夜宵' in text and not re.search(r'晚餐|晚饭',text):return 'expense.food.other'
 return key
def norm(s):return re.sub(r'\s+',' ',unicodedata.normalize('NFKC',s).lower()).strip()
def write(p,data):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 archive=HERE/'archive/104-final';assert not archive.exists(),'Migration already archived'
 archive.mkdir(parents=True)
 files=list((ROOT/'lib/features/recognition').rglob('*.dart'))+[ROOT/'lib/data/database/seed_data.dart']+list((ROOT/'assets/knowledge').glob('*'))
 baseline={'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),'production':{str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in files},'datasets':{p.name:sha(p) for p in (HERE/'data').glob('*')}}
 for p in files:
  target=archive/'snapshot'/p.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
 for p in (HERE/'data').glob('*'):shutil.copy2(p,archive/p.name)
 for p in HERE.glob('*.json'):shutil.copy2(p,archive/p.name)
 write(archive/'baseline.json',baseline)
 seed=ROOT/'lib/data/database/seed_data.dart';s=seed.read_text(encoding='utf-8')
 ids={k.replace('.','-'):v.replace('.','-') for k,v in MAPPING.items() if '_' not in k}
 # Canonical IDs use hyphens for red.packet too. Keep one seed per merged class.
 chunks=re.findall(r'  CategorySeed\(.*?\),',s,re.S);seen=set();new=[]
 for chunk in chunks:
  old=re.search(r"'([^']+)'",chunk).group(1);target=ids.get(old,old)
  if target in seen:continue
  seen.add(target)
  chunk=chunk.replace("'"+old+"'","'"+target+"'",1)
  # Move merged child into its new parent, but reuse its unique existing SVG.
  if old in ids:
   parent='-'.join(target.split('-')[:2]);chunk=re.sub(r"'[^']+'(?=,\s*\))","'"+parent+"'",chunk)
  for a,b in {'美妆护肤':'个人护理用品','影音音乐':'影音内容','电影演出':'电影与演出','兴趣爱好':'娱乐活动','自由职业':'劳务服务','基金收益':'证券交易收益','运动装备':'运动器材'}.items():chunk=chunk.replace(a,b)
  new.append(chunk)
 start=s.index('const defaultCategories');end=s.index('];',start)+2
 s=s[:start]+'const defaultCategories = <CategorySeed>[\n'+ '\n'.join(new)+'\n];'+s[end:]
 start=s.index('const categorySemanticKeys');end=s.index('};',start)+2
 pairs=re.findall(r"  '([^']+)': '([^']+)'",s[start:end]);seen=set();mapped=[]
 for cid,key in pairs:
  key=MAPPING.get(key,key);cid=ids.get(cid,cid)
  if cid in seen:continue
  seen.add(cid);mapped.append(f"  '{cid}': '{key}',")
 s=s[:start]+'const categorySemanticKeys = <String, String>{\n'+'\n'.join(mapped)+'\n};'+s[end:]
 # Explicit legacy keys exist only in this migration contract, never active outputs.
 s+='\nconst mergedDefaultCategoryIds = <String, String>{\n'+''.join(f"  '{a}': '{b}',\n" for a,b in ids.items())+'};\n'
 seed.write_text(s,encoding='utf-8')
 # Active code/fixtures: migrate references; immutable reports and archives excluded.
 for base in [ROOT/'lib',ROOT/'test']:
  for p in base.rglob('*.dart'):
   if p==seed:continue
   text=p.read_text(encoding='utf-8')
   for a,b in MAPPING.items():text=text.replace(a,b)
   for a,b in ids.items():text=text.replace(a,b)
   text=text.replace('hasLength(125)','hasLength(117)').replace('labels.length, 104','labels.length, 96')
   p.write_text(text,encoding='utf-8')
 # Knowledge recursively remaps semantic outputs, preserving evidence metadata.
 def walk(o):
  if isinstance(o,list):return [walk(x) for x in o]
  if isinstance(o,dict):return {k:canonical(v,str(o)) if k in ['semanticKey','semanticPrior'] and isinstance(v,str) else walk(v) for k,v in o.items()}
  return o
 for p in (ROOT/'tools/knowledge').glob('*.json'):
  if p.name.endswith('_source.json') or p.name=='review_samples.json':write(p,walk(json.loads(p.read_text(encoding='utf-8-sig'))))
 # Training source only. Stable first-row retention, no synthetic samples.
 allrows=[json.loads(l) for l in (HERE/'data/ngram_training_corpus_v2.jsonl').read_text(encoding='utf-8').splitlines()]
 split={json.loads(l)['id']:name for name in ['train','dev'] for l in (HERE/f'data/ngram_{name}_v2.jsonl').read_text(encoding='utf-8').splitlines()}
 kept=[];exact={};normalized={};conflicts=[];removed=[]
 for r in allrows:
  r['semanticKey']=canonical(r['semanticKey'],r['text']);n=norm(r['text'])
  if n in normalized and normalized[n]['semanticKey']!=r['semanticKey']:
   conflicts.append({'id':r['id'],'retainedId':normalized[n]['id'],'labels':[normalized[n]['semanticKey'],r['semanticKey']]});continue
  if r['text'] in exact or n in normalized:removed.append(r['id']);continue
  exact[r['text']]=r;normalized[n]=r;kept.append(r)
 assert not conflicts,f'Label conflicts require adjudication: {conflicts[:5]}'
 train=[r for r in kept if split[r['id']]=='train'];dev=[r for r in kept if split[r['id']]=='dev']
 leakage={r['splitGroup'] for r in train}&{r['splitGroup'] for r in dev}
 if leakage:
  import random
  groups=sorted({r['splitGroup'] for r in kept});random.Random(17).shuffle(groups);dg=set(groups[:round(len(groups)*.1)])
  train=[r for r in kept if r['splitGroup'] not in dg];dev=[r for r in kept if r['splitGroup'] in dg]
 for name,rows in [('training_corpus',kept),('train',train),('dev',dev)]:
  (HERE/f'data/ngram_{name}_v2.jsonl').write_text(''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rows),encoding='utf-8')
 write(HERE/'final_dataset_migration.json',{'train':len(train),'dev':len(dev),'classes':len({r['semanticKey'] for r in kept}),'exactAndNormalizedRemoved':len(removed),'labelConflicts':conflicts,'splitGroupLeakage':len({r['splitGroup'] for r in train}&{r['splitGroup'] for r in dev}),'normalization':'NFKC lowercase whitespace; retains numeric field text','sha256':{p.name:sha(p) for p in (HERE/'data').glob('*.jsonl')},'mapping':MAPPING})
 # Oracle migration is contract-only. Seal v7 now; no content access until acceptance.
 out=ROOT/'tools/evaluation/corpora/phase3_96class';out.mkdir(parents=True,exist_ok=True);manifest=[]
 sources=list((ROOT/'tools/evaluation/corpora/phase3_104class').glob('*.json'))+[ROOT/'lightlog_phase3_104class_realworld_holdout_v7.json']
 for p in sources:
  data=json.loads(p.read_text(encoding='utf-8-sig'))
  for case in data['cases']:
   expected=case['expected'];text=case['input'];old=expected.get('semanticKey')
   if old is None and expected.get('subcategoryId'):old=expected['subcategoryId'].replace('-','.')
   if old:
    key=canonical(old,text);expected['semanticKey']=key;expected['subcategoryId']=key.replace('.','-');expected['categoryId']='-'.join(key.split('.')[:2])
   for hist in case.get('setup',{}).get('history',[]):
    hist['subcategoryId']=ids.get(hist['subcategoryId'],hist['subcategoryId'])
  target=out/p.name.replace('104class','96class');write(target,data)
  manifest.append({'source':str(p.relative_to(ROOT)).replace('\\','/'),'sourceSha256':sha(p),'target':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':sha(target)})
 write(HERE/'final_oracle_seal.json',{'corpora':manifest,'protocol':'Contract-only migration. v7 sealed; no reads/search/analysis until production freeze; one acceptance first-run.'})
 print(json.dumps({'train':len(train),'dev':len(dev),'classes':len({r['semanticKey'] for r in kept}),'oracles':len(manifest)}))
if __name__=='__main__':main()

"""Decode the exported int8 contract independently of Dart; parity, not fitting."""
import json,struct,sys
import numpy as np
from scipy.sparse import hstack,csr_matrix
from sklearn.feature_extraction.text import CountVectorizer
from train import normalize,load,ROOT,HERE
from train_final import mask_meal,softmax

def predictions(path):
 b=path.read_bytes();n=struct.unpack('<I',b[4:8])[0];h=json.loads(b[8:8+n]);raw=np.frombuffer(b[8+n:],dtype=np.int8);rows=load('ngram_dev_v2.jsonl');tr=[json.loads(l) for l in (HERE/'dev_pipeline.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 v=CountVectorizer(analyzer='char',ngram_range=tuple(h['grams']),binary=True,lowercase=False,vocabulary={s:i for i,s in enumerate(h['vocabulary'])});x=v.transform([normalize(r['text']) for r in rows]);idx={s:i for i,s in enumerate(h['structuredVocabulary'])};ri=[];ci=[]
 for i,t in enumerate(tr):
  for s in set(t['features']):
   if s in idx:ri.append(i);ci.append(idx[s])
 x=hstack([x,csr_matrix((np.ones(len(ri)),(ri,ci)),shape=(len(rows),len(idx)))],format='csr');features=x.shape[1]
 if h['version']==3:
  d=h['embeddingDimension'];emb=raw[:features*d].reshape(features,d).astype(np.float64)*np.array(h['embeddingScales'])[:,None];raw=raw[features*d:];x=x@emb/np.maximum(x.getnnz(1),1)[:,None];features=d
 def score(head):
  count=len(head['labels']);q=raw[head['offset']:head['offset']+features*count].reshape(features,count);return softmax(x@(q.astype(np.float64)*np.array(head['scales']))+np.array(head['bias']))
 parent=h['heads'][0];pp=score(parent);joint=np.zeros((len(rows),len(h['labels'])))
 for i,p in enumerate(parent['labels']):
  children=[s for s in h['labels'] if h['parentByChild'][s]==p];head=next((s for s in h['heads'][1:] if s['parent']==p),None);cp=score(head) if head else np.ones((len(rows),1))
  for j,s in enumerate(children):joint[:,h['labels'].index(s)]=pp[:,i]*cp[:,j]

 direction=next((head for head in h['heads'] if head.get('parent')=='@direction'),None)
 if direction is not None:
  dp=score(direction)
  meal=next((head for head in h['heads'] if head.get('parent')=='@meal'),None)
  mp=np.zeros(len(rows))
  if meal is not None:
   mx=v.transform([normalize(mask_meal(r['text'])) for r in rows]);mx=hstack([mx,csr_matrix((len(rows),len(idx)))],format='csr')
   count=len(meal['labels']);q=raw[meal['offset']:meal['offset']+features*count].reshape(features,count)
   mp=softmax(mx@(q.astype(np.float64)*np.array(meal['scales']))+np.array(meal['bias']))[:,meal['labels'].index('meal')]
   mp[mx.getnnz(1)==0]=0
  empty=x.getnnz(1)==0
  joint[empty]=0;dp[empty]=.5;mp[empty]=0
  for i,t in enumerate(tr):t['incomeProbability']=float(dp[i,direction['labels'].index('income')]);t['preparedMealProbability']=float(mp[i])
 return h,rows,tr,joint

if __name__=='__main__':
 path=ROOT/'assets/knowledge/ngram.bin';h,rows,tr,p=predictions(path)
 vectors=[dict(text=r['text'],normalized=normalize(r['text']),features=t['features'],scores=q.tolist(),incomeProbability=t.get('incomeProbability'),preparedMealProbability=t.get('preparedMealProbability')) for r,t,q in zip(rows[:12],tr[:12],p[:12])]
 vectors.extend(dict(text=s,normalized=normalize(s),features=[],scores=[0.]*len(h['labels'])) for s in ['', '123 ! 🐈','ＡＢＣ１２３，🐈'])
 (HERE/'final96/parity_vectors.json').write_text(json.dumps(vectors,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 (HERE/'final96/dev_predictions.json').write_text(json.dumps([dict(id=r['id'],label=h['labels'][q.argmax()],probability=float(q.max()),incomeProbability=t.get('incomeProbability'),preparedMealProbability=t.get('preparedMealProbability')) for r,t,q in zip(rows,tr,p)],ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')

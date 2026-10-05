"""Explicit shared-feature parent/conditional-child LR, frozen data only."""
import json,hashlib,struct,time
import numpy as np
from scipy.sparse import hstack,csr_matrix
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score
from train import normalize,load,ROOT,HERE
from select_routing import select

def softmax(z):
 p=np.exp(z-z.max(1)[:,None]);return p/p.sum(1)[:,None]
def fit_head(x,y,xd,labels,c):
 if len(labels)==1: return None,np.ones((xd.shape[0],1))
 m=LogisticRegression(C=c,solver='saga',max_iter=180,tol=.002,random_state=17,n_jobs=1).fit(x,y)
 # sklearn binary coefficients represent one log-odds vector; split symmetrically.
 w=m.coef_;b=m.intercept_
 if len(labels)==2: w=np.vstack([-w[0]/2,w[0]/2]);b=np.array([-b[0]/2,b[0]/2])
 scale=np.maximum(abs(w).max(1),1e-12)/127;q=np.rint(w/scale[:,None]).astype(np.int8)
 p=softmax(xd@(q*scale[:,None]).T+b)
 return dict(labels=labels,scales=scale.tolist(),bias=b.tolist(),q=q.T.copy()),p

def main():
 train,dev=load('ngram_train_v2.jsonl'),load('ngram_dev_v2.jsonl');assert not {r['splitGroup'] for r in train}&{r['splitGroup'] for r in dev}
 taxonomy=json.loads((HERE/'taxonomy.json').read_text(encoding='utf-8-sig'));labels=sorted(taxonomy);parents=sorted(set(taxonomy.values()))
 tr=[json.loads(l) for l in (HERE/'train_pipeline.jsonl').read_text(encoding='utf-8-sig').splitlines()];dt=[json.loads(l) for l in (HERE/'dev_pipeline.jsonl').read_text(encoding='utf-8-sig').splitlines()]
 y=np.array([r['semanticKey'] for r in train]);yp=np.array([taxonomy[s] for s in y]);yd=np.array([r['semanticKey'] for r in dev]);ypd=np.array([taxonomy[s] for s in yd])
 trials=[];best=None
 for dim in [8192,16384]:
  v=CountVectorizer(analyzer='char',ngram_range=(2,3),max_features=dim,binary=True,lowercase=False,min_df=2,dtype=np.float64)
  x=v.fit_transform([normalize(r['text']) for r in train]);xd=v.transform([normalize(r['text']) for r in dev]);base=v.get_feature_names_out().tolist()
  for structured in [False,True]:
   features=sorted({s for r in tr for s in r['features']}) if structured else []
   idx={s:i for i,s in enumerate(features)}
   def extra(rows):
    ri=[];ci=[]
    for i,r in enumerate(rows):
     for s in set(r['features']):
      if s in idx: ri.append(i);ci.append(idx[s])
    return csr_matrix((np.ones(len(ri)),(ri,ci)),shape=(len(rows),len(idx)))
   xx=hstack([x,extra(tr)],format='csr') if structured else x;xxd=hstack([xd,extra(dt)],format='csr') if structured else xd
   for c in [.5,2.]:
    start=time.monotonic();parent,pp=fit_head(xx,yp,xxd,parents,c);heads=[parent];joint=np.zeros((len(dev),len(labels)));pred=[]
    for i,p in enumerate(parents):
     children=[s for s in labels if taxonomy[s]==p];mask=yp==p
     head,cp=fit_head(xx[mask],y[mask],xxd,children,c)
     if head is not None:head['parent']=p;heads.append(head)
     for j,s in enumerate(children):joint[:,labels.index(s)]=pp[:,i]*cp[:,j]
    pt=pp.argmax(1); hierarchical=[]
    for i,p in enumerate(pt):
     children=[j for j,s in enumerate(labels) if taxonomy[s]==parents[p]];hierarchical.append(labels[children[np.argmax(joint[i,children])]])
    size=sum(h['q'].size for h in heads)
    trial=dict(dimension=len(base),structured=structured,structuredCount=len(features),C=c,parentAccuracy=accuracy_score(ypd,np.array(parents)[pt]),categoryAccuracy=accuracy_score(yd,hierarchical),weightBytes=size,seconds=time.monotonic()-start)
    trials.append(trial);print(json.dumps(trial),flush=True)
    # Size wins when gain is < 0.3 percentage points.
    if best is None or trial['categoryAccuracy']>best[0]['categoryAccuracy']+.003 or (abs(trial['categoryAccuracy']-best[0]['categoryAccuracy'])<=.003 and size<best[0]['weightBytes']): best=trial,base,features,heads,joint,pp
 config,vocab,features,heads,joint,pp=best
 parameters=select(labels,joint,('B',pp))
 packed=[];offset=0;rawWeights=[]
 for h in heads:
  q=h.pop('q');h['offset']=offset;offset+=q.size;rawWeights.append(q.tobytes());packed.append(h)
 header=dict(version=2,backend='hierarchical-lr',normalization='ascii-cjk-space-v1',grams=[2,3],labels=labels,parentByChild=taxonomy,vocabulary=vocab,structuredVocabulary=features,heads=packed,**{k:parameters[k] for k in ['parentThreshold','parentMargin','childThreshold','childMargin']})
 raw=json.dumps(header,ensure_ascii=False,separators=(',',':')).encode('utf-8');asset=b'LLNG'+struct.pack('<I',len(raw))+raw+b''.join(rawWeights)
 assert len(asset)<=4*1024*1024
 (ROOT/'assets/knowledge/ngram.bin').write_bytes(asset)
 report=dict(stage='B',selected=config,trials=trials,assetBytes=len(asset),assetSha256=hashlib.sha256(asset).hexdigest(),groupLeakage=0,splitSha256={n:hashlib.sha256((HERE/'data'/n).read_bytes()).hexdigest() for n in ['ngram_train_v2.jsonl','ngram_dev_v2.jsonl']})
 (HERE/'stage_b_training.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 vectors=[dict(text=r['text'],normalized=normalize(r['text']),features=t['features'],scores=p.tolist()) for r,t,p in zip(dev[:12],dt[:12],joint[:12])]
 for text in ['', '123 ! 🐈','ＡＢＣ１２３，🐈']:
  vectors.append(dict(text=text,normalized=normalize(text),features=[],scores=[0.]*len(labels)))
 (HERE/'parity_vectors.json').write_text(json.dumps(vectors,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 (HERE/'dev_predictions.json').write_text(json.dumps([dict(id=r['id'],label=labels[int(p.argmax())],probability=float(p.max())) for r,p in zip(dev,joint)],ensure_ascii=False,separators=(',',':'))+'\n',encoding='utf-8')
 print('SELECTED',json.dumps(report),flush=True)
if __name__=='__main__':main()

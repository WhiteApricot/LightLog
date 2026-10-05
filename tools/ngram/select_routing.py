"""Stage A: frozen posterior only. No fitting and no historical input."""
import json, struct, hashlib
from pathlib import Path
import numpy as np
from sklearn.feature_extraction.text import CountVectorizer
from train import normalize, load, ROOT, HERE

def posterior():
    b=(ROOT/'assets/knowledge/ngram.bin').read_bytes(); n=struct.unpack('<I',b[4:8])[0]
    h=json.loads(b[8:8+n]); q=np.frombuffer(b[8+n:],dtype=np.int8).reshape(len(h['vocabulary']),len(h['labels']))
    v=CountVectorizer(analyzer='char',ngram_range=tuple(h['grams']),binary=True,lowercase=False,vocabulary={t:i for i,t in enumerate(h['vocabulary'])})
    x=v.transform([normalize(r['text']) for r in load('ngram_dev_v2.jsonl')])
    z=x @ (q*np.array(h['scales'])).astype(np.float64)+np.array(h['bias'])
    p=np.exp(z-z.max(1)[:,None]); p/=p.sum(1)[:,None]; p[x.getnnz(1)==0]=0
    return h,p,hashlib.sha256(b).hexdigest()

def select(labels,p,stage):
    rows=load('ngram_dev_v2.jsonl'); trace=[json.loads(l) for l in (HERE/'dev_pipeline.jsonl').read_text(encoding='utf-8-sig').splitlines()]
    taxonomy=json.loads((HERE/'taxonomy.json').read_text(encoding='utf-8-sig')); parents=sorted(set(taxonomy.values()))
    yi=np.array([labels.index(r['semanticKey']) for r in rows]); yp=np.array([parents.index(taxonomy[r['semanticKey']]) for r in rows]); li=np.array([parents.index(taxonomy[l]) for l in labels])
    pp=np.stack([p[:,li==i].sum(1) for i in range(len(parents))],1)
    if isinstance(stage,tuple): stage,pp=stage
    pt=pp.argmax(1); ps=np.sort(pp,axis=1); pm=ps[:,-1]-ps[:,-2]
    hp=np.array([max(np.flatnonzero(li==pt[i]), key=lambda j:p[i,j]) for i in range(len(p))])
    flat=p.argmax(1); best=None; trials=[]
    for threshold in [.25,.40,.55,.70,.85,.95]:
      for margin in [0.,.05,.15]:
       for childThreshold in [.25,.40,.55,.70,.85,.95]:
        pred=[]; accepted=[]; levels=[]
        for i,t in enumerate(trace):
          anchor=t['semanticKey']; level=t['level']; target=parents[pt[i]]
          allow=t['eligible'] and level>0
          if level==1:
            target=taxonomy[anchor]
            if pp[i,parents.index(target)]<threshold: allow=False
          elif pp[i,pt[i]]<threshold or pm[i]<margin: allow=False
          children=np.flatnonzero(li==parents.index(target)); order=children[np.argsort(p[i,children])[::-1]]; child=order[0]
          mass=p[i,children].sum(); cp=p[i,child]/mass if mass else 0
          cm=(p[i,child]-(p[i,order[1]] if len(order)>1 else 0))/mass if mass else 0
          candidate=labels[child]
          if cp<childThreshold or cm<.05: allow=False
          if not t['meal'] and candidate in {'expense.food.breakfast','expense.food.lunch','expense.food.dinner'}: allow=False
          if t['typeConflict'] or (not t['defaultType'] and t['type'] is not None and not candidate.startswith(t['type']+'.')): allow=False
          if candidate.startswith('income.refund.'): allow=False
          if allow: anchor=candidate
          if anchor is None: anchor=(t['type'] or 'expense')+'.other.general'
          pred.append(anchor); accepted.append(allow); levels.append(level)
        correct=np.array(pred)==np.array([r['semanticKey'] for r in rows]); mask=np.array(accepted); count=mask.sum()
        accuracy=float(correct[mask].mean()) if count else 0
        trial=dict(parentThreshold=threshold,parentMargin=margin,childThreshold=childThreshold,childMargin=.05,categoryAccuracy=float(correct.mean()),acceptedAccuracy=accuracy,acceptedCoverage=float(mask.mean()))
        trials.append(trial)
        if accuracy>=.90 and (best is None or (trial['categoryAccuracy'],trial['acceptedCoverage'])>(best[0]['categoryAccuracy'],best[0]['acceptedCoverage'])): best=trial,pred,mask,np.array(levels)
    if best is None: raise RuntimeError('No calibrated routing meets dev accepted accuracy floor')
    config,pred,mask,levels=best
    pred=np.array(pred); expected=np.array([r['semanticKey'] for r in rows]); correct=pred==expected; fallback=np.array([s.endswith('.other.general') for s in pred]); specific=~fallback
    parentCorrect=np.array([taxonomy[s]==taxonomy[r['semanticKey']] for s,r in zip(pred,rows)])
    def rate(m): return float(correct[m].mean()) if m.sum() else None
    report=dict(stage=stage,selection='max full pipeline dev category accuracy with accepted accuracy >=90%; ties coverage',selected=config,flatChildAccuracy=float((flat==yi).mean()),flatParentAccuracy=float((li[flat]==yp).mean()),hierarchicalParentAccuracy=float((pt==yp).mean()),hierarchicalChildAccuracy=float((hp==yi).mean()),parentAccuracy=float(parentCorrect.mean()),specificCategoryCoverage=float(specific.mean()),specificCategoryAccuracy=rate(specific),fallbackRate=float(fallback.mean()),falseFallbackRate=float((fallback & ~correct).mean()),childConditionalAccuracy=rate(parentCorrect),sameParentRerankAccuracy=rate(mask&(levels==1)),sameParentRerankCount=int((mask&(levels==1)).sum()),crossParentStatisticalAccuracy=rate(mask&(levels==2)),crossParentStatisticalCount=int((mask&(levels==2)).sum()),failureDecomposition=dict(otherFallbackError=int((fallback&~correct).sum()),wrongParent=int((~parentCorrect).sum()),correctParentWrongChild=int((parentCorrect&~correct).sum()),wrongType=int(sum(s.split('.')[0]!=r['type'] for s,r in zip(pred,rows))),mealDetection=int(sum(r['semanticKey'] in {'expense.food.breakfast','expense.food.lunch','expense.food.dinner'} and not t['meal'] for r,t in zip(rows,trace))),taxonomyAmbiguity='not adjudicated: no relabeling',safety='separate historical P2 suite'),trials=trials)
    (HERE/f'stage_{stage.lower()}_dev.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (HERE/'routing_parameters.json').write_text(json.dumps(config)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='trials'},ensure_ascii=False),flush=True)
    return config

if __name__=='__main__':
    raise SystemExit('Stage A is archived; use train_hierarchical.py or train_pooled.py for dev-only selection')

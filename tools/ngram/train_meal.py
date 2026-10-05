from pathlib import Path
import json,struct
import numpy as np
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import precision_score,recall_score,balanced_accuracy_score
from train import ROOT,HERE,load,normalize
b=(ROOT/'assets/knowledge/ngram.bin').read_bytes();n=struct.unpack('<I',b[4:8])[0];h=json.loads(b[8:8+n]);v=CountVectorizer(analyzer='char',ngram_range=tuple(h['grams']),binary=True,lowercase=False,vocabulary={s:i for i,s in enumerate(h['vocabulary'])})
tr,dv=load('ngram_train_v2.jsonl'),load('ngram_dev_v2.jsonl');meals={'expense.food.breakfast','expense.food.lunch','expense.food.dinner'}
x=v.transform([normalize(r['text']) for r in tr]);xd=v.transform([normalize(r['text']) for r in dv]);y=np.array([r['semanticKey'] in meals for r in tr]);yd=np.array([r['semanticKey'] in meals for r in dv]);trials=[];best=None
for c in [.5,2.]:
 m=LogisticRegression(C=c,solver='liblinear',random_state=17).fit(x,y);w=m.coef_[0];scale=max(abs(w).max(),1e-12)/127;q=np.rint(w/scale).astype(np.int8);z=xd@(q.astype(float)*scale)+m.intercept_[0];prob=1/(1+np.exp(-z))
 for threshold in [.5,.6,.7,.8,.9,.95]:
  pred=prob>=threshold;trial=dict(C=c,threshold=threshold,precision=precision_score(yd,pred,zero_division=0),recall=recall_score(yd,pred),balancedAccuracy=balanced_accuracy_score(yd,pred),accuracy=float((pred==yd).mean()));trials.append(trial)
  if trial['precision']>=.95 and (best is None or trial['recall']>best[0]['recall']):best=trial,q,scale,float(m.intercept_[0]),prob
report=dict(labelContract='positive iff existing oracle is breakfast/lunch/dinner; other food labels remain negative; no relabeling',positiveTrain=int(y.sum()),positiveDev=int(yd.sum()),trials=trials,selected=best[0] if best else None)
(HERE/'meal_dev.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report),flush=True)
if best:
 trial,q,scale,bias,prob=best
 (HERE/'meal_candidate.json').write_text(json.dumps(dict(weights=q.tolist(),scale=scale,bias=bias,threshold=trial['threshold'],devProbabilities=prob.tolist()))+'\n',encoding='utf-8')

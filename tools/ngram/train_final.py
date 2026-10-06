"""Final 96-class shared sparse LR; all fitting and calibration use train/dev."""
import json,struct,hashlib,time,re
import numpy as np
from scipy.sparse import hstack,csr_matrix
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import precision_score,recall_score
from train import ROOT,HERE,load,normalize
def softmax(z):
 p=np.exp(z-z.max(1)[:,None]);return p/p.sum(1)[:,None]

OUT=HERE/'final96/corrected'
TIME=r'早餐|午餐|晚餐|早饭|午饭|晚饭|早上|中午|晚上|清晨|早晨|上午|下午|正午|午间|晚间|凌晨|今早|昨晚|今晚|[零〇一二两三四五六七八九十\d]{1,3}点(?:半|[零〇一二两三四五六七八九十\d]{1,3}分)?|\d{1,2}:\d{2}'
def mask_meal(s):return re.sub(TIME,' ',s)
def fit(x,y,xd,labels,c,balanced=False):
 if len(labels)==1:return None,np.ones((xd.shape[0],1))
 m=LogisticRegression(C=c,solver='saga',max_iter=180,tol=.002,random_state=17,n_jobs=1,class_weight='balanced' if balanced else None).fit(x,y)
 w=m.coef_;b=m.intercept_
 if len(labels)==2:w=np.vstack([-w[0]/2,w[0]/2]);b=np.array([-b[0]/2,b[0]/2])
 scales=np.maximum(abs(w).max(1),1e-12)/127;q=np.rint(w/scales[:,None]).astype(np.int8)
 return {'labels':labels,'scales':scales.tolist(),'bias':b.tolist(),'q':q.T.copy()},softmax(xd@(q*scales[:,None]).T+b)
def save(base,features,heads,config,path):
 packed=[];offset=0;weights=[]
 for head in heads:
  h={k:v for k,v in head.items() if k!='q'};h['offset']=offset;offset+=head['q'].size;packed.append(h);weights.append(head['q'].tobytes())
 header={'version':2,'backend':'hierarchical-lr','normalization':'ascii-cjk-space-v1','grams':[2,3],'labels':config['labels'],'parentByChild':config['taxonomy'],'vocabulary':base,'structuredVocabulary':features,'heads':packed,'parentThreshold':.25,'parentMargin':0.,'childThreshold':.55,'childMargin':.05,'childCalibration':config['childCalibration'],'directionThreshold':config['directionThreshold'],'preparedMealThreshold':config['mealThreshold'],'fusion':'F1','parentPrior':0.}
 raw=json.dumps(header,ensure_ascii=False,separators=(',',':')).encode();asset=b'LLNG'+struct.pack('<I',len(raw))+raw+b''.join(weights);assert len(asset)<=4*1024*1024;path.write_bytes(asset)
 return hashlib.sha256(asset).hexdigest()
def main():
 assert not (HERE/'final96/production_freeze.json').exists(),'Production frozen: training forbidden'
 assert not OUT.exists() or not list(OUT.glob('*.bin')),'Training artifacts immutable; use a fresh experiment directory'
 OUT.mkdir(parents=True,exist_ok=True);tr,dev=load('ngram_train_v2.jsonl'),load('ngram_dev_v2.jsonl')
 taxonomy=json.loads((HERE/'taxonomy.json').read_text(encoding='utf-8-sig'));labels=sorted(taxonomy);parents=sorted(set(taxonomy.values()));assert len(labels)==96
 traces=[[json.loads(l) for l in (HERE/f'{s}_pipeline.jsonl').read_text(encoding='utf-8-sig').splitlines()] for s in ['train','dev']]
 y=np.array([r['semanticKey'] for r in tr]);yd=np.array([r['semanticKey'] for r in dev]);yp=np.array([taxonomy[s] for s in y]);ypd=np.array([taxonomy[s] for s in yd]);trials=[]
 for dim in [8192,16384]:
  v=CountVectorizer(analyzer='char',ngram_range=(2,3),max_features=dim,binary=True,lowercase=False,min_df=2,dtype=np.float64)
  x=v.fit_transform([normalize(r['text']) for r in tr]);xd=v.transform([normalize(r['text']) for r in dev]);base=v.get_feature_names_out().tolist()
  for structured in [True]:
   features=sorted({f for r in traces[0] for f in r['features']}) if structured else [];index={s:i for i,s in enumerate(features)}
   assert not any(f.startswith(('type:','direction:')) for f in features)
   def extra(rows):
    ri=[];ci=[]
    for i,r in enumerate(rows):
     for f in set(r['features']):
      if f in index:ri.append(i);ci.append(index[f])
    return csr_matrix((np.ones(len(ri)),(ri,ci)),shape=(len(rows),len(features)))
   xx=hstack([x,extra(traces[0])],format='csr');xxd=hstack([xd,extra(traces[1])],format='csr')
   for c in [.5,2.]:
    name=f'{dim}_{int(structured)}_{c}';start=time.monotonic();parent,pp=fit(xx,yp,xxd,parents,c);heads=[parent];joint=np.zeros((len(dev),len(labels)));calibration={}
    for i,p in enumerate(parents):
     children=[s for s in labels if taxonomy[s]==p];h,cp=fit(xx[yp==p],y[yp==p],xxd,children,c)
     if h is not None:h['parent']=p;heads.append(h)
     for j,s in enumerate(children):joint[:,labels.index(s)]=pp[:,i]*cp[:,j]
     actual=ypd==p;top=cp.argmax(1);truth=np.array(children)[top]==yd;ordered=np.sort(cp,axis=1);margin=ordered[:,-1]-(ordered[:,-2] if len(children)>1 else 0)
     options=[]
     for threshold in [.4,.55,.7,.85]:
      for gap in [0.,.05,.15]:
       accepted=actual&(cp.max(1)>=threshold)&(margin>=gap);n=int(accepted.sum());acc=float(truth[accepted].mean()) if n else 0
       if acc>=.97:options.append((n,-threshold,-gap,threshold,gap))
     chosen=max(options) if options else (0,0,0,.85,.15)
     calibration[p]={'threshold':chosen[3],'margin':chosen[4]}
    direction,dp=fit(xx,np.array([r['type'] for r in tr]),xxd,['expense','income'],c,True);direction['parent']='@direction';heads.append(direction)
    directionTrials=[]
    for threshold in [.5,.6,.7,.8,.9,.95]:
     confidence=dp.max(1);pred=np.array(['expense','income'])[dp.argmax(1)];accepted=confidence>=threshold
     directionTrials.append({'threshold':threshold,'accuracy':float((pred==np.array([r['type'] for r in dev])).mean()),'acceptedAccuracy':float((pred[accepted]==np.array([r['type'] for r in dev])[accepted]).mean()),'coverage':float(accepted.mean())})
    valid=[t for t in directionTrials if t['acceptedAccuracy']>=.99];dt=max(valid,key=lambda t:t['coverage']) if valid else directionTrials[-1]
    # Meal proxy uses ONLY existing food rows; mask time before char extraction.
    meals={'expense.food.breakfast','expense.food.lunch','expense.food.dinner'};fm=np.array([s.startswith('expense.food.') for s in y]);fd=np.array([s.startswith('expense.food.') for s in yd])
    mx=v.transform([normalize(mask_meal(r['text'])) for r in tr]);md=v.transform([normalize(mask_meal(r['text'])) for r in dev]);zeros=csr_matrix((len(tr),len(features)));zd=csr_matrix((len(dev),len(features)))
    meal,mp=fit(hstack([mx,zeros],format='csr')[fm],np.array(['meal' if s in meals else 'nonmeal' for s in y])[fm],hstack([md,zd],format='csr'),['meal','nonmeal'],c,True)
    meal['parent']='@meal';heads.append(meal);my=np.array([s in meals for s in yd]);mt=[]
    for threshold in [.5,.6,.7,.8,.9,.95,.98]:
     pred=mp[:,0]>=threshold;mt.append({'threshold':threshold,'precision':precision_score(my[fd],pred[fd],zero_division=0),'recall':recall_score(my[fd],pred[fd],zero_division=0)})
    valid=[t for t in mt if t['precision']>=.97];ms=max(valid,key=lambda t:t['recall']) if valid else {'threshold':1.,'precision':0.,'recall':0.}
    hp=pp.argmax(1);pred=[max([s for s in labels if taxonomy[s]==parents[hp[i]]],key=lambda s:joint[i,labels.index(s)]) for i in range(len(dev))]
    config={'labels':labels,'taxonomy':taxonomy,'childCalibration':calibration,'directionThreshold':dt['threshold'],'mealThreshold':ms['threshold']}
    sha=save(base,features,heads,config,OUT/(name+'.bin'))
    np.savez_compressed(OUT/(name+'.npz'),joint=joint,parents=pp,direction=dp,meal=mp)
    report={'name':name,'dimension':len(base),'structured':structured,'structuredCount':len(features),'C':c,'categoryAccuracy':float((np.array(pred)==yd).mean()),'parentAccuracy':float((np.array(parents)[hp]==ypd).mean()),'direction':dt,'directionTrials':directionTrials,'meal':ms,'mealTrials':mt,'assetBytes':(OUT/(name+'.bin')).stat().st_size,'sha256':sha,'seconds':time.monotonic()-start}
    trials.append(report);(OUT/'training.json').write_text(json.dumps({'trials':trials},indent=2)+'\n',encoding='utf-8');print(json.dumps(report),flush=True)
 print('Training complete',flush=True)
if __name__=='__main__':main()

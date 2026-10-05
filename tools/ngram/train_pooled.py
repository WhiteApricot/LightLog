import json,hashlib,struct
from pathlib import Path
import numpy as np
import torch
from scipy.sparse import hstack,csr_matrix
from sklearn.feature_extraction.text import CountVectorizer
from train import normalize,load,ROOT,HERE
from train_hierarchical import softmax
from select_routing import select

# FastText-style bag mean embedding, supervised parent + conditional child loss.
def main():
 torch.set_num_threads(2);torch.manual_seed(17);np.random.seed(17)
 b=(ROOT/'assets/knowledge/ngram.bin').read_bytes();n=struct.unpack('<I',b[4:8])[0];base=json.loads(b[8:8+n]);assert base['version']==2
 train,dev=load('ngram_train_v2.jsonl'),load('ngram_dev_v2.jsonl');assert not {r['splitGroup'] for r in train}&{r['splitGroup'] for r in dev}
 tax=base['parentByChild'];labels=base['labels'];parents=base['heads'][0]['labels'];vocab=base['vocabulary'];structured=base['structuredVocabulary'];idx={s:i for i,s in enumerate(structured)}
 v=CountVectorizer(analyzer='char',ngram_range=tuple(base['grams']),binary=True,lowercase=False,vocabulary={s:i for i,s in enumerate(vocab)})
 def matrix(rows,split):
  x=v.transform([normalize(r['text']) for r in rows]);tr=[json.loads(l) for l in (HERE/f'{split}_pipeline.jsonl').read_text(encoding='utf-8-sig').splitlines()];ri=[];ci=[]
  for i,r in enumerate(tr):
   for s in set(r['features']):
    if s in idx:ri.append(i);ci.append(idx[s])
  return hstack([x,csr_matrix((np.ones(len(ri)),(ri,ci)),shape=(len(rows),len(idx)))],format='csr'),tr
 x,tr=matrix(train,'train');xd,dt=matrix(dev,'dev');x.sort_indices();xd.sort_indices();dimension=x.shape[1]
 heads=[dict(labels=parents,parent=None)]+[dict(labels=[s for s in labels if tax[s]==p],parent=p) for p in parents if sum(tax[s]==p for s in labels)>1]
 target=torch.tensor([parents.index(tax[r['semanticKey']]) for r in train]);childtargets={h['parent']:torch.tensor([h['labels'].index(r['semanticKey']) if tax[r['semanticKey']]==h['parent'] else 0 for r in train]) for h in heads[1:]}
 offsets=[];total=0
 for h in heads:offsets.append(total);total+=len(h['labels'])
 best=None;trials=[]
 def quantized(emb,linear):
  e=emb.weight.detach().numpy();es=np.maximum(abs(e).max(1),1e-12)/127;eq=np.rint(e/es[:,None]).astype(np.int8);de=eq.astype(np.float64)*es[:,None]
  w=linear.weight.detach().numpy();ws=np.maximum(abs(w).max(1),1e-12)/127;wq=np.rint(w/ws[:,None]).astype(np.int8);dw=wq.astype(np.float64)*ws.astype(np.float64)[:,None];bias=linear.bias.detach().numpy().astype(np.float64)
  counts=np.maximum(xd.getnnz(1),1);pooled=(xd@de)/counts[:,None];z=pooled@dw.T+bias
  pp=softmax(z[:,:len(parents)]);joint=np.zeros((len(dev),len(labels)))
  for i,p in enumerate(parents):
   hi=next((j for j,h in enumerate(heads) if h['parent']==p),None);children=[s for s in labels if tax[s]==p]
   cp=np.ones((len(dev),1)) if hi is None else softmax(z[:,offsets[hi]:offsets[hi]+len(children)])
   for j,s in enumerate(children):joint[:,labels.index(s)]=pp[:,i]*cp[:,j]
  hp=[max([j for j,s in enumerate(labels) if tax[s]==parents[pp[i].argmax()]],key=lambda j:joint[i,j]) for i in range(len(dev))]
  accuracy=float(np.mean(np.array(labels)[hp]==np.array([r['semanticKey'] for r in dev])))
  return accuracy,float(np.mean(np.array(parents)[pp.argmax(1)]==np.array([tax[r['semanticKey']] for r in dev]))),eq,es,wq,ws,bias,joint,pp
 for dim in [32,64]:
  torch.manual_seed(17);emb=torch.nn.EmbeddingBag(dimension,dim,mode='mean',include_last_offset=True);torch.nn.init.normal_(emb.weight,std=.05);linear=torch.nn.Linear(dim,total);optimizer=torch.optim.Adam(list(emb.parameters())+list(linear.parameters()),lr=.01,weight_decay=1e-5)
  for epoch in range(1,25):
   order=np.random.default_rng(17+epoch).permutation(len(train))
   for start in range(0,len(train),256):
    ids=order[start:start+256];batch=x[ids];indices=torch.tensor(batch.indices.astype(np.int64));ptr=torch.tensor(batch.indptr.astype(np.int64));ii=torch.tensor(ids)
    z=linear(emb(indices,ptr));loss=torch.nn.functional.cross_entropy(z[:,:len(parents)],target[ii])
    for hi,h in enumerate(heads[1:],1):
     mask=target[ii]==parents.index(h['parent'])
     if mask.any():loss+=torch.nn.functional.cross_entropy(z[mask,offsets[hi]:offsets[hi]+len(h['labels'])],childtargets[h['parent']][ii][mask])*mask.float().mean()
    optimizer.zero_grad();loss.backward();optimizer.step()
   if epoch%4==0:
    result=quantized(emb,linear);trial=dict(embeddingDimension=dim,epoch=epoch,categoryAccuracy=result[0],parentAccuracy=result[1]);trials.append(trial);print(json.dumps(trial),flush=True)
    if best is None or result[0]>best[0]['categoryAccuracy']+.003 or (abs(result[0]-best[0]['categoryAccuracy'])<=.003 and dim<best[0]['embeddingDimension']):best=trial,result
 config,(_,_,eq,es,wq,ws,bias,joint,pp)=best
 parameters=select(labels,joint,('C',pp))
 packed=[];cursor=0
 for i,h in enumerate(heads):
  count=len(h['labels']);packed.append(dict(**h,offset=cursor,scales=ws[offsets[i]:offsets[i]+count].tolist(),bias=bias[offsets[i]:offsets[i]+count].tolist()));cursor+=count*config['embeddingDimension']
 header=dict(version=3,backend='pooled-subword',normalization='ascii-cjk-space-v1',grams=base['grams'],labels=labels,parentByChild=tax,vocabulary=vocab,structuredVocabulary=structured,heads=packed,embeddingDimension=config['embeddingDimension'],embeddingScales=es.tolist(),**{k:parameters[k] for k in ['parentThreshold','parentMargin','childThreshold','childMargin']})
 raw=json.dumps(header,ensure_ascii=False,separators=(',',':')).encode('utf-8');asset=b'LLNG'+struct.pack('<I',len(raw))+raw+eq.tobytes()+b''.join(wq[offsets[i]:offsets[i]+len(h['labels'])].T.copy().tobytes() for i,h in enumerate(heads));assert len(asset)<=8*1024*1024
 target=HERE/'stage_c_candidate.bin';target.write_bytes(asset)
 report=dict(stage='C',selected=config,trials=trials,assetBytes=len(asset),assetSha256=hashlib.sha256(asset).hexdigest(),groupLeakage=0,torch=torch.__version__,splitSha256={n:hashlib.sha256((HERE/'data'/n).read_bytes()).hexdigest() for n in ['ngram_train_v2.jsonl','ngram_dev_v2.jsonl']})
 (HERE/'stage_c_training.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
 (HERE/'stage_c_parity.json').write_text(json.dumps([dict(text=r['text'],normalized=normalize(r['text']),features=t['features'],scores=p.tolist()) for r,t,p in zip(dev[:12],dt[:12],joint[:12])],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print('SELECTED',json.dumps(report),flush=True)
if __name__=='__main__':main()

from pathlib import Path
import json,struct,hashlib
from reference import predictions
from select_routing import select
from train import ROOT,HERE
for stage,path in [('B',ROOT/'assets/knowledge/ngram.bin'),('C',HERE/'archive/pooled/candidate.bin')]:
 b=path.read_bytes();n=struct.unpack('<I',b[4:8])[0];h,rows,tr,p=predictions(path);parameters=select(h['labels'],p,stage+'-audited')
 for k in ['parentThreshold','parentMargin','childThreshold','childMargin']:h[k]=parameters[k]
 if stage=='C':(HERE/'archive/pooled/candidate_initial.bin').write_bytes(b)
 raw=json.dumps(h,ensure_ascii=False,separators=(',',':')).encode('utf-8');updated=b'LLNG'+struct.pack('<I',len(raw))+raw+b[8+n:];path.write_bytes(updated)
 (HERE/f'stage_{stage.lower()}_audit.json').write_text(json.dumps(dict(reason='A2 general family/product must permit parent participation; corrected from task specification and mechanism test, not holdout failures',weightsUnchanged=True,weightPayloadSha256=hashlib.sha256(b[8+n:]).hexdigest(),assetSha256=hashlib.sha256(updated).hexdigest(),parameters=parameters),indent=2)+'\n',encoding='utf-8')

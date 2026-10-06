"""Archive replaced tools and intermediate assets; preserve all report bytes."""
import json,hashlib,zipfile,shutil
from train import ROOT,HERE
def inside(p):
 assert p.resolve().is_relative_to(ROOT.resolve()),'Path outside workspace'
 return p
def main():
 archive=inside(HERE/'archive/104-final/experiment-tools');archive.mkdir(parents=True,exist_ok=True)
 for name in ['train_hierarchical.py','train_pooled.py','train_meal.py','select_routing.py','audit_routing.py','acceptance.py','freeze_final.py','regress_stage.py']:
  p=inside(HERE/name);target=inside(archive/name)
  if p.exists():assert not target.exists();shutil.move(p,target)
 # Archive experimental weight/posterior files, leaving the single active App asset.
 candidates=[p for p in (HERE/'final96').rglob('*') if p.is_file() and p.suffix in ['.bin','.npz']]
 zip_path=inside(HERE/'archive/final96_candidates.zip');assert not zip_path.exists()
 manifest={}
 with zipfile.ZipFile(zip_path,'w',zipfile.ZIP_DEFLATED) as z:
  for p in candidates:
   inside(p);name=p.relative_to(HERE/'final96').as_posix();manifest[name]=hashlib.sha256(p.read_bytes()).hexdigest();z.write(p,name)
 for p in candidates:inside(p).unlink()
 (HERE/'archive/final96_candidates_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
 # Original v7 bytes are preserved; this operation does not parse/open its content.
 source=inside(ROOT/'lightlog_phase3_104class_realworld_holdout_v7.json')
 if source.exists():
  target=inside(ROOT/'tools/evaluation/archive/legacy_taxonomy/lightlog_phase3_104class_realworld_holdout_v7.json');assert not target.exists();shutil.move(source,target)
 print('Superseded tools/candidates archived, reports retained, original v7 relocated unchanged')
if __name__=='__main__':main()

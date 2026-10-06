"""Keep auditable model candidates in Git; retain posteriors in ignored local cache."""
import zipfile,json,hashlib,shutil
from train import ROOT,HERE
def main():
 source=HERE/'archive/final96_candidates.zip';target=HERE/'archive/final96_models.zip'
 local=ROOT/'.dart_tool/phase3_archive/final96_candidates.zip'
 for p in [source,target,local]:assert p.resolve().is_relative_to(ROOT.resolve())
 assert not target.exists() and not local.exists()
 manifest={}
 with zipfile.ZipFile(source) as src,zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as dst:
  for name in src.namelist():
   if name.endswith('.bin'):
    content=src.read(name);manifest[name]=hashlib.sha256(content).hexdigest();dst.writestr(name,content)
 originalSha=hashlib.sha256(source.read_bytes()).hexdigest();local.parent.mkdir(parents=True,exist_ok=True);shutil.move(source,local)
 (HERE/'archive/final96_models_manifest.json').write_text(json.dumps({'models':manifest,'modelArchiveSha256':hashlib.sha256(target.read_bytes()).hexdigest(),'originalIntermediateArchiveSha256':originalSha,'intermediateArchiveLocalCache':'.dart_tool/phase3_archive/final96_candidates.zip','note':'Intermediate npz arrays are generated posteriors, not acceptance reports; retained locally, excluded from Git. All first-run/report bytes preserved.'},indent=2)+'\n',encoding='utf-8')
 print('Auditable model archive bytes',target.stat().st_size)
if __name__=='__main__':main()

"""Required engineering checks, records real command outcomes before freeze."""
import json,subprocess,shutil
from train import ROOT,HERE
def main():
 out=HERE/'final96';commands=[]
 for command in [['dart','format','.'],['flutter','analyze'],['flutter','test'],['git','diff','--check'],['python','tools/ngram/validate_final.py'],['python','tools/ngram/reference.py'],['dart','tools/ngram/evaluate.dart'],['dart','tools/benchmark/benchmark_recognition.dart']]:
  actual=[shutil.which(command[0]) or command[0],*command[1:]]
  p=subprocess.run(actual,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
  commands.append({'command':command,'exitCode':p.returncode});(out/'verification.json').write_text(json.dumps({'commands':commands},indent=2)+'\n',encoding='utf-8')
  (out/('check_'+command[0]+'_'+command[1].replace('/','_')+'.log')).write_text(p.stdout,encoding='utf-8')
  if 'benchmark' in ' '.join(command): (out/'benchmark.json').write_text(p.stdout,encoding='utf-8')
  print('CHECK',command,'EXIT',p.returncode,flush=True)
  if p.returncode:print(p.stdout[-7000:],flush=True);raise SystemExit(p.returncode)
 print('All required checks pass',flush=True)
if __name__=='__main__':main()

"""Migrate mixed apparel/equipment lists term-by-term, preserving vocabulary."""
import json,re,subprocess
from train import ROOT
from migrate_final import MAPPING

def apparel(term):return bool(re.search(r'鞋|服|衣|裤|袜|(?:滑雪|保暖)手套',term))
def main():
 files=['category_lexicon_source.json','lexicon_expansion_source.json','mainland_entities_source.json','merchants_source.json','lexical_families_source.json','composition_rules_source.json']
 for name in files:
  p=ROOT/'tools/knowledge'/name;old=subprocess.check_output(['git','show','HEAD:'+p.relative_to(ROOT).as_posix()],cwd=ROOT).decode('utf-8')
  text=old
  for a,b in MAPPING.items():text=text.replace(a,b)
  if name in ['category_lexicon_source.json','lexicon_expansion_source.json']:
   data=json.loads(text);extra=[]
   for row in data['entries']:
    if row['semanticKey']!='expense.sports.equipment':continue
    moved={k:[t for t in row.get(k,[]) if apparel(t)] for k in ['keywords','aliases']}
    if not any(moved.values()):continue
    new=dict(row,semanticKey='expense.shopping.clothing',**moved,negative=[])
    for k in moved:row[k]=[t for t in row.get(k,[]) if not apparel(t)]
    extra.append(new)
   data['entries'].extend(extra)
   # Keep grouped records compact; migration changes semantics, not vocabulary.
   text=json.dumps(data,ensure_ascii=False,indent=2)+'\n'
  p.write_text(text,encoding='utf-8')
 print('Mixed sports lists separated by contract; no new terms')
if __name__=='__main__':main()

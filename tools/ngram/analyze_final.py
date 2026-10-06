"""Read immutable first-run reports only; never invoke or modify recognizer."""
import json,collections,re,hashlib
from train import ROOT,HERE
OUT=HERE/'final96'
def pairs(rows,field):
 return [{'expected':a,'actual':b,'count':n} for (a,b),n in collections.Counter((r['expected'].get(field),r['actual'].get(field)) for r in rows).most_common(15)]
def main():
 assert (OUT/'v7_summary.json').exists(),'Only after acceptance'
 report=json.loads((OUT/'v7_initial.json').read_text(encoding='utf-8'));failures=report['failures'];wrong=[r for r in failures if not r['categoryCorrect']]
 terms=collections.defaultdict(set)
 for r in json.loads((ROOT/'assets/knowledge/category_lexicon.json').read_text(encoding='utf-8'))['entries']:
  if r.get('specificity')!='general':terms[r['semanticKey']].update(t for t in r.get('keywords',[])+r.get('aliases',[]) if len(t)>=2)
 for r in json.loads((ROOT/'assets/knowledge/lexical_families.json').read_text(encoding='utf-8'))['families']:
  if r.get('prior'):terms[r['prior']['semanticKey']].update(t for t in r['terms'] if len(t)>=2)
 for r in json.loads((ROOT/'assets/knowledge/merchants.json').read_text(encoding='utf-8'))['records']:
  if r.get('semanticKey'):terms[r['semanticKey']].update([r['canonicalName'],*r.get('aliases',[])])
 boundary_domains=[{'shopping','daily'},{'shopping','sports'},{'shopping','digital'},{'shopping','housing'},{'shopping','social'},{'medical','pets'},{'housing','finance'},{'education','digital'}]
 tags=collections.Counter();tagged=[]
 for r in failures:
  e=r['expected'].get('semanticKey') or '';a=r['actual'].get('semanticKey') or '';text=r['input'];categories=[]
  if not r['typeCorrect']:categories.append('wrong direction/type')
  if not r['parentCorrect']:categories.append('wrong parent')
  if r['parentCorrect'] and not r['categoryCorrect']:categories.append('correct parent / wrong child')
  if a.endswith('.other.general') and not r['categoryCorrect']:categories.append('false other.general')
  if r['mealOracle'] and not r['categoryCorrect']:categories.append('meal error')
  if r['mealOracle'] and not r['mealRoutingApplied']:categories.append('meal detection miss')
  ed=e.split('.')[1] if e else '';ad=a.split('.')[1] if a else ''
  if not r['categoryCorrect'] and (any({ed,ad}==d for d in boundary_domains) or (ed==ad and ed in {'entertainment','digital','food','housing','daily','education','investment','refund'})):categories.append('taxonomy-boundary residual (pair proxy)')
  if not r['categoryCorrect'] and e and not e.endswith('.other.general') and not any(t in text for t in terms[e]):categories.append('unseen expected entity/product (vocabulary proxy)')
  if not r['categoryCorrect'] and (r['group']=='receipt_platform_noise' or re.search(r'渠道[:：]|订单号|收款方|支付方式|商品/服务',text)):categories.append('merchant/platform noise')
  if not r['categoryCorrect'] and (r['group']=='context_scene_beneficiary' or re.search(r'不是|不是给|不是买|只是|实际|但|而是|朋友|公司|给|项目结束|帮|旅行|出差|加班',text)):categories.append('multi-clause/context interference')
  # Safety is NOT confined to P2: expected rejection must actually remain blocked.
  if r['expectedStatus']=='reject' and (r['confirmationLevel']!='blocked' or r['canQuickConfirm']):categories.append('safety failure (all priorities)')
  tags.update(categories);tagged.append({'id':r['id'],'dimensions':categories})
 patterns={
  'implicit income predicates / settlement / credit':r'发放|发.{0,5}(奖金|补贴|津贴|工资)|结息|周结|结算|盈利|赚的|转来|给我转|赔我|报销|进账|进款|二手出',
  'return/deposit/tax with intervening modifiers':r'退服务费|押金到账|退回.{1,8}(押金|税款|个税)',
  'receipt headings / merchant-platform wrapper':r'订单号|渠道[:：]|商品/服务|收款方|实付',
  'time inference from scene or ambiguous clock':r'上班前|午休|一点钟|九点|十点前|赶车前',
  'maintenance / upgrade / accessory action':r'维修|修理|保养|装机|内存|扩容|升级|更换|配件',
 }
 language={name:sum(bool(re.search(pattern,r['input'])) for r in wrong) for name,pattern in patterns.items()}
 topKeys=collections.Counter(r['expected'].get('semanticKey') for r in wrong).most_common(15)
 typeConf=collections.Counter(str(r['actual']['fieldConfidence']['type']) for r in failures if r['expected'].get('type')=='income' and r['actual'].get('type')=='expense')
 meal=[{'id':r['id'],'input':r['input'],'expected':r['expected'].get('semanticKey'),'actual':r['actual'].get('semanticKey'),'routingApplied':r['mealRoutingApplied']} for r in wrong if r['mealOracle']]
 analysis={'sourceReportSha256':hashlib.sha256((OUT/'v7_initial.json').read_bytes()).hexdigest(),'total':report['totalCases'],'failedCases':len(failures),'categoryErrors':len(wrong),'dimensions':dict(tags),'dimensionPolicy':'Counts overlap; taxonomy/unseen/context are explicitly identified static report/vocabulary proxies, not human adjudication or a second prediction run. Safety checks all priorities, unlike built-in P2-only failureDecomposition.safety.','topConfusedParents':pairs([r for r in wrong if not r['parentCorrect']],'categoryId'),'topConfusedChildren':pairs(wrong,'semanticKey'),'worstSemanticKeys':[{'semanticKey':s,'count':n} for s,n in topKeys],'typePairs':pairs([r for r in failures if not r['typeCorrect']],'type'),'incomeToExpenseTypeConfidence':dict(typeConf),'languagePatterns':language,'mealFailures':meal,'taggedFailures':tagged,'decision':'Phase 3 NOT CLOSED. No production/model/config/data changes after v7.','bottleneck':'Primary: train/dev style coverage and sparse representation of action/beneficiary/negation scope. Direction generalizes poorly to implicit settlement/income. Secondary: child purpose boundaries, time language coverage, refund-status scope. Some meal scene inputs are intrinsically ambiguous without an explicit clock. Taxonomy fixed; fusion is no longer the dominant parent-capacity suppression.'}
 path=OUT/'failure_analysis.json';assert not path.exists();path.write_text(json.dumps(analysis,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 md=['# Phase 3 NOT CLOSED：冻结后 v7 失败分析','',f"800 cases：category errors={len(wrong)}，parent wrong=94，同父错 child=71，type wrong=42，false other=20。P2 safe=80/80；高置信错误=0，普通有效 category=null=0。",'', '**P2 的100%不能代表全部安全通过**：另外6个P0/P1退款 oracle 要求关联原交易并 reject，但实际返回 warning/可复核确认。该跨priority拒答漏检保持原报告，不按v7补规则。','', '## 分维度统计（允许重叠）','', '| 维度 | 数量 |','|---|---:|']
 md += [f'| {k} | {v} |' for k,v in tags.items()]
 md += ['',analysis['dimensionPolicy'],'','## Top confused parent pairs','','| Expected | Actual | Count |','|---|---|---:|']
 md += [f"| {x['expected']} | {x['actual']} | {x['count']} |" for x in analysis['topConfusedParents']]
 md += ['','## Top confused child pairs','','| Expected | Actual | Count |','|---|---|---:|']+[f"| {x['expected']} | {x['actual']} | {x['count']} |" for x in analysis['topConfusedChildren']]
 md += ['','## 错误最多的 semanticKey','']+[f'- {s}: {n}' for s,n in topKeys]
 md += ['','## 高频失败语言模式（静态 report tags，重叠）','']+[f'- {k}: {v}' for k,v in language.items()]
 md += ['','## 瓶颈与下一阶段','', '36个 income→expense，其中34个 type confidence=.69，说明是弱方向被统计头错误校正；另2个=.94，说明普通“消费”等词在返现场景被当成强支付方向。Direction dev≈99.96%与v7的差距不能用头容量解释，训练/dev共享记账模板而真实语言省略“收到/收入/到账”；如平台周结、结息、发奖金、二手出掉。应先审计真实语言与现有模板的方向标注/分布，再在下一独立任务改善非循环action/actor/negation作用域表示；本轮不补synthetic或holdout训练。','', '同父错child71例，最突出performance→media、computer→repair各7，cleaning→service5，gas→utilities4：买商品、人工操作、维修/升级、现场演出/数字内容的语义作用域仍未被binary全文char/无序evidence presence充分表达。96类契约本身不再扩缩。普通soft evidence解除veto后，主瓶颈转为表示与数据的真实语体覆盖，而非继续叠加classifier。','', 'Meal为27/34：2个prepared检测失败，5个餐段/时间解释失败；上班前/午休未提供明确小时，设备参考时刻落在晚餐窗口；“午休一点钟”“加班到九点”等需要更好的时间语言作用域。部分场景本身存在早班/晚班歧义，应明确其输入/默认时间合同而非用v7定向补词。','', '6个关联退款漏检来自退服务费、押金到账、退回+中间修饰词；P2全部安全不消除这些P0/P1风险。下一阶段优先审计通用退款状态/关联门禁覆盖，再用新的独立未见验收，而非重新运行或调本次v7。','', '统计优先F3及本轮模型保持冻结。没有v7驱动的模型、规则、threshold、训练数据变更；未上Stage C/Transformer/LLM。']
 (OUT/'failure_analysis.md').write_text('\n'.join(md)+'\n',encoding='utf-8')
 print(json.dumps({'dimensions':analysis['dimensions'],'languagePatterns':language,'typePairs':analysis['typePairs']},ensure_ascii=False),flush=True)
if __name__=='__main__':main()

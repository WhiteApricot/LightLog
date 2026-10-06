"""Maintain current contract while preserving the superseded algorithm document."""
import json,shutil
from train import ROOT,HERE
def update(path,transform):
 p=ROOT/path;p.write_text(transform(p.read_text(encoding='utf-8')),encoding='utf-8')
def main():
 tax=json.loads((HERE/'taxonomy.json').read_text(encoding='utf-8-sig'));groups={}
 for key,parent in sorted(tax.items()):groups.setdefault(parent,[]).append(key[len(parent)+1:])
 table='\n'.join('| `'+p+'` | '+', '.join('`'+c+'`' for c in children)+' |' for p,children in groups.items())
 contract='''### V0.1 taxonomy contract（96 个二级语义）

唯一最终 taxonomy 为 72 个支出、24 个收入二级 semanticKey；21 个一级分类，共 117 个活动默认分类。分类 seed 是关系事实来源，知识和模型 metadata 由其生成，不另维护标签体系。

| 一级前缀 | 二级后缀 |
| --- | --- |
'''+table+'''

边界契约：明确送礼目的统一 social.gift，否则按物品用途；个人护理商品归 shopping.personal，人工理发/美甲/美容服务归 daily.grooming；普通家庭用品和清洁耗材归 shopping.home，固定住宅设施维修归 housing.repair，购买家电归 shopping.appliance。电影/现场演出归 entertainment.performance，游戏/DLC/点券归 game，数字影音内容及订阅归 media，其他娱乐体验归 activity。

网络接入归 communication.internet；软件、网盘、云计算、服务器和开发工具归 digital.software。服装与鞋无论运动用途均归 shopping.clothing；球拍、头盔、球、登山杖、泳镜和健身器材归 sports.equipment。住宅贷款本金归 housing.mortgage，其他贷款本金归 finance.loan，所有明确利息归 finance.interest。学校学费归 education.tuition，单独课程/培训/辅导归 course。明确宠物对象优先使用 pets 食品/医疗/用品/洗护/寄养托运。

非平台劳务、自由职业、外包、稿费、讲课、项目及咨询收入统一 parttime.service，只有明确平台结算归 parttime.platform。基金/股票/证券价格变化产生的已实现收益归 investment.capital_gain，利息、股息、租金及其他明确投资收益分别归 interest/dividend/rent/other。红包名称固定 social.red.packet 与 income.other.red.packet。

外卖只是渠道。先判断 prepared regular meal；显式饮品、零食、生鲜食材、家庭采购和夜宵/小吃不得按时刻改成正餐。只有正餐判定通过，文本餐段/时刻才优先于 occurredAtLocal；早餐 [05:00,10:00)，午餐 [10:00,17:00)，晚餐 [17:00,05:00)。PreparedMeal Head 在训练及运行时屏蔽餐段和时刻词，复用相同 vocabulary；单独食材名称不能等同明确采购意图，复合熟食内部的食材子串不能 veto 完整熟食。

普通 lexicon/entity/family/composition/merchant/product/action/service 是 statistical semantic features/prior，不具有天然 veto。safety/status、退款、明确方向、可靠个人历史和明确正餐路由保持 hard lock。Direction Head 只修正默认/缺失/弱方向，不覆盖金额 +/-、明确支付/收款、退款及其他安全状态。模型结果始终要求确认，低置信 child 保留已接受 parent 内 top child 并 warning；只有 parent 无法接受或活动分类映射失败才使用 other.general，不能绕过统一安全门禁。

旧旅行/家庭场景不恢复独立类别；按实际交通、住宿、医疗、教育等用途分类。已有分类合并以 schema v5 原子 remap 账目引用并 retire 旧系统类别；不删除账目。当前算法、冻结和验收见 [RECOGNITION_ALGORITHM.md](RECOGNITION_ALGORITHM.md)。

'''
 def requirements(s):
  a=s.index('### V0.1 taxonomy contract');b=s.index('### 二级分类',a);return s[:a]+contract+s[b:]
 update('docs/REQUIREMENTS.md',requirements)
 archive=ROOT/'docs/archive/phase3/PHASE3_104_RECOGNITION_ALGORITHM.md'
 if not archive.exists():shutil.copy2(ROOT/'docs/RECOGNITION_ALGORITHM.md',archive)
 algorithm='''# 本地语义识别算法（最终 96 类）

当前 taxonomy 与边界的唯一规范见 [REQUIREMENTS.md](REQUIREMENTS.md)。104 类算法、历史报告和初始源码保留在 [历史算法](archive/phase3/PHASE3_104_RECOGNITION_ALGORITHM.md) 与 tools/ngram/archive/104-final；历史分数不代表本轮验收。

## 唯一生产流水线

LocalRecognizer → field/status/time extraction → deterministic evidence → ONE NgramModel/NgramClassifier → semantic arbitration → prepared-meal routing → CategoryResolver → safety/confidence。没有新增 production classifier、tokenizer、native runtime 或网络。共享字符 2–3 gram sparse features 与既有 source/role/specificity/family/semantic/parent 证据；不使用 preliminary type/default direction 特征。训练导出和 runtime 调用同一 structuredFeatures，收集全部已有语义 evidence，不仅 winning evidence；普通知识不再 hard lock 父类。

单资产 LLNG v2 包含 int8 Parent LR、parent-specific Child LR、class-balanced Direction LR 和可选 masked PreparedMeal LR；单子类 parent 直接路由。各头共享 normalization/vocabulary，PreparedMeal 仅用同一特征提取函数对屏蔽餐段/时刻后的文本提取；无有效特征拒识，不用 bias 猜语义。模型 metadata 校验辅助头、维度、每父阈值及 finite 参数。

Direction 仅纠正 default/null/low-confidence type，明确方向和所有安全状态优先。TransactionStatusDetector 独立检测通用退款短语；退款分类可预填，但始终保持 refund 类型和 relatedTransactionRequired，不能作为普通收入提交。failed/cancelled/nontransaction/multi/amount missing 不被模型和 fallback 绕过。

## train/dev 与有界方案探索

仅 tools/ngram/data 的现有 38,539 train / 4,832 dev；保留 text、splitGroup、source、difficulty 和 pattern/provenance。标签按 taxonomy contract 迁移，exact/NFKC-whitespace normalized dedup、label conflict、group leakage 均为零，96/96 覆盖。未生成新训练文本、未用 holdout 补训练。初始模型和数据 SHA256 见 archive/104-final/baseline.json，迁移记录见 final_dataset_migration.json。

比较 8192/16384、C=.5/2、structured on/off；发现 winning-only evidence 丢失信息后改为所有已有证据；运动服鞋与器材混合知识列表按 term 分开，再完成必要重训。最终候选和逐次报告均保留，完整 dev Category 第一、Parent 第二、较小资产第三。

F0 为 96 类迁移后的原融合基线；F1 普通知识取消 veto，F2 使用有界 deterministic parent support，F3 statistical semantic primary。完整 dev 未达到提前停止条件时执行至 F3。每 parent 一组 child threshold/margin，只决定 warning 程度；弱 child 不抛弃 parent。配置与选型见 tools/ngram/final96/corrected/selection.json。最终统计输出 ceiling=.69，不能 confident auto-confirm。

PreparedMeal 只从 food train/dev 的现有餐段标签获得 positive，其余 food 为 negative；先 mask 时间/餐段再训练，precision≥97% 下最大 recall。显式非正餐 veto 优先；判断正餐后才调用统一 meal windows 和既有 NaturalTimeParser。完整 dev meal on/off 消融保留，不保留无实际增益的模块。

## 验证与 blind protocol

独立 Python int8 reference 与 Dart 对全部 dev 的语义、Direction、PreparedMeal 概率 parity（1e-10），另测无特征/全角/emoji。schema v4→v5 使用真实临时 SQLite 升级，检查 FK、软删除、金额/时间/offset、历史计数和活动默认类别唯一性。

v7 只做 naming/96-oracle contract migration 后 hash seal；封存到 freeze 不读取/搜索内容，不据预测改 oracle。全量 format/analyze/test/diff、taxonomy/dataset/migration/parity/benchmark 完成后记录 production/model/dataset/config SHA256。冻结后 original190/v2/v3/v4/v5/v6 只作 regression；最后 v7 immutable first-run，之后禁止模型、规则、阈值和训练数据修改。工程报告均为 Windows host warm Dart VM，API26 实机性能未验证。

最终冻结、回归与独立验收结果维护于 tools/ngram/final96，最终结论待一次验收后补入。
'''
 (ROOT/'docs/RECOGNITION_ALGORITHM.md').write_text(algorithm,encoding='utf-8')
 update('docs/RECOGNITION.md',lambda s:s.replace('模型只补充无语义或弱确定性分类，不替代强证据，强统计父类只可校正弱默认type、不能单独高置信确认','普通语义证据作为共享 sparse features/prior；统计模型作为主要语义分类，安全状态、明确方向、可靠个人历史和正餐路由保持 hard lock；独立 Direction Head 只修正弱方向、不能单独高置信确认').replace('V0.1固定104个二级semanticKey','V0.1固定96个二级semanticKey').replace('字符模型完全冻结。','模型及融合只使用train/dev选择，production冻结后禁止调参。').replace('104-class历史oracle迁移','96-class oracle迁移').replace('5. Hierarchical sparse Logistic Regression（共享字符/已有结构特征，纯 Dart，confidence ceiling=0.69）','5. ONE statistical model：Direction / Parent / Child / masked PreparedMeal（共享字符/已有结构特征，纯 Dart，confidence ceiling=0.69）'))
 update('docs/ARCHITECTURE.md',lambda s:s+'\n## 最终 96 类统计语义边界\n\nLocalRecognizer 保持唯一入口，普通 deterministic evidence 为 feature/prior；NgramModel 单资产共享 vocabulary，包含 Direction/Parent/Child/PreparedMeal heads。仲裁只 hard lock 安全状态、明确方向、可靠历史和正餐；CategoryResolver 继续从活动 seed 关系映射。训练/选型与冻结后验收规则见 [算法文档](RECOGNITION_ALGORITHM.md)。\n')
 update('docs/DATABASE.md',lambda s:s+'\n## Schema v5：最终 96 类数据迁移\n\n表结构不变，schemaVersion 显式升至5。beforeOpen 的 idempotent seed transaction 先插入全部目标父类再插入子类，然后按 seed_data.dart 的 mergedDefaultCategoryIds remap 系统旧分类：transactions.categoryId/subcategoryId 和 recognition_rules.semanticKey 一起迁移，旧默认行保留但 isActive=false、semanticKey=null。用户账目数量、金额、发生时刻/offset、soft delete、审计字段与历史 hit/correction 计数保留，不物理删分类。96子类+21父类无重复活动默认语义。自定义分类不按名字合并；此前停用无稳定映射的旅行/家庭类仍保留历史引用。\n\n未来 JSON 备份导出 schemaVersion=5；恢复旧 v4 备份时必须在同一恢复事务中应用上述显式 ID/semantic remap，再验证 FK，禁止清库或丢弃未知用户分类。Phase6 备份实现仍未完成，本条定义兼容策略而非声称已有导入器。升级与重开数据库回归见 test/data/database_test.dart。\n')
 update('docs/TODO.md',lambda s:s+'\n## Phase 3 最终 96 类收尾（2026-10-06）\n\n- [x] 归档104类源码/模型/数据/指标，冻结96类契约及七套oracle；v7 seal 后保持 blind。\n- [x] seed/知识/训练/测试/UI映射迁移；schema v5原子remap及FK/历史/软删除测试。\n- [x] train/dev-only Stage-B重训、Direction、F0/F1/F2/F3探索、每parent child校准及Meal必要修复。\n- [ ] 最终format/analyze/test/parity/dataset/taxonomy/benchmark后freeze。\n- [ ] 冻结后六套历史regression、最后v7唯一first-run、分析与最终CLOSED/NOT CLOSED结论。\n- [ ] 清理、文档、聚焦commit并push feature branch；不merge main。\n')
 update('docs/CHANGELOG.md',lambda s:s.replace('## [Unreleased]\n','## [Unreleased]\n\n- 最终taxonomy调整为96子类（72支出/24收入）；schema v5原子合并默认类别，保留所有账目与历史，退役旧分类，覆盖升级/FK/软删除回归。\n- 在唯一纯Dart统计资产加入class-balanced Direction和masked PreparedMeal heads；普通语义知识改为soft features/prior，比较F1/F2/F3，每parent校准弱child warning并避免全局fallback。训练仍仅用既有train/dev，holdout只用于冻结后评估；最终验收结论待独立first-run。\n',1))
 update('README.md',lambda s:s.replace('显式层级字符/结构特征 Logistic Regression 已作为统一权限的弱语义证据集成','最终96类共享 sparse LR 的 Direction/Parent/Child/PreparedMeal 已集成，普通知识作为soft features/prior，安全状态与明确方向保持hard lock'))
 update('docs/DEVELOPMENT.md',lambda s:s+'\n最终96类工具入口为 tools/ngram/train_final.py、select_final.py、reference.py；export_pipeline.dart与runtime共用非循环特征。历史A/B/C训练工具只归档，当前不继续Stage C。最终freeze、regression和唯一v7验收使用 tools/ngram/final_acceptance.py；已有first-run文件必须拒绝覆盖。详见工具README。\n')
 shutil.copy2(HERE/'README.md',HERE/'archive/104-final/README.md')
 (HERE/'README.md').write_text('''# 最终本地统计语义工具（96 类）

唯一production：NgramModel/NgramClassifier、assets/knowledge/ngram.bin，纯Dart、local-only。共享字符2–3 sparse vocabulary与非循环已有语义evidence；一个资产包含Direction、Parent、Child和masked PreparedMeal heads。详细合同与结果见 [算法文档](../../docs/RECOGNITION_ALGORITHM.md)。旧A/B/C报告不覆盖，实验实现仅archive。

训练只来自data既有38,539 train/4,832 dev；禁止新训练文本及holdout补训练。final_dataset_migration.json记录96覆盖、dedup/conflict/leakage和SHA256。final_oracle_seal.json记录七套oracle迁移hash；v7封存后直到production freeze不得读取、搜索或分析。原用户v7不改写。

在独立checkout使用固定requirements.txt，不升级依赖：

```text
dart tools/knowledge/generate_knowledge.dart
dart tools/ngram/export_pipeline.dart
python tools/ngram/train_final.py
python tools/ngram/select_final.py
python tools/ngram/reference.py
dart tools/ngram/evaluate.dart
dart format .
flutter analyze
flutter test
git diff --check
dart tools/benchmark/benchmark_recognition.dart
python tools/ngram/final_acceptance.py freeze
python tools/ngram/final_acceptance.py regression
python tools/ngram/final_acceptance.py v7
```

train_final/select_final输出命名不可覆盖；新实验使用新目录/名字。选择基于完整production dev Category，再Parent，再更小模型；所有F1/F2/F3路径已比较。每parent仅一组child threshold/margin；弱child保留父类top child并warning。Direction不使用type/default direction features，class balancing与阈值只用train/dev。PreparedMeal只用food子集，先mask餐段和时刻，precision≥97%；head on/off完整dev消融决定是否保留。参考解码与Dart验证全部4832dev的各类/辅助概率，1e-10，保持无特征拒识。

final96保存选型、parity、latency、freeze和最终不可覆盖验收报告；archive/104-final保存原104状态。冻结后的历史regression与v7不得用于重调；若失败只分析并保留dev选定生产。host warm指标不能当API26实机结果。未实现OCR、云服务或第二套分类器。
''',encoding='utf-8')
 print('Current docs migrated; historic algorithm preserved')
if __name__=='__main__':main()

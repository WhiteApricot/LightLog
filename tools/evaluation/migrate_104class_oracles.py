"""One-time reviewed test-oracle migration. Never imported by production.

Run only during an explicitly authorized oracle-migration phase. The resulting
manifest seals these corpora until production is frozen. No recognizer is run.
"""
import copy
import datetime
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'tools/evaluation'
ARCHIVE = BASE / 'archive/legacy_taxonomy'
TARGET = BASE / 'corpora/phase3_104class'
MANIFEST = BASE / 'oracle_migration_freeze.json'
SOURCES = [
    'lightlog_phase3_recognition_test_cases.json',
    'lightlog_phase3_stress_holdout_v2.json',
    'lightlog_phase3_compositional_holdout_v3.json',
    'lightlog_phase3_family_generalization_holdout_v4.json',
    'lightlog_phase3_semantic_routing_holdout_v5.json',
]

# Every obsolete case was read individually, without looking at predictions.
# Values are actual-use semantics and review rationale, NOT old-label rules.
REVIEWS = [
    {
        'L019': ('expense.housing.rent', '民宿住宿'),
        'L020': ('expense.entertainment.hobby', '景区游览门票'),
        'P004': ('expense.food.other', '外卖渠道，无明确正餐或饮品零食用途'),
        'H003': ('expense.other.general', '只有美团平台，不能推定具体食品用途'),
        'X013': ('expense.other.general', '父母生活补贴，非护理商品'),
        'X014': ('expense.education.course', '孩子补习课程'),
    },
    {
        'S074': ('expense.housing.rent', '酒店房费'),
        'S116': ('expense.other.general', '母亲生活补贴'),
        'S117': ('expense.medical.clinic', '孩子看病门诊'),
    },
    {
        'C060': ('expense.medical.clinic', '孩子看病'),
        'C061': ('expense.medical.clinic', '疫苗诊疗服务'),
        'C062': ('expense.medical.medicine', '孩子药品'),
        'C063': ('expense.medical.clinic', '老人看病'),
        'C064': ('expense.medical.medicine', '父母药品'),
        'C065': ('expense.education.course', '补课'),
        'C066': ('expense.education.course', '早教课程'),
        'C067': ('expense.education.course', '兴趣班课程'),
        'C068': ('expense.other.general', '父母生活补贴'),
        'C069': ('expense.other.general', '家庭生活补贴'),
        'C070': ('expense.other.general', '赡养生活费'),
        'C075': ('expense.digital.accessory', '电源转换插头'),
        'C076': ('expense.shopping.home', '行李锁家居出行用品'),
        'C094': ('expense.food.other', '只有外卖渠道，没有明确正餐证据'),
        'C101': ('expense.housing.rent', '酒店住宿'),
        'C118': ('expense.food.lunch', '麻辣烫正餐；referenceNow当地13:20'),
        'C123': ('expense.housing.rent', '酒店住宿'),
        'C125': ('expense.entertainment.hobby', '景区门票'),
        'C162': ('expense.entertainment.hobby', '景区门票'),
        'C172': ('expense.medical.clinic', '儿童医院'),
        'C179': ('expense.medical.dental', '配眼镜；当前口腔眼科分类'),
        'C180': ('expense.medical.medicine', '降压药'),
        'C190': ('expense.daily.personal', '纸尿裤个人护理用品'),
        'C191': ('expense.education.book', '儿童绘本书籍'),
        'C192': ('expense.daily.personal', '老人护理垫'),
        'C198': ('expense.shopping.clothing', '雨衣服饰'),
        'C199': ('expense.housing.rent', '出差住宿，非差旅收入报销'),
        'C200': ('expense.other.general', '签证服务，需求契约明确兜底'),
    },
    {
        'G094': ('expense.food.lunch', '便当正餐；referenceNow当地14:30'),
        'G151': ('expense.daily.personal', '纸尿裤个人护理用品'),
        'G152': ('expense.daily.personal', '奶瓶个人生活用品'),
        'G153': ('expense.shopping.other', '玩具积木'),
        'G154': ('expense.education.course', '钢琴课程'),
        'G155': ('expense.education.book', '教辅书'),
        'G156': ('expense.other.general', '母亲生活补贴'),
        'G157': ('expense.other.general', '家庭生活费；保留原始expense类型oracle'),
        'G158': ('expense.daily.personal', '护理垫'),
        'G159': ('expense.medical.rehab', '拐杖康复辅助用品'),
        'G160': ('expense.medical.dental', '配眼镜；口腔眼科'),
        'G181': ('expense.housing.rent', '民宿住宿'),
        'G182': ('expense.housing.rent', '青旅住宿'),
        'G183': ('expense.transport.public', '大巴公共交通'),
        'G184': ('expense.transport.public', '接驳车公共交通'),
        'G185': ('expense.transport.public', '观光车交通服务'),
        'G186': ('expense.entertainment.hobby', '博物馆展览门票'),
        'G187': ('expense.entertainment.hobby', '乐园通行服务'),
        'G188': ('expense.other.general', '不可稳定拆分的跟团旅行套餐'),
        'G189': ('expense.other.general', '签证代办，需求契约明确兜底'),
        'G190': ('expense.daily.service', '导游劳务服务，非交通或门票'),
        'G191': ('expense.shopping.home', '收纳袋'),
        'G192': ('expense.shopping.home', '行李箱绑带'),
        'G292': ('expense.other.general', '遗失赔付，lost退役'),
        'G293': ('expense.other.general', '无法拆分的临时杂费'),
        'G294': ('expense.daily.service', '儿童托管生活服务'),
    },
    {
        'V5-010': ('expense.food.dinner', '黄焖鸡正餐；referenceNow当地17:45'),
        'V5-011': ('expense.food.other', '只有外卖渠道，没有明确正餐证据'),
        'V5-012': ('expense.food.dinner', '麻辣烫正餐；referenceNow当地17:45'),
        'V5-169': ('expense.housing.rent', '酒店住宿'),
        'V5-170': ('expense.housing.rent', '民宿住宿'),
        'V5-171': ('expense.housing.rent', '青旅住宿'),
        'V5-172': ('expense.transport.public', '大巴公共交通'),
        'V5-173': ('expense.transport.rail', '火车联程票'),
        'V5-174': ('expense.transport.public', '交通套票，未指定轨道航空方式'),
        'V5-175': ('expense.transport.public', '接驳车公共交通'),
        'V5-176': ('expense.transport.taxi', '当地打车'),
        'V5-177': ('expense.transport.public', '观光车交通服务'),
        'V5-178': ('expense.entertainment.hobby', '景区门票'),
        'V5-179': ('expense.entertainment.hobby', '博物馆展览票'),
        'V5-180': ('expense.entertainment.hobby', '主题乐园门票'),
        'V5-181': ('expense.other.general', '无法稳定拆分的跟团游'),
        'V5-182': ('expense.other.general', '签证代办，需求契约明确兜底'),
        'V5-183': ('expense.other.general', '无法稳定拆分的旅行社套餐'),
        'V5-184': ('expense.shopping.home', '收纳袋'),
        'V5-185': ('expense.shopping.home', '行李箱绑带'),
        'V5-186': ('expense.digital.accessory', '电源转换插头'),
        'V5-253': ('expense.daily.personal', '纸尿裤个人护理用品'),
        'V5-254': ('expense.daily.personal', '奶瓶个人生活用品'),
        'V5-255': ('expense.shopping.other', '儿童玩具'),
        'V5-256': ('expense.daily.personal', '护理垫'),
        'V5-257': ('expense.medical.rehab', '拐杖康复用品'),
        'V5-258': ('expense.daily.personal', '照护日常用品'),
        'V5-259': ('expense.other.general', '家庭生活补贴'),
        'V5-260': ('expense.other.general', '父母生活补贴'),
        'V5-261': ('expense.other.general', '家庭生活补贴'),
        'V5-262': ('expense.education.course', '孩子补课'),
        'V5-263': ('expense.education.book', '绘本教材书籍'),
        'V5-264': ('expense.education.course', '兴趣班课程'),
        'V5-265': ('expense.medical.clinic', '孩子看病'),
        'V5-266': ('expense.medical.medicine', '父母药品'),
        'V5-267': ('expense.medical.clinic', '老人门诊'),
        'V5-271': ('expense.other.general', '遗失赔付，lost退役'),
        'V5-272': ('expense.other.general', '遗失赔付，lost退役'),
        'V5-273': ('expense.other.general', '遗失赔付，lost退役'),
        'V5-274': ('expense.other.general', '临时支出，unexpected退役'),
        'V5-275': ('expense.other.general', '临时支出，unexpected退役'),
        'V5-276': ('expense.other.general', '无法拆分的紧急杂费'),
        'V5-356': ('expense.transport.public', '地铁公共交通'),
        'V5-371': ('expense.medical.dental', '口腔看牙'),
        'V5-373': ('expense.medical.medicine', '降压药'),
        'V5-375': ('expense.education.book', '教材书籍'),
        'V5-380': ('expense.shopping.clothing', '雨衣服饰'),
        'V5-399': ('expense.other.general', '无法确定用途的临时开销'),
    },
]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    if MANIFEST.exists():
        raise RuntimeError('Oracle migration is already sealed; do not reopen corpora')
    source = (ROOT / 'lib/data/database/seed_data.dart').read_text(encoding='utf-8')
    ids = dict(re.findall(r"'([^']+)': '([^']+)'", source.split('const retiredDefaultCategoryIds')[0]))
    semantic_ids = {v:k for k,v in ids.items()}
    children = {v for v in ids.values() if v.count('.') >= 2}
    assert len(children) == 104
    TARGET.mkdir(parents=True, exist_ok=True)
    ARCHIVE.mkdir(parents=True, exist_ok=True)
    audit, manifest = [], []
    for name, reviewed in zip(SOURCES, REVIEWS):
        original = BASE / name
        original_hash = sha(original)
        data = json.loads(original.read_text(encoding='utf-8'))
        used = set()
        for case in data['cases']:
            before = copy.deepcopy(case['expected'])
            expected = case['expected']
            old_id = expected.get('subcategoryId')
            if old_id and old_id not in ids:
                key, rationale = reviewed[case['id']]
                assert key in children
                expected.update(semanticKey=key, subcategoryId=semantic_ids[key],
                                categoryId=semantic_ids['.'.join(key.split('.')[:2])])
                used.add(case['id'])
                audit.append(dict(corpus=name, id=case['id'], input=case['input'], before=before,
                                  after=copy.deepcopy(expected), reason=rationale))
            elif old_id:
                expected['semanticKey'] = ids[old_id]
            else:
                expected['semanticKey'] = None
            for history in case['setup'].get('history', []):
                if history['subcategoryId'] not in ids:
                    # H003 records only a platform; no stable food purpose remains.
                    assert case['id'] == 'H003'
                    history.update(categoryId='expense-other', subcategoryId='expense-other-general')
            assert expected['semanticKey'] is None or expected['semanticKey'] in children
            if expected['subcategoryId']:
                assert ids[expected['subcategoryId']] == expected['semanticKey']
                assert ids[expected['categoryId']] == '.'.join(expected['semanticKey'].split('.')[:2])
            for h in case['setup'].get('history', []):
                assert ids[h['subcategoryId']] in children
        assert used == set(reviewed), (name, used ^ set(reviewed))
        data['metadata'].update(name=data['metadata']['name']+' (migrated 104-class)',
                                taxonomySemanticCount=104,
                                taxonomyCoverage='All non-null expected semantics and history use active 104 labels',
                                oracleMigration='Reviewed actual use only; original inputs/type/status/amount/time/issues and all legal labels unchanged')
        target = TARGET / (Path(name).stem+'_104class.json')
        target.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        # Validation belongs to this migration phase; never rerun during production work.
        validated = json.loads(target.read_text(encoding='utf-8'))
        assert len(validated['cases']) == len(data['cases'])
        assert all(c['expected']['semanticKey'] is None or c['expected']['semanticKey'] in children for c in validated['cases'])
        shutil.move(str(original), str(ARCHIVE / name))
        assert sha(ARCHIVE / name) == original_hash
        manifest.append(dict(source=str((ARCHIVE/name).relative_to(ROOT)), sourceSha256=original_hash,
                             target=str(target.relative_to(ROOT)), sha256=sha(target),
                             cases=len(data['cases']), migratedLabels=len(used), invalidLabels=0))
    (ARCHIVE/'oracle_migration_review.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    sealed = dict(sealedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(), taxonomyCount=104,
                  policy='No further corpus or review-content access until production freeze. v6 remains unopened.', corpora=manifest)
    MANIFEST.write_text(json.dumps(sealed, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(sealed, indent=2))

if __name__ == '__main__':
    main()

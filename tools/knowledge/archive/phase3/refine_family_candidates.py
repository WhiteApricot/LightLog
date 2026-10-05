"""One-time, reviewed Phase 3 candidate refinement; never reads evaluation data.

The allowlist selects concepts, not candidate semantic suggestions. Candidate
core vocabulary precedes its mechanically generated wrappers (first seven).
Each selected core is still subject to an explicit lexical exclusion/owner
review. Runtime generation consumes only the resulting JSON sources.
"""
import json
import re
from pathlib import Path


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def write(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def normalize(term):
    # Mirrors RecognitionNormalizer.indexKey; the generator rechecks this.
    term = "".join(" " if ord(c) == 0x3000 else chr(ord(c)-0xFEE0)
                   if 0xFF01 <= ord(c) <= 0xFF5E else "¥"
                   if ord(c) == 0xFFE5 else c for c in term).lower()
    term = re.sub("[，、；]", ",", term)
    term = re.sub("[。！]", " ", term)
    return re.sub(r"[\s,.:：·_\-/\\'’]", "", term).strip()


candidate = read("lexical_family_candidates.json")
source = read("tools/knowledge/lexical_families_source.json")
rules = read("tools/knowledge/composition_rules_source.json")
original = {f["id"]: list(f["terms"]) for f in source["families"]}
families = {f["id"]: dict(f) for f in source["families"]}

# Flat semantic groups. Subtypes are merged wherever service routing is the
# same; phone/computer/photo remain separate because their purchase semantics
# differ. There is no runtime inheritance or parent lookup.
groups = {
    "object.vehicle": "vehicle newEnergyVehicle motorcycle bicycle electricBike",
    "object.vehiclePart": "vehiclePart tire vehicleBattery vehicleAccessory",
    "object.fuel": "fuel",
    "object.parkingCredential": "parkingCredential",
    "object.publicTransitCard": "publicTransitCard",
    "object.railTicket": "railTicket",
    "object.flightTicket": "flightTicket",
    "object.busTicket": "busTicket shipTicket",
    "object.digitalDevice": "digitalDevice tablet audioDevice wearableDevice networkDevice printer",
    "object.phone": "phone",
    "object.computerHardware": "computer computerPart display storageDevice",
    "object.photoEquipment": "camera lens",
    "object.digitalAccessory": "digitalAccessory charger",
    "object.software": "software",
    "object.cloud": "cloudResource",
    "object.gameProduct": "gameProduct",
    "object.appliance": "appliance kitchenAppliance cleaningAppliance climateAppliance laundryAppliance refrigerationAppliance waterAppliance personalAppliance",
    "object.homeFurnishing": "furniture bedroomFurniture livingRoomFurniture officeFurniture textile",
    "object.homeFixture": "homeFixture lighting sanitaryWare hardwareMaterial",
    "object.tableware": "tableware",
    "object.storageSupply": "storageSupply",
    "object.clothing": "clothing underwear fitnessWear",
    "object.shoe": "shoe",
    "object.bag": "bag luggage",
    "object.jewelry": "jewelry watch hatScarf",
    "object.eyewear": "eyewear",
    "object.beautyProduct": "beautyProduct skinCareProduct",
    "object.hairCareProduct": "hairCareProduct",
    "object.personalCareProduct": "oralCareProduct personalCareProduct menstrualProduct",
    "object.household": "householdSupply paperProduct",
    "object.laundryProduct": "cleaningSupply",
    "object.medicine": "medicine traditionalMedicine",
    "object.medicalDevice": "medicalDevice rehabAid",
    "object.foodIngredient": "foodIngredient vegetable meat seafood grain egg seasoning",
    "object.fruit": "fruit",
    "object.dairy": "dairy",
    "object.preparedFood": "preparedFood",
    "context.takeoutFood": "stapleFood",
    "object.snack": "snack dessert",
    "object.drink": "drink coffeeTea alcohol",
    "object.pet": "pet cat dog smallPet",
    "object.petFood": "petFood",
    "object.petSupply": "petSupply",
    "object.petMedicine": "petMedicine",
    "object.babySupply": "babySupply childToy",
    "object.schoolSupply": "schoolSupply officeSupply",
    "object.book": "book",
    "object.sportEquipment": "sportEquipment",
    "object.outdoorGear": "outdoorGear",
    "object.travelSupply": "travelSupply",
    "object.gift": "gift flower",
    "object.collectible": "collectible craftMaterial musicalInstrument",
    "object.property": "property home",
    "object.financialProduct": "financialProduct",
    "object.certificate": "certificate",
    "action.sell": "sell",
    "action.recharge": "recharge",
    "action.renew": "renew subscribe",
    "action.repair": "repair uninstall",
    "action.maintenance": "maintain",
    "action.replacePart": "replacePart upgrade",
    "action.install": "install",
    "action.cleaning": "clean disinfect launder",
    "action.grooming": "groom",
    "action.decorate": "decorate",
    "action.alteration": "alter",
    "action.move": "move",
    "action.rent": "rent",
    "action.repay": "repay",
    "action.insure": "insure",
    "action.claim": "claim",
    "action.sportEvent": "register",
    "action.book": "book reserveSeat checkIn",
    "action.ship": "ship deliver",
    "action.store": "store",
    "action.print": "print copy bind",
    "action.education": "learn",
    "action.train": "train",
    "action.medical": "medicalTreatment vaccinate",
    "action.physicalExam": "physicalExam",
    "action.rehabilitate": "rehabilitate",
    "action.nurse": "nurse care",
    "action.consult": "consult",
    "action.donate": "donate",
    "context.socialGift": "gift",
    "action.authenticate": "authenticate",
    "action.exchangeCurrency": "exchangeCurrency",
    "action.withdraw": "withdraw",
    "modifier.child": "child baby",
    "modifier.elder": "elder",
    "modifier.student": "student school",
    "modifier.secondHand": "secondHand",
    "service.membership": "membership subscription",
    "service.express": "express",
    "service.housekeeping": "cleaning housekeeping",
    "service.moving": "moving",
    "service.storage": "storage",
    "service.beauty": "beauty nail",
    "service.haircut": "haircut",
    "service.massage": "massage",
    "service.photography": "photography",
    "service.printing": "printing",
    "service.consulting": "consulting legal accounting",
    "service.training": "training tutoring",
    "service.dental": "dental visionCare",
    "service.rehab": "rehab",
    "service.nursing": "nursing",
    "service.insurance": "insurance",
    "service.visa": "visa",
    "service.ticketing": "ticketing",
    "service.parking": "parking",
    "service.carWash": "carWash",
    "service.rideHailing": "rideHailing chauffeur",
    "service.travelPackage": "travelPackage guide",
    "service.hotel": "hotel",
    "service.catering": "catering",
    "service.eventPlanning": "eventPlanning funeral",
    "service.childcare": "childcare",
    "service.eldercare": "eldercare",
    "service.homeRepair": "homeRepair interiorDesign",
    "venue.supermarket": "supermarket convenienceStore wetMarket",
    "context.medicalVenue": "hospital clinic communityHealthCenter",
    "venue.pharmacy": "pharmacy",
    "venue.petHospital": "petHospital",
    "venue.restaurant": "restaurant fastFood",
    "venue.cafe": "cafe bakery",
    "venue.hotel": "hotel homestay",
    "venue.cinema": "cinema",
    "venue.theater": "theater",
    "venue.gameVenue": "gameVenue ktv",
    "venue.gym": "gym",
    "venue.sport": "sportVenue swimmingPool",
    "venue.outdoorSite": "outdoorSite",
    "venue.school": "school trainingCenter",
    "venue.library": "library bookstore",
    "venue.scenic": "scenicArea museum themePark",
    "venue.bank": "bank",
    "context.travel": "travel",
    "context.businessTrip": "businessTrip",
    "context.work": "work",
    "context.education": "education exam",
    "context.driving": "driving commute",
    "context.home": "home moving renovation",
    "context.pregnancy": "pregnancy childcare",
    "context.sport": "sport fitness outdoor",
    "context.game": "gaming",
    "context.photo": "photography",
    "context.gathering": "gathering social",
    "context.wedding": "wedding festival giftGiving",
    "context.charity": "charity",
    "platform.shopping": "shopping",
    "platform.delivery": "takeout",
    "platform.travel": "travel",
    "platform.secondHand": "secondHand",
    "platform.content": "content",
    "platform.education": "education",
    "platform.freelance": "freelance",
    "income.wage": "wage salary salaryPayment",
    "income.bonus": "bonus",
    "income.allowance": "allowance",
    "income.salaryPerformance": "performance overtime commission",
    "income.reimbursement": "reimbursement",
    "income.privateOrder": "freelance privateOrder projectLabor",
    "income.orderIncome": "platformOrder",
    "income.teachingFee": "teachingFee consulting",
    "income.authorFee": "authorFee royalty",
    "income.liveStream": "liveStream",
    "income.interest": "interest",
    "income.dividend": "dividend",
    "income.fundReturn": "fundReturn stockReturn",
    "income.rentIncome": "rentIncome",
    "income.refund": "refund shoppingRefund serviceRefund",
    "income.depositReturn": "depositReturn",
    "income.taxRefund": "taxRefund",
    "income.cashback": "cashback reward",
    "income.redPacket": "redPacket giftIncome",
    "income.secondHandSale": "secondHandSale",
    "income.compensation": "compensation",
    "income.subsidy": "subsidy",
    "income.prize": "prize",
    "income.saleIncome": "saleIncome serviceIncome",
}

# Independent candidate kinds whose IDs differ from the output group kind.
kind_override = {"context.takeoutFood": "object", "context.socialGift": "action",
                 "context.medicalVenue": "venue"}
excluded = set("零部件 原厂件 副厂件 机车 踏板车 助力车 电车 天然气 充电电量 通行卡 月卡 停车码 市民卡 一卡通 车票 船运票 上船票 电子玩意 智能硬件 学习机 学习平板 老人机 备用机 新手机 硬件 屏幕 显示屏 套头 腕表设备 健康手环 儿童手表 网络盒子 网关 程序 客户端 插件 APP 电子设备 架子 灯 碗筷 刀具 箱子 穿搭 儿童表 太阳镜 隐形眼镜 护目镜 护理用品 洗护用品 杂货 家杂 原料 生鲜 果子 水果拼盘 果切 主粮 奶粉 奶酪 冻干 滴眼液 皮肤药 书包 护具 心意 赠品 植物 公寓 不动产 住房 房子 房产 保险产品 许可证 通行证 签证 修改 调整 改造 重新加工 注册 登记 录入信息 签到 托管 陪护 教育 健康 工作室 减脂 增肌 塑形 训练 比赛 兴趣班 摄像 写真 拍照 原路退款 售后退款 业绩奖 提成奖金 绩效奖金 佣金收入 保险医疗赔付 礼金收入 份子钱收入 转账红包 奖金 保险赔款 赔付 到账一笔 客户付款 劳动报酬".split())

# Merge only the selected natural cores. Never import relatedSemanticKeys.
decisions = []
for target, names in groups.items():
    kind = kind_override.get(target, target.split(".")[0])
    selected = {kind + "." + name for name in names.split()}
    terms = families.setdefault(target, {"id": target, "terms": []})["terms"]
    for raw in candidate["families"]:
        if raw["id"] not in selected:
            continue
        for index, term in enumerate(raw["terms"]):
            reason = "retained-core"
            if index >= 7:
                reason = "mechanical-wrapper"
            elif len(normalize(term)) <= 1:
                reason = "single-character"
            elif term in excluded or term in raw.get("highRiskTerms", []):
                reason = "ambiguous-or-misleading-core"
            else:
                terms.append(term)
            decisions.append({"sourceFamily": raw["id"], "targetFamily": target,
                              "term": term, "decision": reason})

# Cross-role legacy duplicates are reviewed in the generator; all new terms
# have a single owner. Legacy vocabulary stays available for validated rules.
legacy_owners = {}
for fid, terms in original.items():
    for t in terms:
        legacy_owners.setdefault(normalize(t), []).append(fid)
seen = dict(legacy_owners)
for fid, family in families.items():
    output, local = [], set()
    for term in family["terms"]:
        key = normalize(term)
        if key in local:
            continue
        if fid not in legacy_owners.get(key, []) and key in seen and fid not in seen[key]:
            continue
        local.add(key)
        seen.setdefault(key, []).append(fid)
        output.append(term)
    family["terms"] = output
    family["kind"] = fid.split(".")[0]

# Terms not in the candidate, justified by natural daily service vocabulary.
additions = {
    "object.phone": "苹果手机 苹果手机配件 安卓手机 iPhone 智能机 移动手机 电话机",
    "object.computerHardware": "笔记本电脑 台式电脑 电脑主机 固态盘 散热器 机箱 CPU 内存 显示卡",
    "object.photoEquipment": "摄影器材 摄影设备 相机支架 三脚架 稳定器 相机电池 相机滤镜",
    "object.software": "办公软件 杀毒软件 设计软件 修图软件 剪辑软件 系统软件 软件许可证",
    "object.cloud": "网盘容量 云盘容量 云备份 云端空间 云储存 网盘会员 云服务",
    "object.network": "宽带 网络 光纤 家庭宽带 宽带网络 固网 家用网络 宽带套餐",
    "object.mobilePlan": "话费 手机套餐 手机流量 流量包 通话套餐 手机卡 电话费 通讯套餐",
    "object.loan": "贷款 信用卡 房贷 车贷 消费贷 借款 分期贷款 住房贷款",
    "object.utility": "水费 电费 水电费 燃气费 天然气费 煤气费 暖气费 供暖费",
    "object.exam": "资格考试 资格证 职业资格 考研 考公 公务员考试 驾照考试 自考",
    "object.document": "文件 资料 论文 简历 证件材料 讲义 作业 试卷 合同",
    "object.media": "视频 音乐 影视 电影 电视剧 有声书 听书 流媒体",
    "object.bankAccount": "银行卡 银行账户 信用卡账户 储蓄卡 储蓄账户 活期账户 定期账户",
    "action.receive": "收到 收款 收入 到账 入账 收到款 结算收入 收取 收了",
    "action.education": "补课 上学 辅导 读书 上网课 学习课程 教育课程",
    "action.medical": "诊疗 就医 打疫苗 接种疫苗 疫苗注射 打预防针 诊治",
    "action.repair": "修复 检修 修补 修整 返修 送修 上门维修 故障检修",
    "action.install": "装机 安装调试 上门安装 拆装 安装费 组装费 加装",
    "action.maintenance": "养护 定期保养 例行保养 换油 护理保养 日常维护",
    "action.recharge": "充话费 充流量 充值费 充余额 加值 储值 续充",
    "action.physicalExam": "健康体检 例行体检 专项体检 入学体检 体检费 健康筛查",
    "action.print": "打印资料 打印文件 复印资料 扫描文件 胶装论文 打印费 复印费",
    "action.ship": "寄快递 快递寄件 邮递 寄包裹 寄文件 快递费 运费",
    "service.fee": "手续费 手续费用 手续费支出 管理费 提现费 汇款手续费 换汇手续费",
    "service.tuition": "学费 学杂费 学期学费 学校费用 学年学费 保教费 教育费",
    "service.exam": "报名费 考试费 考务费 考证费 认证费 资格考试费 证书费",
    "context.design": "平面设计 网页设计 UI设计 插画设计 图形设计 美术设计 美工",
    "context.teaching": "教学 家教 辅导授课 线上授课 教学辅导 课外辅导 教书",
    "context.ridePlatform": "送外卖 配送接单 网约车接单 跑腿接单 众包送餐 外卖骑手 网约车司机",
    "context.finance": "银行 金融 银行卡 银行交易 银行转账 金融业务 银行业务",
}
for fid, text in additions.items():
    family = families.setdefault(fid, {"id": fid, "kind": fid.split(".")[0], "terms": []})
    for term in text.split():
        key = normalize(term)
        if key not in seen or fid in seen[key]:
            if key not in {normalize(t) for t in family["terms"]}:
                family["terms"].append(term)
                seen.setdefault(key, []).append(fid)

pair_seen = {tuple(sorted((r["leftFamily"], r["rightFamily"]))) for r in rules["rules"]}


def rule(left, right, semantic, distance=5, score=.94):
    assert left in families and right in families, (left, right)
    pair = tuple(sorted((left, right)))
    if pair in pair_seen:
        return
    pair_seen.add(pair)
    rules["rules"].append({"id": "daily-" + left.replace(".", "-") + "-" + right.replace(".", "-"),
                           "leftFamily": left, "rightFamily": right, "semanticKey": semantic,
                           "maxDistance": distance, "score": score})


def route(objects, actions, semantic):
    for obj in objects.split():
        for action in actions.split():
            rule(obj, action, semantic)


# Explicit semantic decisions, independent of compositionCandidates hints.
route("object.vehicle object.vehiclePart", "action.repair action.maintenance action.replacePart action.install service.carWash", "expense.transport.maintenance")
route("object.vehicle object.parkingCredential", "service.parking action.renew", "expense.transport.parking")
route("object.vehicle object.fuel", "action.recharge", "expense.transport.fuel")
route("object.publicTransitCard", "action.recharge action.renew", "expense.transport.public")
route("object.railTicket", "service.ticketing action.book", "expense.transport.rail")
route("object.flightTicket", "service.ticketing action.book", "expense.transport.flight")
route("object.busTicket", "service.ticketing action.book", "expense.travel.ticket")
route("object.phone object.computerHardware object.photoEquipment object.digitalDevice", "action.repair action.replacePart action.install action.maintenance", "expense.digital.repair")
route("object.appliance object.homeFixture", "action.install action.maintenance action.decorate service.homeRepair", "expense.housing.repair")
route("object.homeFurnishing object.homeFixture object.clothing object.shoe object.bag", "action.cleaning service.housekeeping", "expense.daily.cleaning")
route("object.bag object.jewelry object.eyewear object.shoe", "action.repair action.maintenance", "expense.daily.service")
route("object.clothing object.shoe object.bag", "action.alteration", "expense.daily.service")
route("object.homeFurnishing object.homeFixture object.property", "service.moving action.move", "expense.daily.service")
route("object.property", "action.rent", "expense.housing.rent")
route("object.property", "action.decorate service.homeRepair", "expense.housing.repair")
route("object.software", "action.renew service.membership", "expense.digital.software")
route("object.cloud", "action.renew action.recharge", "expense.communication.cloud")
route("object.network", "action.renew action.install action.recharge", "expense.communication.internet")
route("object.mobilePlan", "action.renew action.recharge", "expense.communication.mobile")
route("object.media platform.content", "action.renew service.membership", "expense.entertainment.subscription")
route("object.gameProduct context.game venue.gameVenue", "action.recharge service.membership", "expense.entertainment.game")
route("venue.cinema", "service.ticket action.book", "expense.entertainment.movie")
route("venue.theater", "service.ticket action.book", "expense.entertainment.music")
route("venue.gym context.sport", "action.train service.membership", "expense.sports.fitness")
route("venue.sport", "service.membership action.book", "expense.sports.venue")
route("venue.outdoorSite context.sport", "object.outdoorGear", "expense.sports.outdoor")
route("object.pet venue.petHospital", "action.physicalExam action.rehabilitate service.nursing", "expense.pets.medical")
route("object.pet", "object.petFood", "expense.pets.food")
route("object.pet", "object.petMedicine", "expense.pets.medical")
route("object.pet", "action.store service.hotel", "expense.pets.service")
route("modifier.child", "object.babySupply service.childcare", "expense.family.child")
route("modifier.child modifier.student", "service.training service.tuition object.book object.schoolSupply", "expense.family.education")
route("modifier.child modifier.elder", "action.physicalExam action.rehabilitate service.nursing service.dental service.rehab", "expense.family.health")
route("modifier.elder", "service.eldercare object.medicalDevice action.nurse", "expense.family.elder")
route("context.medicalVenue", "action.physicalExam", "expense.medical.checkup")
route("context.medicalVenue", "service.dental", "expense.medical.dental")
route("context.medicalVenue", "service.rehab action.rehabilitate service.nursing", "expense.medical.rehab")
route("venue.pharmacy", "object.medicine action.medicine", "expense.medical.medicine")
route("object.document object.book object.certificate", "action.print service.printing", "expense.education.stationery")
route("object.exam context.education", "service.exam action.authenticate", "expense.education.exam")
route("context.education venue.school", "service.training action.education", "expense.education.course")
route("venue.school modifier.student", "service.tuition", "expense.education.tuition")
route("venue.library", "object.book", "expense.education.book")
route("context.photo", "service.photography", "expense.daily.service")
route("context.home", "service.housekeeping", "expense.daily.cleaning")
route("context.home", "service.moving action.move service.storage", "expense.daily.service")
route("context.travel platform.travel", "service.hotel venue.hotel", "expense.travel.hotel")
route("context.travel platform.travel", "service.travelPackage service.visa", "expense.travel.package")
route("context.travel", "service.rideHailing action.rent", "expense.travel.local")
route("context.travel", "service.storage action.store object.bag", "expense.travel.supplies")
route("context.wedding context.socialGift", "object.gift service.eventPlanning", "expense.social.gift")
route("context.gathering", "service.catering venue.restaurant", "expense.social.gathering")
route("context.charity", "action.donate", "expense.social.donation")
route("object.loan", "action.repay", "expense.finance.loan")
route("object.financialProduct object.vehicle object.property", "action.insure service.insurance", "expense.finance.insurance")
route("context.finance venue.bank object.bankAccount", "service.fee action.withdraw action.exchangeCurrency", "expense.finance.fee")
route("platform.shopping", "object.foodIngredient object.fruit object.dairy", "expense.food.groceries")
route("platform.shopping", "object.beautyProduct", "expense.shopping.beauty")
route("platform.shopping", "object.personalCareProduct object.hairCareProduct", "expense.daily.personal")
route("platform.shopping", "object.clothing object.shoe object.bag", "expense.shopping.clothing")
route("platform.shopping", "object.homeFurnishing object.tableware object.storageSupply", "expense.shopping.home")
route("platform.shopping", "object.appliance", "expense.shopping.appliance")
route("platform.shopping", "object.phone", "expense.digital.phone")
route("platform.shopping", "object.computerHardware", "expense.digital.computer")
route("platform.shopping", "object.photoEquipment", "expense.digital.photo")
route("platform.shopping", "object.digitalAccessory", "expense.digital.accessory")
route("platform.delivery", "object.drink", "expense.food.drink")
route("platform.delivery", "object.snack", "expense.food.snack")
route("platform.education", "service.training service.membership", "expense.education.course")
route("object.document object.gift object.bag", "action.ship service.express", "expense.communication.post")
route("context.businessTrip", "income.reimbursement", "income.reimbursement.travel")
route("context.work", "income.reimbursement", "income.reimbursement.work")
route("income.wage", "action.receive", "income.salary.monthly")
route("income.bonus", "action.receive", "income.salary.bonus")
route("income.allowance", "context.work action.receive", "income.salary.allowance")
route("income.salaryPerformance", "action.receive", "income.salary.overtime")
route("income.privateOrder", "context.design platform.freelance", "income.parttime.freelance")
route("income.privateOrder", "action.receive", "income.parttime.project")
route("income.orderIncome", "platform.freelance context.ridePlatform", "income.parttime.platform")
route("income.teachingFee", "context.teaching action.receive", "income.parttime.consulting")
route("income.authorFee income.liveStream", "action.receive", "income.parttime.freelance")
for fid, semantic in {
    "income.interest": "income.investment.interest", "income.dividend": "income.investment.dividend",
    "income.fundReturn": "income.investment.fund", "income.rentIncome": "income.investment.rent",
    "income.depositReturn": "income.refund.deposit", "income.taxRefund": "income.refund.tax",
    "income.cashback": "income.other.reward", "income.redPacket": "income.other.red.packet",
    "income.compensation": "income.other.compensation", "income.subsidy": "income.other.general",
    "income.prize": "income.other.reward", "income.saleIncome": "income.other.general",
}.items():
    rule(fid, "action.receive", semantic)
route("modifier.secondHand platform.secondHand", "action.sell income.secondHandSale", "income.other.secondhand")
route("object.software service.training service.hotel service.membership", "income.refund", "income.refund.service")
route("platform.shopping", "income.refund", "income.refund.shopping")

# Avoid unused speculative concepts. Existing validated families are retained.
used = {r[k] for r in rules["rules"] for k in ("leftFamily", "rightFamily")}
families = {k: v for k, v in families.items() if k in used or k in original}
write("tools/knowledge/lexical_families_source.json", {"version": 1, "families": list(families.values())})
write("tools/knowledge/composition_rules_source.json", rules)
retained = {normalize(t) for f in families.values() for t in f["terms"]}
candidate_terms = {normalize(t) for f in candidate["families"] for t in f["terms"]}
write("tools/knowledge/review/family_candidate_review.json", {
    "policy": "Reviewed flat concept allowlist, natural cores only; no evaluation input or semantic hints used",
    "candidateFamilies": len(candidate["families"]), "candidateUniqueTerms": len(candidate_terms),
    "candidateTermsRetained": len(candidate_terms & retained),
    "candidateTermsFiltered": len(candidate_terms - retained),
    "familyCount": len(families), "uniqueTerms": len(retained), "ruleCount": len(rules["rules"]),
    "semanticCoverage": len({r["semanticKey"] for r in rules["rules"]}),
    "normalizedDiff": {fid: {"added": [t for t in f["terms"] if normalize(t) not in {normalize(x) for x in original.get(fid, [])}],
                              "preserved": original.get(fid, [])} for fid, f in families.items()},
    "candidateDecisions": [{**d, "retainedInProduction": normalize(d["term"]) in retained} for d in decisions],
    "excludedCandidateFamilies": [f["id"] for f in candidate["families"] if not any(d["sourceFamily"] == f["id"] for d in decisions)],
})
print(len(families), len(retained), len(rules["rules"]), len({r["semanticKey"] for r in rules["rules"]}))

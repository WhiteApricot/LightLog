# V0.1 需求基线

本文是“轻记”V0.1 MVP 的正式需求基线。超出本文件的能力默认不属于 V0.1。

## 产品目标

“轻记”是一款 Android 优先、local-first、单机单用户、轻量，并支持智能识别与个性化规则学习的记账工具。目标是让常见账目在数秒内完成录入。

- 主要语言：简体中文
- 默认货币：CNY / ¥
- 新建账目的时间输入使用设备本地时区；历史账目按发生时保存的 UTC offset 还原和展示，不随当前设备时区漂移
- 数据位置：V0.1 仅保存在本机

## V0.1 必须功能

### 手动记账

每笔账目包含：

- 账务类型：`expense`、`income`、`transfer`、`refund`
- 一级分类
- 二级分类
- 内容/商户
- 金额
- 时间，默认当前时间且可修改到分钟
- 账户/支付方式
- 备注，可选

UI 重点优化 `expense` 和 `income`，但数据模型必须能表达全部四种类型。金额持久化使用正整数最小货币单位，人民币使用“分”，账务方向由类型决定，不得使用正负金额或浮点数作为核心表示。

主界面只提供一个“记一笔”入口。进入后在同一页面顶部提供智能文字输入框，仅在用户点击“识别”后调用 Parser，不在输入过程中实时识别。完整结果在输入框下方展示分类、时间、金额和内容/商户，并可直接“确认入账”；下方完整手动表单同步填充，仍允许修改全部字段后保存。两条保存路径必须复用同一验证与 Repository。分类使用紧凑的纵向图标网格，不允许分类区横向滚动；默认只展示一级分类，点击一级分类展开/收起对应二级分类，已有二级选择时保持其父级展开。切换一级分类时必须清除不再有效的二级分类。日期和具体时间均可修改，时间采用可循环的 24 小时滚轮选择器，不显示 AM/PM。智能文字账目确认保存成功后直接返回主界面。

主界面顶部展示本月收入、本月支出和结余，下方账目按发生时本地日期分组；日期分隔处展示日期、星期和当日收入/支出总额。账目行展示二级分类图标。预算系统实现前仅展示“未设置”等状态，不提前提供预算编辑或计算能力。

`transfer` 必须记录转出和转入账户，不计入收入、支出或净收支统计。`refund` 应关联原账目，统计时按退款语义冲减原收入或支出，不机械视为普通收入或支出。时间持久化采用 UTC epoch milliseconds，并记录交易发生时的设备 UTC offset；历史账目的展示和编辑使用该 offset 还原发生时当地时间，编辑时保留原 offset，不使用当前设备时区重新解释。


### V0.1 taxonomy contract（104 个二级语义）

最终以已确认的逐项清单为准：78 个支出、26 个收入二级 semanticKey，共 104 类；21 个一级分类，共 125 个默认分类。下表中的一级前缀与二级后缀组成完整 semanticKey，是知识库和已实现字符分类模型的唯一标签体系。模型仅作完全本地、纯Dart的分级低置信语义证据；允许强统计父类校正弱默认方向；不得替代确定性强证据或绕过确认/退款等安全门禁。

| 一级前缀 | 二级后缀 |
| --- | --- |
| `expense.food` | `breakfast`, `lunch`, `dinner`, `drink`, `snack`, `groceries`, `other` |
| `expense.transport` | `public`, `taxi`, `rail`, `flight`, `fuel`, `parking`, `maintenance` |
| `expense.shopping` | `clothing`, `beauty`, `home`, `appliance`, `gift`, `other` |
| `expense.housing` | `rent`, `mortgage`, `property`, `utilities`, `gas`, `repair` |
| `expense.daily` | `household`, `personal`, `cleaning`, `haircut`, `service` |
| `expense.entertainment` | `movie`, `game`, `music`, `subscription`, `hobby` |
| `expense.education` | `book`, `course`, `exam`, `stationery`, `tuition` |
| `expense.medical` | `clinic`, `medicine`, `dental`, `checkup`, `rehab` |
| `expense.communication` | `mobile`, `internet`, `post`, `cloud` |
| `expense.social` | `gathering`, `gift`, `donation`, `relationship` |
| `expense.social.red` | `packet` |
| `expense.sports` | `fitness`, `equipment`, `venue`, `outdoor`, `event` |
| `expense.pets` | `food`, `medical`, `supplies`, `grooming`, `service` |
| `expense.digital` | `phone`, `computer`, `photo`, `accessory`, `software`, `repair` |
| `expense.finance` | `fee`, `interest`, `insurance`, `tax`, `loan`, `investment` |
| `expense.other` | `general` |
| `income.salary` | `monthly`, `bonus`, `allowance`, `overtime` |
| `income.reimbursement` | `work`, `travel`, `medical`, `other` |
| `income.parttime` | `freelance`, `project`, `platform`, `consulting` |
| `income.investment` | `interest`, `dividend`, `fund`, `rent`, `other` |
| `income.refund` | `shopping`, `service`, `deposit`, `tax` |
| `income.other.red` | `packet` |
| `income.other` | `secondhand`, `reward`, `compensation`, `general` |

支出按真实用途分类。“外卖”是渠道，删除 `expense.food.takeout`；删除全部 `expense.travel.*` 和 `expense.family.*`。旅行交通、保险、用品按实际用途迁移；酒店、民宿、青旅统一归入 `expense.housing.rent`；无法稳定拆分用途的旅行套餐、签证代办归入 `expense.other.general`。儿童、老人等是使用者上下文，医疗、教育、护理用品按实际用途分类，纯家庭生活补贴归入 `expense.other.general`。`income.reimbursement.travel` 保留。

保留早餐、午餐、晚餐。明确正餐证据 + 明确文本时间 > 明确正餐证据 + occurredAtLocal 时间段 > 其他 food subtype，是食品用途分类的最高优先级原则；不能把外卖渠道整体静态映射到某一餐。该规则已在唯一LocalRecognizer中实现，时段、弱置信上限和证据边界见 [算法文档](RECOGNITION_ALGORITHM.md)。n-gram不能单独猜餐段，饮品、零食及食材本身不属于明确正餐证据。

有效金额、交易类型已识别且最终无合法semantic/活动分类映射的普通支出归入 `expense.other.general`，收入归入 `income.other.general`。该fallback已在deterministic与ngram均尝试之后实现，复用CategoryResolver；必须有可用的other.general活动分类，结果保持warning并要求复核。failed、cancelled、nontransaction、多笔交易、金额缺失、未关联退款及其他safety-blocked状态不得被fallback绕过，不得伪造缺失的分类映射。

### 二级分类

分类采用两级结构，并可维护，不得硬编码到 UI 逻辑中：

```text
一级分类
└── 二级分类
```

默认分类应覆盖个人日常收支的主要场景。每个一级和二级分类都通过数据库字段稳定关联轻量 SVG 图标资源；二级分类必须使用不同且语义匹配的实际矢量图形，自动测试应防止仅文件名不同但图形重复。UI 不得按分类名称维护巨型图标映射。

示例：

```text
餐饮
├── 早餐
├── 午餐
├── 晚餐
├── 饮品
├── 零食
└── 其他餐饮
```

### 文字自动记账

示例输入：

```text
二食堂 15
```

午间输入时可生成以下候选结果：

```text
支出
餐饮 → 午餐
二食堂
15.00 CNY
当前时间
```

V0.1 使用正则、关键词、时间规则、本地历史与轻量字符线性分类弱证据，不使用 LLM。唯一 `LocalRecognizer` 只能产生 `RecognitionCandidate`，不得直接写入 `Transaction`。

### 支付截图自动记账

```text
截图
→ OCR
→ 字段提取
→ 规则推断
→ RecognitionCandidate
→ 确认/自动确认
→ Transaction
```

尽量提取金额、商户、时间、交易号/订单号、商品或订单详情、支付平台。OCR 结果不得直接写账，处理完成后默认不保存原始支付截图。

### 个性化规则学习

第一次遇到不确定映射时要求用户确认或修改；确认/修改结果形成本地规则，之后相似账目可提高分类置信度。

- 高置信度：自动入账，同时显示 Snackbar/提示并提供撤销。
- 低置信度或规则冲突：必须确认。
- 是否自动入账由历史证据与 confidence 共同决定，不机械绑定固定命中次数。

### 编辑与删除

已有账目支持手动编辑、重新文字解析和重新截图识别。重新识别仍先产生 Candidate，并在确认后更新账目。

删除采用 soft delete，并提供撤销；不得直接破坏历史数据。单条账目从编辑页右上角删除，列表不提供滑动删除；长按账目进入多选模式后可批量删除。

### 重复检测

优先使用订单号/交易号判定重复；缺失时使用以下组合生成或比较 fingerprint：

```text
商户 + 金额 + 时间 + 来源
```

无法确定时只提示疑似重复，不静默丢弃或覆盖。

### 账户/支付方式

至少支持微信、支付宝、银行卡、现金、其他。账户通过数据库字段关联轻量 SVG，并使用“图标 + 名称”点选，不使用下拉框或按名称硬编码图标。V0.1 不做账户余额管理。

### 搜索筛选

至少支持内容/商户关键词、时间、一级分类、二级分类和收支类型筛选。

### 统计

支持本周、本月、本年和自定义时间段，展示总收入、总支出、净收支、时间趋势、一级分类占比和二级分类明细。转账不参与收支统计；退款依据其关联原账目冲减对应统计。

### 数据导入导出

- CSV：用于人工查看及 Excel/分析。
- JSON：用于完整备份与完整恢复。

完整 JSON 备份至少包含：

```text
schemaVersion
transactions
categories
accounts
recognitionRules
```

导入必须校验格式和 schemaVersion，不得让部分失败静默产生不完整数据。

## 隐私要求

- 不保存原始支付截图。
- 默认所有消费数据仅保存在本机。
- V0.1 不上传 OCR、账目或截图数据。
- 不加入 analytics 或 telemetry。
- 无需登录。

## 明确不属于 V0.1

以下仅可列为 Future，不得提前或隐式实现：

- 登录注册
- 后端服务器
- 云同步
- 多用户
- 家庭共享账本
- 微信/支付宝官方 API 同步
- 银行账户自动同步
- Accessibility 自动抓取
- 后台扫描相册
- LLM
- 在线商户搜索或 Web Search
- AI 消费建议
- 语音记账
- 投资资产管理
- 多币种实时汇率
- Windows、macOS、Web 正式客户端

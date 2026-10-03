class CategorySeed {
  const CategorySeed(
    this.id,
    this.name,
    this.type,
    this.sortOrder, [
    this.parentId,
  ]);

  final String id;
  final String name;
  final String type;
  final int sortOrder;
  final String? parentId;
}

class AccountSeed {
  const AccountSeed(this.id, this.name, this.type, this.sortOrder);

  final String id;
  final String name;
  final String type;
  final int sortOrder;
}

const defaultCategories = <CategorySeed>[
  CategorySeed('expense-food', '餐饮', 'expense', 10),
  CategorySeed('expense-food-breakfast', '早餐', 'expense', 10, 'expense-food'),
  CategorySeed('expense-food-lunch', '午餐', 'expense', 20, 'expense-food'),
  CategorySeed('expense-food-dinner', '晚餐', 'expense', 30, 'expense-food'),
  CategorySeed('expense-food-drink', '饮料', 'expense', 40, 'expense-food'),
  CategorySeed('expense-food-snack', '零食', 'expense', 50, 'expense-food'),
  CategorySeed('expense-food-other', '其他餐饮', 'expense', 60, 'expense-food'),
  CategorySeed('expense-transport', '交通', 'expense', 20),
  CategorySeed(
    'expense-transport-public',
    '公共交通',
    'expense',
    10,
    'expense-transport',
  ),
  CategorySeed(
    'expense-transport-taxi',
    '打车',
    'expense',
    20,
    'expense-transport',
  ),
  CategorySeed('expense-shopping', '购物', 'expense', 30),
  CategorySeed(
    'expense-shopping-daily',
    '日用品',
    'expense',
    10,
    'expense-shopping',
  ),
  CategorySeed('expense-other', '其他支出', 'expense', 90),
  CategorySeed('expense-other-general', '其他支出', 'expense', 10, 'expense-other'),
  CategorySeed('income-salary', '工资', 'income', 10),
  CategorySeed('income-salary-monthly', '月薪', 'income', 10, 'income-salary'),
  CategorySeed('income-other', '其他收入', 'income', 90),
  CategorySeed('income-other-general', '其他收入', 'income', 10, 'income-other'),
];

const defaultAccounts = <AccountSeed>[
  AccountSeed('account-wechat', '微信', 'wechat', 10),
  AccountSeed('account-alipay', '支付宝', 'alipay', 20),
  AccountSeed('account-bank-card', '银行卡', 'bank_card', 30),
  AccountSeed('account-cash', '现金', 'cash', 40),
  AccountSeed('account-other', '其他', 'other', 50),
];

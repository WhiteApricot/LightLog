import 'dart:io';

import 'package:light_log/data/database/seed_data.dart';

/// Imports the small, fixed Lucide subset used by LightLog.
///
/// Usage: `dart run tools/icons/import_lucide_icons.dart <lucide-repository-root>`
void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Expected the Lucide repository root as the only argument.');
    exitCode = 64;
    return;
  }

  final sourceRoot = Directory(arguments.single);
  final sourceIcons = Directory(
    '${sourceRoot.path}${Platform.pathSeparator}icons',
  );
  if (!sourceIcons.existsSync()) {
    stderr.writeln('Lucide icons directory not found: ${sourceIcons.path}');
    exitCode = 66;
    return;
  }

  _validateMapping(
    kind: 'category',
    expectedIds: defaultCategories.map((item) => item.id),
    mapping: _categoryIcons,
  );
  _validateMapping(
    kind: 'account',
    expectedIds: defaultAccounts.map((item) => item.id),
    mapping: _accountIcons,
  );

  final allSources = [..._categoryIcons.values, ..._accountIcons.values];
  if (allSources.toSet().length != allSources.length) {
    throw StateError(
      'Every category and account must use a distinct source SVG.',
    );
  }
  for (final icon in allSources) {
    final source = File(
      '${sourceIcons.path}${Platform.pathSeparator}$icon.svg',
    );
    if (!source.existsSync()) {
      throw StateError('Missing Lucide icon: $icon.svg');
    }
  }

  _importGroup(
    sourceIcons: sourceIcons,
    destination: Directory('assets/icons/categories'),
    mapping: _categoryIcons,
  );
  _importIcon(
    source: File('${sourceIcons.path}${Platform.pathSeparator}shapes.svg'),
    target: File('assets/icons/categories/category-default.svg'),
  );
  _importGroup(
    sourceIcons: sourceIcons,
    destination: Directory('assets/icons/accounts'),
    mapping: _accountIcons,
  );

  File('${sourceRoot.path}${Platform.pathSeparator}LICENSE')
      .copySync('assets/icons/LUCIDE_LICENSE.txt');
  stdout.writeln(
    'Imported ${_categoryIcons.length} category icons and '
    '${_accountIcons.length} account icons.',
  );
}

void _validateMapping({
  required String kind,
  required Iterable<String> expectedIds,
  required Map<String, String> mapping,
}) {
  final expected = expectedIds.toSet();
  final missing = expected.difference(mapping.keys.toSet());
  final extra = mapping.keys.toSet().difference(expected);
  if (missing.isNotEmpty || extra.isNotEmpty) {
    throw StateError(
      'Invalid $kind mapping. Missing: $missing; unexpected: $extra',
    );
  }
}

void _importGroup({
  required Directory sourceIcons,
  required Directory destination,
  required Map<String, String> mapping,
}) {
  destination.createSync(recursive: true);
  for (final oldFile in destination.listSync().whereType<File>()) {
    if (oldFile.path.toLowerCase().endsWith('.svg')) oldFile.deleteSync();
  }
  for (final entry in mapping.entries) {
    _importIcon(
      source: File(
        '${sourceIcons.path}${Platform.pathSeparator}${entry.value}.svg',
      ),
      target: File(
        '${destination.path}${Platform.pathSeparator}${entry.key}.svg',
      ),
    );
  }
}

void _importIcon({required File source, required File target}) {
  final compact = source
      .readAsStringSync()
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'>\s+<'), '><')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  target.writeAsStringSync('$compact\n');
}

const _categoryIcons = <String, String>{
  'expense-food': 'utensils',
  'expense-food-breakfast': 'egg-fried',
  'expense-food-lunch': 'soup',
  'expense-food-dinner': 'cooking-pot',
  'expense-food-takeout': 'package-open',
  'expense-food-drink': 'cup-soda',
  'expense-food-snack': 'cookie',
  'expense-food-groceries': 'salad',
  'expense-food-other': 'sandwich',
  'expense-transport': 'route',
  'expense-transport-public': 'bus-front',
  'expense-transport-taxi': 'car-taxi-front',
  'expense-transport-rail': 'train-front',
  'expense-transport-flight': 'plane',
  'expense-transport-fuel': 'fuel',
  'expense-transport-parking': 'square-parking',
  'expense-transport-maintenance': 'wrench',
  'expense-shopping': 'shopping-cart',
  'expense-shopping-clothing': 'shirt',
  'expense-shopping-beauty': 'sparkles',
  'expense-shopping-home': 'armchair',
  'expense-shopping-appliance': 'refrigerator',
  'expense-shopping-gift': 'gift',
  'expense-shopping-other': 'shopping-basket',
  'expense-housing': 'house',
  'expense-housing-rent': 'key-round',
  'expense-housing-mortgage': 'landmark',
  'expense-housing-property': 'building-complex',
  'expense-housing-utilities': 'plug-zap',
  'expense-housing-gas': 'flame',
  'expense-housing-repair': 'hammer',
  'expense-daily': 'package',
  'expense-daily-household': 'boxes',
  'expense-daily-personal': 'spray-can',
  'expense-daily-cleaning': 'shower-head',
  'expense-daily-haircut': 'scissors',
  'expense-daily-service': 'concierge-bell',
  'expense-entertainment': 'party-popper',
  'expense-entertainment-movie': 'clapperboard',
  'expense-entertainment-game': 'gamepad-2',
  'expense-entertainment-music': 'headphones',
  'expense-entertainment-subscription': 'badge-check',
  'expense-entertainment-hobby': 'palette',
  'expense-education': 'graduation-cap',
  'expense-education-book': 'book-open',
  'expense-education-course': 'presentation',
  'expense-education-exam': 'clipboard-check',
  'expense-education-stationery': 'pencil-ruler',
  'expense-education-tuition': 'school',
  'expense-medical': 'hospital',
  'expense-medical-clinic': 'stethoscope',
  'expense-medical-medicine': 'pill',
  'expense-medical-dental': 'scan-eye',
  'expense-medical-checkup': 'heart-pulse',
  'expense-medical-rehab': 'accessibility',
  'expense-communication': 'messages-square',
  'expense-communication-mobile': 'phone-call',
  'expense-communication-internet': 'router',
  'expense-communication-post': 'send',
  'expense-communication-cloud': 'cloud',
  'expense-social': 'users',
  'expense-social-gathering': 'utensils-crossed',
  'expense-social-red-packet': 'mail',
  'expense-social-gift': 'hand-coins',
  'expense-social-donation': 'heart-handshake',
  'expense-social-relationship': 'handshake',
  'expense-travel': 'map',
  'expense-travel-hotel': 'bed-double',
  'expense-travel-ticket': 'ticket-check',
  'expense-travel-local': 'tram-front',
  'expense-travel-attraction': 'ferris-wheel',
  'expense-travel-package': 'briefcase-business',
  'expense-travel-supplies': 'luggage',
  'expense-sports': 'trophy',
  'expense-sports-fitness': 'biceps-flexed',
  'expense-sports-equipment': 'volleyball',
  'expense-sports-venue': 'land-plot',
  'expense-sports-outdoor': 'mountain',
  'expense-sports-event': 'medal',
  'expense-pets': 'paw-print',
  'expense-pets-food': 'bone',
  'expense-pets-medical': 'syringe',
  'expense-pets-supplies': 'dog',
  'expense-pets-grooming': 'bath',
  'expense-pets-service': 'fence',
  'expense-digital': 'cpu',
  'expense-digital-phone': 'tablet-smartphone',
  'expense-digital-computer': 'laptop',
  'expense-digital-photo': 'camera',
  'expense-digital-accessory': 'cable',
  'expense-digital-software': 'app-window',
  'expense-digital-repair': 'drill',
  'expense-finance': 'badge-dollar-sign',
  'expense-finance-fee': 'receipt-text',
  'expense-finance-interest': 'percent',
  'expense-finance-insurance': 'shield-check',
  'expense-finance-tax': 'file-spreadsheet',
  'expense-finance-loan': 'hand-helping',
  'expense-finance-investment': 'chart-candlestick',
  'expense-family': 'house-heart',
  'expense-family-child': 'baby',
  'expense-family-elder': 'person-standing',
  'expense-family-support': 'hand-heart',
  'expense-family-education': 'book-heart',
  'expense-family-health': 'heart',
  'expense-other': 'circle-ellipsis',
  'expense-other-general': 'circle-question-mark',
  'expense-other-lost': 'triangle-alert',
  'expense-other-unexpected': 'zap',
  'income-salary': 'wallet-cards',
  'income-salary-monthly': 'banknote',
  'income-salary-bonus': 'badge-plus',
  'income-salary-allowance': 'piggy-bank',
  'income-salary-overtime': 'clock-plus',
  'income-reimbursement': 'receipt',
  'income-reimbursement-work': 'clipboard-plus',
  'income-reimbursement-travel': 'plane-landing',
  'income-reimbursement-medical': 'shield-plus',
  'income-reimbursement-other': 'file-question-mark',
  'income-parttime': 'briefcase',
  'income-parttime-freelance': 'pen-tool',
  'income-parttime-project': 'folder-kanban',
  'income-parttime-platform': 'panels-top-left',
  'income-parttime-consulting': 'speech',
  'income-investment': 'trending-up',
  'income-investment-interest': 'circle-percent',
  'income-investment-dividend': 'chart-no-axes-combined',
  'income-investment-fund': 'chart-spline',
  'income-investment-rent': 'map-pin-house',
  'income-investment-other': 'coins',
  'income-refund': 'rotate-ccw',
  'income-refund-shopping': 'shopping-bag',
  'income-refund-service': 'badge-minus',
  'income-refund-deposit': 'vault',
  'income-refund-tax': 'badge-percent',
  'income-other': 'circle-dollar-sign',
  'income-other-red-packet': 'mail-open',
  'income-other-secondhand': 'tag',
  'income-other-reward': 'badge-cent',
  'income-other-compensation': 'umbrella',
  'income-other-general': 'wallet-minimal',
};

const _accountIcons = <String, String>{
  'account-wechat': 'message-circle-more',
  'account-alipay': 'scan-line',
  'account-bank-card': 'credit-card',
  'account-cash': 'banknote-arrow-down',
  'account-other': 'wallet',
};

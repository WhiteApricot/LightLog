import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../data/database/database.dart';

class AccountPicker extends StatelessWidget {
  const AccountPicker({
    super.key,
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<Account> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('账户 / 支付方式', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 5,
            mainAxisExtent: 66,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
          ),
          itemCount: accounts.length,
          itemBuilder: (context, index) {
            final account = accounts[index];
            final selected = account.id == selectedId;
            return Semantics(
              button: true,
              selected: selected,
              label: account.name,
              child: InkWell(
                key: ValueKey('account-icon-${account.id}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(account),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primaryContainer
                        : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? colors.primary : colors.outlineVariant,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        account.iconAsset,
                        key: ValueKey('account-icon-image-${account.id}'),
                        width: 22,
                        height: 22,
                        colorFilter: ColorFilter.mode(
                          selected ? colors.primary : colors.onSurfaceVariant,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: selected
                              ? colors.onPrimaryContainer
                              : colors.onSurface,
                          fontWeight: selected ? FontWeight.w700 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

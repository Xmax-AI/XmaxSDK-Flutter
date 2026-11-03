import 'package:flutter/material.dart';

import '../../localization/xlab_localization.dart';
import '../../ui/xlab_theme.dart';
import 'feed_credit_balance.dart';

final class FeedCreditBalancePill extends StatelessWidget {
  const FeedCreditBalancePill({required this.state, super.key});

  final FeedCreditBalanceState state;

  @override
  Widget build(BuildContext context) {
    final localization = XLabLocalization.shared;
    final initialLoading = state.isLoading && state.balance == null;
    final value = state.balance == null && state.refreshFailed
        ? localization.text('feed.credits.unavailable')
        : formatFeedCreditBalance(state.balance);

    return Semantics(
      key: const ValueKey('feed.creditBalance'),
      container: true,
      excludeSemantics: true,
      label: localization.text('feed.credits'),
      value: initialLoading ? localization.text('feed.credits.loading') : value,
      hint: state.refreshFailed
          ? localization.text('feed.credits.refreshFailed')
          : null,
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: XLabPalette.mint.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: XLabPalette.mint.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                localization.text('feed.credits'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: XLabPalette.secondaryText,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (initialLoading)
              const SizedBox(
                key: ValueKey('feed-credit-loading'),
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  color: XLabPalette.mint,
                  strokeWidth: 1,
                ),
              )
            else
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: state.refreshFailed
                        ? XLabPalette.orange
                        : XLabPalette.mint,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

//
//  XmaxCreditBalance.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The server-reported credit balance for the account owning the client's API key.
final class XmaxCreditBalance {

  /// Creates a balance after the API payload has been validated.
  const XmaxCreditBalance._({
    required this.currentBalance,
  });

  /// Remaining credits as a finite, nonnegative value, including fractional credits.
  final double currentBalance;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is XmaxCreditBalance && currentBalance == other.currentBalance;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => currentBalance.hashCode;
}

/// Creates a credit balance from a validated account response.
///
/// [currentBalance] is the finite, nonnegative remaining credit amount.
XmaxCreditBalance createXmaxCreditBalance({
  required double currentBalance,
}) => XmaxCreditBalance._(currentBalance: currentBalance);

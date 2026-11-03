import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

typedef FeedCreditBalanceQuery = Future<double> Function();
typedef FeedCreditBalanceQueryFactory =
    FeedCreditBalanceQuery Function(String apiKey, XmaxEnvironment environment);

@immutable
final class FeedCreditBalanceState {
  const FeedCreditBalanceState({
    this.balance,
    this.isLoading = false,
    this.refreshFailed = false,
  });

  final double? balance;
  final bool isLoading;
  final bool refreshFailed;

  @override
  bool operator ==(Object other) =>
      other is FeedCreditBalanceState &&
      balance == other.balance &&
      isLoading == other.isLoading &&
      refreshFailed == other.refreshFailed;

  @override
  int get hashCode => Object.hash(balance, isLoading, refreshFailed);
}

typedef _Account = ({String key, XmaxEnvironment environment});

/// Refreshes credits only while the homepage is active and rejects replaced account results.
final class FeedCreditBalancePoller extends ChangeNotifier {
  FeedCreditBalancePoller({FeedCreditBalanceQueryFactory? makeQuery})
    : _makeQuery = makeQuery ?? _defaultQuery;

  final FeedCreditBalanceQueryFactory _makeQuery;
  FeedCreditBalanceState _state = const FeedCreditBalanceState();
  _Account? _account;
  Timer? _timer;
  int _revision = 0;
  bool _isRunning = false;
  bool _isDisposed = false;

  FeedCreditBalanceState get state => _state;

  static FeedCreditBalanceQuery _defaultQuery(
    String apiKey,
    XmaxEnvironment environment,
  ) {
    final client = XmaxClient(
      configuration: XmaxConfiguration(
        apiKey: apiKey,
        environment: environment,
      ),
    );
    return () async => (await client.getCreditBalance()).currentBalance;
  }

  void update({
    required String apiKey,
    required XmaxEnvironment environment,
    required bool isActive,
  }) {
    if (_isDisposed) return;
    final next = (key: apiKey.trim(), environment: environment);
    if (_account != next) {
      _pause();
      _account = next;
      _publish(const FeedCreditBalanceState());
    }

    if (_isDisposed) return;
    if (!isActive || next.key.isEmpty) {
      _pause();
      return;
    }
    if (_isRunning) return;

    _isRunning = true;
    final revision = ++_revision;
    _timer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_refresh(revision, next, null));
    });
  }

  Future<void> _refresh(
    int revision,
    _Account account,
    FeedCreditBalanceQuery? query,
  ) async {
    if (!_isCurrent(revision)) return;
    _timer = null;
    _publish(FeedCreditBalanceState(balance: _state.balance, isLoading: true));
    if (!_isCurrent(revision)) return;

    try {
      query ??= _makeQuery(account.key, account.environment);
      final balance = await query();
      if (!_isCurrent(revision)) return;
      _publish(FeedCreditBalanceState(balance: balance));
    } catch (_) {
      if (!_isCurrent(revision)) return;
      _publish(
        FeedCreditBalanceState(balance: _state.balance, refreshFailed: true),
      );
    }

    if (!_isCurrent(revision)) return;
    // Schedule after completion so a slow request never creates a polling backlog.
    _timer = Timer(const Duration(seconds: 5), () {
      unawaited(_refresh(revision, account, query));
    });
  }

  bool _isCurrent(int revision) =>
      !_isDisposed && _isRunning && revision == _revision;

  void _pause() {
    _revision++;
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    if (_state.isLoading) {
      _publish(
        FeedCreditBalanceState(
          balance: _state.balance,
          refreshFailed: _state.refreshFailed,
        ),
      );
    }
  }

  void _publish(FeedCreditBalanceState state) {
    if (_isDisposed || _state == state) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _revision++;
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

final _creditFormat = NumberFormat('#,##0.######', 'en_US');

String formatFeedCreditBalance(double? balance) =>
    balance == null ? '—' : _creditFormat.format(balance);

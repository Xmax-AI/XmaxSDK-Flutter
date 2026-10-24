//
//  XmaxStorageCancellationToken.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A one-shot cancellation signal for image and video uploads or downloads.
///
/// Create one token per transfer and pass it as `cancellationToken`.
/// Upload cancellation covers credential retrieval, COS transfer, and optional image safety checks.
/// It does not delete objects already accepted by storage or undo a completed upload.
/// Download cancellation preserves existing files and removes staged data before completion.
/// Cancellation cannot undo a committed file or interrupt replacement once it has started.
///
/// Cancelled transfers complete with `XmaxErrorCode.cancelled`. A cancelled token cannot be reset.
/// Sharing a token cancels all transfers using it; unrelated transfers are unaffected.
/// Use the token within the transfer's isolate.
final class XmaxStorageCancellationToken {

  /// Creates an uncancelled file transfer token.
  XmaxStorageCancellationToken();

  /// Whether cancellation has been requested, including after a download has completed.
  bool get isCancelled => _isCancelled;

  /// Whether this one-shot signal has been delivered.
  bool _isCancelled = false;

  /// Active observers, removed when their transfers finish.
  final Set<void Function()> _listeners = {};

  /// Requests cancellation of transfers using this token; repeated calls have no effect.
  ///
  /// This method signals cancellation synchronously. Await the transfer future to observe the
  /// cancellation error and resource cleanup. Completed transfers are unchanged.
  void cancel() {
    if (_isCancelled) {
      return;
    }

    _isCancelled = true;
    final listeners = _listeners.toList();
    _listeners.clear();

    for (final listener in listeners) {
      listener();
    }
  }
}

/// Registers an internal observer, delivering an existing cancellation immediately.
///
/// Parameters:
/// - [token]: The cancellation signal associated with the transfer.
/// - [listener]: The synchronous cancellation handler for that transfer.
///
/// Returns a function that detaches the observer when the transfer finishes.
void Function() observeStorageCancellation(
  XmaxStorageCancellationToken token,
  void Function() listener,
) {
  if (token._isCancelled) {
    listener();
  } else {
    token._listeners.add(listener);
  }

  return () {
    token._listeners.remove(listener);
  };
}

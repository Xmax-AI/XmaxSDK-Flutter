//
//  XmaxStorageCancellationToken.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A one-shot cancellation signal for image and video downloads.
///
/// Create one token per download and pass it as `cancellationToken`. Calling [cancel] before
/// destination replacement aborts the transfer with `XmaxErrorCode.cancelled`, preserves an
/// existing destination, and removes staged data before the download future completes.
/// Cancellation cannot undo a committed file or interrupt replacement once it has started.
///
/// A cancelled token cannot be reset. Sharing a token cancels all downloads using that token;
/// unrelated transfers are unaffected. Use the token within the download's isolate.
final class XmaxStorageCancellationToken {

  /// Creates an uncancelled download token.
  XmaxStorageCancellationToken();

  /// Whether cancellation has been requested, including after a download has completed.
  bool get isCancelled => _isCancelled;

  /// Whether this one-shot signal has been delivered.
  bool _isCancelled = false;

  /// Active observers, removed when their downloads finish.
  final Set<void Function()> _listeners = {};

  /// Requests cancellation of downloads using this token; repeated calls have no effect.
  ///
  /// This method signals cancellation synchronously. Await the download future to observe the
  /// cancellation error and completion of staged-file cleanup. Completed downloads are unchanged.
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
/// - [token]: The cancellation signal associated with the download.
/// - [listener]: The synchronous cancellation handler for that download.
///
/// Returns a function that detaches the observer when the download finishes.
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

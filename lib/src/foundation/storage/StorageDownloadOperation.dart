//
//  StorageDownloadOperation.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:io';

import '../errors/XmaxError.dart';
import '../logging/XmaxLogger.dart';
import 'DownloadedFile.dart';
import 'StorageProgressListener.dart';
import 'XmaxStorageCancellationToken.dart';

/// A file-backed download with operation-specific progress and staged destination replacement.
final class StorageDownloadOperation {

  /// Creates a download operation.
  const StorageDownloadOperation({
    StorageProgressListener? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) : _progress = progress,
       _cancellationToken = cancellationToken;

  /// The progress observer for this download.
  final StorageProgressListener? _progress;

  /// The caller's optional cancellation signal for this transfer.
  final XmaxStorageCancellationToken? _cancellationToken;

  /// Downloads a file and commits it after a successful HTTP response and complete file write.
  ///
  /// The existing destination remains untouched until commit. A private staging directory on the
  /// destination filesystem prevents cross-filesystem moves and is removed after success or failure.
  ///
  /// Parameters:
  /// - [client]: The HTTP client performing the transfer; the caller retains ownership.
  /// - [remoteURL]: The HTTP or HTTPS source URL, validated by the storage manager.
  /// - [destinationURL]: The local destination, which must not be a directory.
  ///
  /// Returns the committed file URI and its on-disk byte count.
  ///
  /// The returned future completes with an error if the response, transfer, file write, or commit
  /// fails. Progress observations do not establish that the destination has been committed.
  Future<DownloadedFile> value({
    required HttpClient client,
    required Uri remoteURL,
    required Uri destinationURL,
  }) async {
    final destination = File.fromUri(destinationURL);
    Directory? stagingDirectory;
    RandomAccessFile? output;
    HttpClientResponse? response;
    StreamIterator<List<int>>? chunks;
    var hasBodySubscription = false;
    final cancellation = _StorageDownloadCancellation(_cancellationToken);

    try {
      cancellation.check();
      await _validateDestination(destination);
      cancellation.check();

      final request = await cancellation.wait(
        client.getUrl(remoteURL).then(cancellation.attachRequest),
      );
      cancellation.check();
      final activeResponse = await cancellation.wait(
        request.close().then((
          received,
        ) async {
          // Headers may arrive after cancellation has already completed the caller's future.
          if (cancellation.isCancelled) {
            await received.listen(null).cancel();
            cancellation.check();
          }

          response = received;
          return received;
        }),
      );
      cancellation.check();

      chunks = StreamIterator<List<int>>(activeResponse);
      if (activeResponse.statusCode < 200 || activeResponse.statusCode >= 300) {
        throw XmaxError(
          code: XmaxErrorCode.downloadError,
          message: 'Storage download failed with HTTP ${activeResponse.statusCode}',
          httpStatus: activeResponse.statusCode,
        );
      }

      stagingDirectory = await destination.parent.createTemp('.xmax-download-');
      cancellation.check();

      final temporaryFile = File('${stagingDirectory.path}/download');

      output = await temporaryFile.open(mode: FileMode.write);
      cancellation.check();

      // Automatic decompression changes the byte count delivered by the response stream.
      // A compressed Content-Length cannot describe the size of the decoded destination file.
      final isDecompressed =
          activeResponse.compressionState == HttpClientResponseCompressionState.decompressed;
      final total = !isDecompressed && activeResponse.contentLength > 0
          ? activeResponse.contentLength
          : 0;
      var completed = 0;

      hasBodySubscription = true;
      while (await cancellation.wait(chunks.moveNext())) {
        cancellation.check();
        final chunk = chunks.current;

        // Await each write to apply backpressure and observe disk failures before commit.
        await output.writeFrom(chunk);
        cancellation.check();
        completed += chunk.length;
        if (total > 0 && completed > total) {
          throw const XmaxError(
            code: XmaxErrorCode.downloadError,
            message: 'Storage download exceeded the expected file size',
          );
        }

        _reportProgress(
          completed,
          total,
        );
      }

      await output.flush();
      await output.close();
      output = null;
      cancellation.check();

      final byteCount = await temporaryFile.length();

      if (byteCount != completed || (total > 0 && byteCount != total)) {
        throw const XmaxError(
          code: XmaxErrorCode.downloadError,
          message: 'Storage download did not produce the complete file',
        );
      }

      await _validateDestination(destination);
      cancellation.check();

      // Do not delete or truncate an existing destination before the completed file replaces it.
      // Commit admission is synchronous: cancellation cannot report failure after replacement.
      cancellation.detach();
      await temporaryFile.rename(destination.path);
      _reportProgress(
        byteCount,
        byteCount,
      );

      return DownloadedFile(
        fileURL: destinationURL,
        byteCount: byteCount,
      );
    } finally {
      cancellation.detach();

      // Cleanup must not replace the transfer or commit error with a secondary failure.
      try {
        if (hasBodySubscription) {
          await chunks?.cancel();
        } else {
          // StreamIterator subscribes lazily. Rejected responses still need an owned subscription
          // to release the connection when HTTP validation or staging fails before the first read.
          await response?.listen(null).cancel();
        }
      } catch (_) {}

      try {
        await output?.close();
      } catch (_) {}

      try {
        await stagingDirectory?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Rejects directories without modifying their contents, including a directory symlink target.
  ///
  /// Parameters:
  /// - [destination]: The target path to validate before transfer and immediately before commit.
  Future<void> _validateDestination(
    File destination,
  ) async {
    final type = await FileSystemEntity.type(destination.path);

    if (type == FileSystemEntityType.directory) {
      throw const XmaxError(
        code: XmaxErrorCode.downloadError,
        message: 'Storage download destination must not be a directory',
      );
    }
  }

  /// Reports bytes written without allowing observer failures to interrupt file transfer.
  ///
  /// Parameters:
  /// - [completed]: The number of bytes written to disk.
  /// - [total]: The expected file size, or zero when unknown until completion.
  void _reportProgress(
    int completed,
    int total,
  ) {
    try {
      _progress?.call(
        completed,
        total,
      );
    } catch (_) {
      // Observers must not turn a committed file into an apparent transfer failure.
      try {
        XmaxLogger.warn(
          category: XmaxLoggerCategory.storage,
          message: XmaxLogger.localized(
            '下载进度回调失败 (Download Progress Callback Failed)',
            'Download Progress Callback Failed',
          ),
        );
      } catch (_) {}
    }
  }
}

/// Owns cancellation of one request without closing its shared HTTP client.
final class _StorageDownloadCancellation {

  /// Binds the caller's signal for the lifetime of this download.
  _StorageDownloadCancellation(
    XmaxStorageCancellationToken? token,
  ) {
    if (token != null) {
      _detach = observeStorageCancellation(
        token,
        _cancel,
      );
    }
  }

  /// The error delivered when this transfer is cancelled.
  static const _error = XmaxError(
    code: XmaxErrorCode.cancelled,
    message: 'Storage download was cancelled',
  );

  /// Whether this download accepted cancellation before commit.
  bool _isCancelled = false;

  /// The interruption callback for the current passive network wait.
  void Function()? _interrupt;

  /// The request owned exclusively by this download, once acquired.
  HttpClientRequest? _request;

  /// The function that removes this download's cancellation observer.
  void Function()? _detach;

  /// Whether this download accepted cancellation before commit.
  bool get isCancelled => _isCancelled;

  /// Aborts this request and releases passive waits even when no body bytes arrive.
  void _cancel() {
    if (isCancelled) {
      return;
    }

    _isCancelled = true;
    _interrupt?.call();
    _abortRequest();
  }

  /// Aborts the owned request without allowing a transport failure to interrupt cancellation.
  void _abortRequest() {
    try {
      _request?.abort(_error);
    } catch (_) {}
  }

  /// Records request ownership, aborting requests acquired after cancellation.
  ///
  /// Parameters:
  /// - [request]: The request returned by the shared HTTP client.
  ///
  /// Returns the owned request, including when it was immediately aborted.
  HttpClientRequest attachRequest(
    HttpClientRequest request,
  ) {
    // A cancelled connection may yield a request after the caller has already returned.
    // Observe its terminal error even when no close call will be made.
    request.done.ignore();
    _request = request;
    if (isCancelled) {
      _abortRequest();
    }

    return request;
  }

  /// Completes a passive network wait on cancellation while observing late transport errors.
  ///
  /// Parameters:
  /// - [pending]: A request, response, or body read; not a resource-creating filesystem operation.
  ///
  /// Returns the network result, or completes with a cancellation error.
  Future<T> wait<T>(
    Future<T> pending,
  ) async {
    pending.ignore();
    check();

    final interruption = Completer<T>();

    _interrupt = () => interruption.completeError(_error);
    try {
      return await Future.any<T>([
        pending,
        interruption.future,
      ]);
    } finally {
      // Only the active network wait retains a cancellation observer, regardless of file size.
      _interrupt = null;
    }
  }

  /// Rejects further transfer or staging work once cancellation has been accepted.
  void check() {
    if (isCancelled) {
      throw _error;
    }
  }

  /// Stops observing the token at commit admission or transfer completion.
  void detach() {
    _detach?.call();
    _detach = null;
    _request = null;
  }
}

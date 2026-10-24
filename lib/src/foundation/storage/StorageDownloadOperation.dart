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

/// A file-backed download with operation-specific progress and staged destination replacement.
final class StorageDownloadOperation {

  /// Creates a download operation.
  const StorageDownloadOperation({
    StorageProgressListener? progress,
  }) : _progress = progress;

  /// The progress observer for this download.
  final StorageProgressListener? _progress;

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

    try {
      await _validateDestination(destination);

      final request = await client.getUrl(remoteURL);
      response = await request.close();

      chunks = StreamIterator<List<int>>(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XmaxError(
          code: XmaxErrorCode.downloadError,
          message: 'Storage download failed with HTTP ${response.statusCode}',
          httpStatus: response.statusCode,
        );
      }

      stagingDirectory = await destination.parent.createTemp('.xmax-download-');

      final temporaryFile = File('${stagingDirectory.path}/download');

      output = await temporaryFile.open(mode: FileMode.write);

      // Automatic decompression changes the byte count delivered by the response stream.
      // A compressed Content-Length cannot describe the size of the decoded destination file.
      final isDecompressed =
          response.compressionState == HttpClientResponseCompressionState.decompressed;
      final total = !isDecompressed && response.contentLength > 0
          ? response.contentLength
          : 0;
      var completed = 0;

      hasBodySubscription = true;
      while (await chunks.moveNext()) {
        final chunk = chunks.current;

        // Await each write to apply backpressure and observe disk failures before commit.
        await output.writeFrom(chunk);
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

      final byteCount = await temporaryFile.length();

      if (byteCount != completed || (total > 0 && byteCount != total)) {
        throw const XmaxError(
          code: XmaxErrorCode.downloadError,
          message: 'Storage download did not produce the complete file',
        );
      }

      await _validateDestination(destination);

      // Do not delete or truncate an existing destination before the completed file replaces it.
      // Staging beside the destination keeps the rename on the same filesystem.
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

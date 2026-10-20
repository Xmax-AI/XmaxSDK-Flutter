//
//  XmaxStorageManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/storage/StorageModels.dart';
import '../../service/storage/StorageServicing.dart';
import 'XmaxDownloadedFile.dart';
import 'XmaxStorageManaging.dart';
import 'XmaxStorageProgressHandler.dart';
import 'XmaxUploadedFile.dart';

/// 统一接收内存数据或本地文件，并返回 SDK 文件传输结果。
final class XmaxStorageManager implements XmaxStorageManaging {

  /// 创建文件传输管理器。
  XmaxStorageManager({
    required StorageServicing storageService,
  }) : _storageService = storageService;

  /// 包含凭证获取和安全检查的文件服务。
  final StorageServicing _storageService;

  /// 上传图片到对象存储；来源约束见 [XmaxStorageManaging]。
  ///
  /// 详细说明见 [XmaxStorageManaging.uploadImage]。
  @override
  Future<XmaxUploadedFile> uploadImage({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  }) => _upload(
    data: data,
    at: at,
    fileName: fileName,
    contentType: contentType,
    progress: progress,
    dataOperation: _storageService.uploadImage,
    fileOperation: _storageService.uploadImageFile,
  );

  /// 上传图片，并检查内容是否安全；未通过时抛出 unsafeImage 错误。
  ///
  /// 详细说明见 [XmaxStorageManaging.uploadImageWithSafetyCheck]。
  @override
  Future<XmaxUploadedFile> uploadImageWithSafetyCheck({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  }) => _upload(
    data: data,
    at: at,
    fileName: fileName,
    contentType: contentType,
    progress: progress,
    dataOperation: _storageService.uploadImageWithSafetyCheck,
    fileOperation: _storageService.uploadImageFileWithSafetyCheck,
  );

  /// 上传视频并返回对象存储结果；不创建实时视频输入流。
  ///
  /// 详细说明见 [XmaxStorageManaging.uploadVideo]。
  @override
  Future<XmaxUploadedFile> uploadVideo({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  }) => _upload(
    data: data,
    at: at,
    fileName: fileName,
    contentType: contentType,
    progress: progress,
    dataOperation: _storageService.uploadVideo,
    fileOperation: _storageService.uploadVideoFile,
  );

  /// 将远程图片下载到指定本地文件位置。
  ///
  /// 详细说明见 [XmaxStorageManaging.downloadImage]。
  @override
  Future<XmaxDownloadedFile> downloadImage({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
  }) async => _downloadedFile(
    await _storageService.downloadImage(
      remoteURL: from,
      destinationURL: to,
      progress: _progressListener(progress),
    ),
  );

  /// 将远程视频下载到指定本地文件位置。
  ///
  /// 详细说明见 [XmaxStorageManaging.downloadVideo]。
  @override
  Future<XmaxDownloadedFile> downloadVideo({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
  }) async => _downloadedFile(
    await _storageService.downloadVideo(
      remoteURL: from,
      destinationURL: to,
      progress: _progressListener(progress),
    ),
  );

  /// 校验上传来源并执行上传，返回成功保存的对象信息。
  ///
  /// - [data]：待上传的原始文件字节。
  /// - [at]：待上传的本地 file URI；与 data 二选一。文件来源使用 URI 中的文件名。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  /// - [dataOperation]：处理内存字节来源的上传操作。
  /// - [fileOperation]：处理本地文件来源的上传操作。
  ///
  /// 返回对象访问地址、对象键和可用的 ETag。
  Future<XmaxUploadedFile> _upload({
    required Uint8List? data,
    required Uri? at,
    required String? fileName,
    required String? contentType,
    required XmaxStorageProgressHandler? progress,
    required Future<StoredFile> Function({
      required Uint8List data,
      required String fileName,
      required String contentType,
      StorageProgressListener? progress,
    })
    dataOperation,
    required Future<StoredFile> Function({
      required Uri fileURL,
      String? contentType,
      StorageProgressListener? progress,
    })
    fileOperation,
  }) async {
    if ((data == null) == (at == null)) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Exactly one of data or at must be provided',
      );
    }

    final StoredFile stored;

    if (data != null) {
      final resolvedFileName = fileName?.trim() ?? '';
      final resolvedContentType = contentType?.trim() ?? '';

      if (resolvedFileName.isEmpty || resolvedContentType.isEmpty) {
        throw const XmaxError(
          code: XmaxErrorCode.invalidConfiguration,
          message: 'Data uploads require fileName and contentType',
        );
      }

      stored = await dataOperation(
        data: data,
        fileName: resolvedFileName,
        contentType: resolvedContentType,
        progress: _progressListener(progress),
      );
    } else {
      stored = await fileOperation(
        fileURL: at!,
        contentType: contentType,
        progress: _progressListener(progress),
      );
    }

    return createXmaxUploadedFile(
      url: stored.url,
      objectKey: stored.objectKey,
      etag: stored.etag,
    );
  }

  /// 将底层字节进度转换为 SDK 进度值。
  ///
  /// - [handler]：接收公开传输进度的回调；未指定时不创建适配函数。
  ///
  /// 返回底层字节进度监听器；未提供监听器时返回 null。
  StorageProgressListener? _progressListener(
    XmaxStorageProgressHandler? handler,
  ) => handler == null
      ? null
      : (completedBytes, totalBytes) => handler(
          XmaxStorageProgress(
            completedBytes: completedBytes.clamp(0, totalBytes),
            totalBytes: totalBytes,
          ),
        );

  /// 将底层下载结果转换为公开文件结果。
  ///
  /// - [file]：底层下载返回的本地文件结果。
  ///
  /// 返回下载后的本地文件 URI 和实际字节数。
  XmaxDownloadedFile _downloadedFile(
    DownloadedFile file,
  ) => createXmaxDownloadedFile(
    fileURL: file.fileURL,
    byteCount: file.byteCount,
  );
}

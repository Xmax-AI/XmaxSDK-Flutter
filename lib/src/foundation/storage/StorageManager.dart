//
//  StorageManager.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:io';

import 'package:tencentcloud_cos_sdk_plugin_nobeacon/cos.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/cos_transfer_manger.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/enums.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/fetch_credentials.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/pigeon.dart';

import '../errors/ErrorMessageFormatter.dart';
import '../errors/ErrorNormalizer.dart';
import '../errors/XmaxError.dart';
import 'StorageManaging.dart';
import 'StorageModels.dart';

/// 普通 PUT 上传阈值，用于禁止自动切换分片上传。
/// 配合强制普通上传选项，确保不同文件大小均使用单次 PUT。
const int _simpleUploadThreshold = 0x7FFFFFFFFFFFFFFF;

/// 封装腾讯 COS 上传和 HTTP 文件下载能力。
final class StorageManager implements StorageManaging {

  /// 创建对象上传和文件下载入口。
  ///
  /// - [httpClient]：下载使用的 HTTP 客户端；默认创建独立客户端。
  StorageManager({
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  /// HTTP 下载客户端；未指定时创建独立客户端。
  final HttpClient _httpClient;

  /// 共享凭证提供器的初始化任务。
  static Future<void>? _credentialProviderInitialization;

  /// 使用本次临时凭证执行普通 PUT 上传，不自动切换为分片上传。
  ///
  /// 详细说明见 [StorageManaging.upload]。
  @override
  Future<StoredFile> upload({
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
    StorageProgressListener? progress,
  }) async {
    _validateUpload(
      source: source,
      objectKey: objectKey,
      contentType: contentType,
      configuration: configuration,
    );

    final completer = Completer<StoredFile>();

    try {
      final transferManager = await _transferManager(configuration);
      final credential = configuration.credential;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // 每次上传都使用本次获取的临时会话凭证。
      final sessionCredentials = SessionQCloudCredentials(
        secretId: credential.accessKeyID,
        secretKey: credential.secretAccessKey,
        token: credential.sessionToken,
        startTime: now - 60,
        expiredTime: now + 25 * 60,
      );

      // 将插件回调转换为 Future，供 SDK 调用方等待上传结果。
      final resultListener = ResultListener(
        (headers, result) {
          if (completer.isCompleted) {
            return;
          }

          try {
            final candidate =
                result?.accessUrl ??
                headers?['location'] ??
                headers?['Location'];

            completer.complete(
              StoredFile(
                url: resolveObjectURL(
                  candidate: candidate,
                  configuration: configuration,
                  objectKey: objectKey,
                ),
                objectKey: objectKey,
                etag: result?.eTag ?? headers?['etag'] ?? headers?['ETag'],
              ),
            );
          } catch (error, stackTrace) {
            completer.completeError(error, stackTrace);
          }
        },
        (clientException, serviceException) {
          if (!completer.isCompleted) {
            final error = serviceException ?? clientException;

            completer.completeError(
              XmaxError(
                code: XmaxErrorCode.uploadError,
                message: error == null
                    ? 'Storage upload failed'
                    : ErrorMessageFormatter.format(error),
              ),
            );
          }
        },
      );

      void stateCallback(
        TransferState state,
      ) {
        if (state == TransferState.CANCELED && !completer.isCompleted) {
          completer.completeError(
            const XmaxError(
              code: XmaxErrorCode.cancelled,
              message: 'Storage upload was cancelled',
            ),
          );
        }
      }

      switch (source) {
        case StorageDataUploadSource(:final data):
          await transferManager.upload(
            configuration.bucket,
            objectKey,
            region: configuration.region,
            byteArr: data,
            customHeaders: <String, String>{'Content-Type': contentType},
            sessionCredentials: sessionCredentials,
            resultListener: resultListener,
            stateCallback: stateCallback,
            progressCallBack: progress,
          );
        case StorageFileUploadSource(:final fileURL):
          await transferManager.upload(
            configuration.bucket,
            objectKey,
            region: configuration.region,
            filePath: fileURL.toFilePath(),
            customHeaders: <String, String>{'Content-Type': contentType},
            sessionCredentials: sessionCredentials,
            resultListener: resultListener,
            stateCallback: stateCallback,
            progressCallBack: progress,
          );
      }

      return await completer.future;
    } on XmaxError {
      rethrow;
    } catch (error) {
      if (ErrorNormalizer.isCancellation(error)) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Storage upload was cancelled',
        );
      }

      throw XmaxError(
        code: XmaxErrorCode.uploadError,
        message: ErrorMessageFormatter.format(error),
      );
    }
  }

  /// 流式下载文件到本地目标，并返回实际写入的字节数。
  ///
  /// 详细说明见 [StorageManaging.download]。
  @override
  Future<DownloadedFile> download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) async {
    if (!_isHTTPURL(remoteURL)) {
      throw const XmaxError(
        code: XmaxErrorCode.downloadError,
        message: 'Storage download URL must use HTTP or HTTPS',
      );
    }

    if (!destinationURL.isScheme('file')) {
      throw const XmaxError(
        code: XmaxErrorCode.downloadError,
        message: 'Storage download destination must be a file URL',
      );
    }

    IOSink? sink;

    try {
      final request = await _httpClient.getUrl(remoteURL);
      final response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw XmaxError(
          code: XmaxErrorCode.downloadError,
          message: 'Storage download failed with HTTP ${response.statusCode}',
          httpStatus: response.statusCode,
        );
      }

      final target = File(destinationURL.toFilePath());

      sink = target.openWrite();

      var completed = 0;
      final total = response.contentLength;

      await for (final chunk in response) {
        sink.add(chunk);
        completed += chunk.length;
        if (total >= completed && total > 0) {
          progress?.call(completed, total);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      progress?.call(completed, completed);

      return DownloadedFile(fileURL: destinationURL, byteCount: completed);
    } on XmaxError {
      rethrow;
    } catch (error) {
      if (ErrorNormalizer.isCancellation(error)) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Storage download was cancelled',
        );
      }

      throw XmaxError(
        code: XmaxErrorCode.downloadError,
        message: ErrorMessageFormatter.format(error),
      );
    } finally {
      await sink?.close();
    }
  }

  /// 准备使用当前存储区域和凭证策略的传输管理器。
  ///
  /// - [configuration]：本次上传使用的存储桶、区域、服务地址和临时凭证。
  ///
  /// 返回当前区域的 COS 传输管理器。
  Future<CosTransferManger> _transferManager(
    StorageConfiguration configuration,
  ) async {
    // 先初始化原生签名器，再注册传输器；并发上传共享同一初始化任务。
    await (_credentialProviderInitialization ??= Cos()
        .initWithSessionCredential(_RequestOnlyCredentials()));

    final key =
        'xmax-simple-${configuration.region}-'
        '${configuration.endpoint.hashCode}-${configuration.bucket.hashCode}';

    if (Cos().hasTransferManger(key)) {
      return Cos().getTransferManger(key);
    }

    final endpoint = _normalizedEndpoint(configuration.endpoint);

    return Cos().registerTransferManger(
      key,
      CosXmlServiceConfig(
        region: configuration.region,
        isHttps: endpoint == null || endpoint.isScheme('https'),
        host: endpoint?.host,
        port: endpoint?.hasPort == true ? endpoint?.port : null,
      ),
      TransferConfig(
        forceSimpleUpload: true,
        divisionForUpload: _simpleUploadThreshold,
      ),
    );
  }

  /// 校验上传来源、对象信息和凭证是否满足传输要求。
  ///
  /// - [source]：待上传的内存字节或本地文件来源。
  /// - [objectKey]：对象在存储桶内的完整键，不是本地文件路径。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [configuration]：本次上传使用的存储桶、区域、服务地址和临时凭证。
  void _validateUpload({
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
  }) {
    final identifier = RegExp(r'^[A-Za-z0-9.-]+$');
    final credential = configuration.credential;

    if (!identifier.hasMatch(configuration.bucket.trim())) {
      throw const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'Storage bucket is invalid',
      );
    }

    if (!identifier.hasMatch(configuration.region.trim())) {
      throw const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'Storage region is invalid',
      );
    }

    if (objectKey.trim().isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'Storage object key is invalid',
      );
    }

    if (contentType.trim().isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'Storage content type cannot be empty',
      );
    }

    if (credential.accessKeyID.trim().isEmpty ||
        credential.secretAccessKey.trim().isEmpty ||
        credential.sessionToken.trim().isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'Storage temporary credential is incomplete',
      );
    }

    if (source case StorageFileUploadSource(:final fileURL)) {
      if (!fileURL.isScheme('file') ||
          !File(fileURL.toFilePath()).existsSync()) {
        throw const XmaxError(
          code: XmaxErrorCode.uploadError,
          message: 'Storage upload file is unavailable',
        );
      }
    }
  }

  /// 解析有效对象访问地址，必要时依据存储配置和对象键构造地址。
  ///
  /// - [candidate]：对象存储返回的候选访问地址。
  /// - [configuration]：本次上传使用的存储桶、区域、服务地址和临时凭证。
  /// - [objectKey]：对象在存储桶内的完整键，不是本地文件路径。
  ///
  /// 返回经过校验或根据对象键构造的对象访问 URL。
  static Uri resolveObjectURL({
    required String? candidate,
    required StorageConfiguration configuration,
    required String objectKey,
  }) {
    final location = candidate?.trim() ?? '';

    if (location.startsWith('//')) {
      final url = Uri.tryParse('https:$location');

      if (url != null) {
        return url;
      }
    }

    final candidateURL = Uri.tryParse(location);

    if (candidateURL != null && _isHTTPURL(candidateURL)) {
      return candidateURL;
    }

    final configuredEndpoint = _normalizedEndpoint(configuration.endpoint);
    final endpoint =
        configuredEndpoint ??
        Uri.parse(
          'https://${configuration.bucket}.cos.'
          '${configuration.region}.myqcloud.com',
        );

    final segments = <String>[
      ...endpoint.pathSegments.where((segment) => segment.isNotEmpty),
      ...objectKey.split('/'),
    ];

    return endpoint.replace(pathSegments: segments);
  }

  /// 将非空服务地址规范化为 HTTP 或 HTTPS URI；地址格式无效时抛出上传错误。
  ///
  /// - [value]：对象存储服务的地址文本，可省略 https 前缀。
  ///
  /// 返回规范化的 HTTP 或 HTTPS URI；输入空白时为 null，格式无效时抛出上传错误。
  static Uri? _normalizedEndpoint(
    String value,
  ) {
    final endpoint = value.trim();

    if (endpoint.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(
      endpoint.contains('://') ? endpoint : 'https://$endpoint',
    );

    if (uri == null || !_isHTTPURL(uri)) {
      throw const XmaxError(
        code: XmaxErrorCode.uploadError,
        message: 'Storage endpoint is invalid',
      );
    }

    return uri;
  }

  /// 检查 URI 是否具有有效的 HTTP 或 HTTPS 服务地址。
  ///
  /// - [uri]：待校验或读取的 URI。
  ///
  /// 返回 URI 是否使用 HTTP 或 HTTPS 且包含非空主机名。
  static bool _isHTTPURL(
    Uri uri,
  ) => (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty;
}

/// 禁止使用全局凭证回退，确保每次上传仅使用当前请求的临时凭证。
final class _RequestOnlyCredentials implements IFetchCredentials {

  /// 拒绝全局凭证回退；上传必须显式提交本次请求的临时凭证。
  ///
  /// 不返回凭证；Future 始终以上传错误结束，禁止使用全局凭证回退。
  @override
  Future<SessionQCloudCredentials> fetchSessionCredentials() async {
    throw const XmaxError(
      code: XmaxErrorCode.uploadError,
      message: 'Storage request is missing its temporary credential',
    );
  }
}

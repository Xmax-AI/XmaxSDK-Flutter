//
//  StorageService.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../foundation/errors/ErrorMessageFormatter.dart';
import '../../foundation/errors/ErrorNormalizer.dart';
import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/logging/XmaxLoggerOption.dart';
import '../../foundation/media/MediaFileMetadataManager.dart';
import '../../foundation/storage/StorageManaging.dart';
import '../../foundation/storage/StorageModels.dart';
import '../network/ApiServicing.dart';
import 'StorageServicing.dart';

/// 上传文件的媒体类别及日志展示名称。
enum _StorageMediaType {

  /// 图片文件。
  image('image', 'Image'),

  /// 视频文件。
  video('video', 'Video');

  /// 定义上传媒体类别及日志名称。
  const _StorageMediaType(
    this.value,
    this.displayName,
  );

  /// 序列化时使用的值。
  final String value;

  /// 用于界面或日志展示的名称。
  final String displayName;
}

/// 获取临时凭证，校验上传下载参数，并按需执行图片安全检查。
final class StorageService implements StorageServicing {

  /// 创建凭证获取、参数校验及文件安全检查服务。
  ///
  /// - [apiService]：凭证和安全检查的网络服务。
  /// - [storageManager]：对象上传与文件下载入口。
  /// - [dateGenerator]：对象键时间戳来源，默认使用系统时间。
  /// - [identifierGenerator]：对象键随机标识来源，默认生成 UUID。
  StorageService({
    required ApiServicing apiService,
    required StorageManaging storageManager,
    DateTime Function()? dateGenerator,
    String Function()? identifierGenerator,
  }) : _apiService = apiService,
       _storageManager = storageManager,
       _dateGenerator = dateGenerator ?? DateTime.now,
       _identifierGenerator = identifierGenerator ?? _makeIdentifier;

  /// 云端 API 请求服务。
  final ApiServicing _apiService;

  /// 执行对象上传及 HTTP 下载的底层组件。
  final StorageManaging _storageManager;

  /// 生成对象键时间戳的时间提供函数。
  final DateTime Function() _dateGenerator;

  /// 生成随机对象标识的函数。
  final String Function() _identifierGenerator;

  /// 上传内存图片到对象存储。
  ///
  /// 详细说明见 [StorageServicing.uploadImage]。
  @override
  Future<StoredFile> uploadImage({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  }) async => _upload(
    source: StorageDataUploadSource(data),
    fileName: fileName,
    contentType: contentType,
    mediaType: _StorageMediaType.image,
    checksSafety: false,
    progress: progress,
  );

  /// 上传本地图片文件；未指定 MIME 类型时按扩展名推断。
  ///
  /// 详细说明见 [StorageServicing.uploadImageFile]。
  @override
  Future<StoredFile> uploadImageFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  }) async => _upload(
    source: StorageFileUploadSource(fileURL),
    fileName: _fileName(fileURL),
    contentType: contentType ?? _inferImageContentType(_fileName(fileURL)),
    mediaType: _StorageMediaType.image,
    checksSafety: false,
    progress: progress,
  );

  /// 上传图片并执行内容安全检查；未通过时抛出 unsafeImage。
  ///
  /// 详细说明见 [StorageServicing.uploadImageWithSafetyCheck]。
  @override
  Future<StoredFile> uploadImageWithSafetyCheck({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  }) => _upload(
    source: StorageDataUploadSource(data),
    fileName: fileName,
    contentType: contentType,
    mediaType: _StorageMediaType.image,
    checksSafety: true,
    progress: progress,
  );

  /// 上传本地图片并执行内容安全检查；未通过时抛出 unsafeImage。
  ///
  /// 详细说明见 [StorageServicing.uploadImageFileWithSafetyCheck]。
  @override
  Future<StoredFile> uploadImageFileWithSafetyCheck({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  }) async => _upload(
    source: StorageFileUploadSource(fileURL),
    fileName: _fileName(fileURL),
    contentType: contentType ?? _inferImageContentType(_fileName(fileURL)),
    mediaType: _StorageMediaType.image,
    checksSafety: true,
    progress: progress,
  );

  /// 上传视频并返回对象存储结果；不创建实时视频输入流。
  ///
  /// 详细说明见 [StorageServicing.uploadVideo]。
  @override
  Future<StoredFile> uploadVideo({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  }) => _upload(
    source: StorageDataUploadSource(data),
    fileName: fileName,
    contentType: contentType,
    mediaType: _StorageMediaType.video,
    checksSafety: false,
    progress: progress,
  );

  /// 上传本地视频文件；未指定 MIME 类型时按扩展名推断。
  ///
  /// 详细说明见 [StorageServicing.uploadVideoFile]。
  @override
  Future<StoredFile> uploadVideoFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  }) async => _upload(
    source: StorageFileUploadSource(fileURL),
    fileName: _fileName(fileURL),
    contentType: contentType ?? _inferVideoContentType(_fileName(fileURL)),
    mediaType: _StorageMediaType.video,
    checksSafety: false,
    progress: progress,
  );

  /// 将远程图片下载到指定本地文件位置。
  ///
  /// 详细说明见 [StorageServicing.downloadImage]。
  @override
  Future<DownloadedFile> downloadImage({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) => _download(
    remoteURL: remoteURL,
    destinationURL: destinationURL,
    progress: progress,
  );

  /// 将远程视频下载到指定本地文件位置。
  ///
  /// 详细说明见 [StorageServicing.downloadVideo]。
  @override
  Future<DownloadedFile> downloadVideo({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) => _download(
    remoteURL: remoteURL,
    destinationURL: destinationURL,
    progress: progress,
  );

  /// 校验上传来源并执行上传，返回成功保存的对象信息。
  ///
  /// - [source]：待上传的内存字节或本地文件来源。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [mediaType]：上传文件的媒体类型：图片或视频。
  /// - [checksSafety]：是否在上传后执行图片安全检查。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> _upload({
    required StorageUploadSource source,
    required String fileName,
    required String contentType,
    required _StorageMediaType mediaType,
    required bool checksSafety,
    StorageProgressListener? progress,
  }) async {
    final startedAt = DateTime.now();

    try {
      final safeName = _validateUpload(
        source: source,
        fileName: fileName,
        contentType: contentType,
        mediaType: mediaType,
      );
      final byteCount = _sourceByteCount(source);
      final resolution = XmaxLogger.isEnabled(XmaxLoggerOption.business)
          ? await const MediaFileMetadataManager().readResolution(
              source,
              isVideo: mediaType == _StorageMediaType.video,
            )
          : '--';

      XmaxLogger.info(
        category: XmaxLoggerCategory.storage,
        message:
            '开始上传 (Upload Started)\n'
            '├─ ${XmaxLogger.localized('类型：', 'Type: ')}${mediaType.value}\n'
            '├─ ${XmaxLogger.localized('分辨率：', 'Resolution: ')}$resolution\n'
            '├─ ${XmaxLogger.localized('大小：', 'Size: ')}${_formatByteCount(byteCount)}\n'
            '└─ ${XmaxLogger.localized('安全检测：', 'Safety Check: ')}$checksSafety',
      );

      final temporary = await _fetchStorageConfiguration();
      final objectKey = _makeObjectKey(temporary.prefix, safeName);

      final stored = await _storageManager.upload(
        source: source,
        objectKey: objectKey,
        contentType: contentType.trim(),
        configuration: temporary.configuration,
        progress: progress,
      );

      final StoredFile result;

      if (checksSafety) {
        // 安全检测接口接收图片地址，因此先上传到 COS，再执行检测。
        final checkedURL = await _checkImage(stored.url);

        result = StoredFile(
          url: checkedURL,
          objectKey: stored.objectKey,
          etag: stored.etag,
        );
      } else {
        result = stored;
      }

      XmaxLogger.info(
        category: XmaxLoggerCategory.storage,
        message:
            '上传完成 (Upload Completed)\n'
            '├─ ${XmaxLogger.localized('地址：', 'URL: ')}${result.url}\n'
            '└─ ${XmaxLogger.localized('耗时：', 'Duration: ')}${_formatDuration(startedAt)}',
      );

      return result;
    } on XmaxError catch (error) {
      _logUploadFailure(error, startedAt);
      rethrow;
    } catch (error) {
      if (ErrorNormalizer.isCancellation(error)) {
        const cancelledError = XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Storage upload was cancelled',
        );

        _logUploadFailure(cancelledError, startedAt);
        throw cancelledError;
      }

      final uploadError = XmaxError(
        code: XmaxErrorCode.uploadError,
        message: ErrorMessageFormatter.format(error),
      );

      _logUploadFailure(uploadError, startedAt);
      throw uploadError;
    }
  }

  /// 读取上传来源的实际字节数。
  ///
  /// - [source]：内存字节或本地文件来源，不读取完整文件内容。
  ///
  /// 返回上传来源的字节数，本地文件不存在时抛出文件访问错误。
  static int _sourceByteCount(
    StorageUploadSource source,
  ) => switch (source) {
    StorageDataUploadSource(:final data) => data.length,
    StorageFileUploadSource(:final fileURL) => File(
      fileURL.toFilePath(),
    ).lengthSync(),
  };

  /// 按便于阅读的容量单位格式化字节数。
  ///
  /// - [byteCount]：文件大小，单位为字节。
  ///
  /// 返回使用 B、KB、MB 或 GB 表示的文件容量。
  static String _formatByteCount(
    int byteCount,
  ) {
    final count = byteCount.toDouble();

    if (byteCount < 1024) return '$byteCount B';

    if (byteCount < 1024 * 1024) {
      return '${(count / 1024).toStringAsFixed(1)} KB';
    }

    if (byteCount < 1024 * 1024 * 1024) {
      return '${(count / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return '${(count / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 将操作开始时间到现在的耗时格式化为毫秒或秒。
  ///
  /// - [startedAt]：当前操作的开始时间，用于计算耗时。
  ///
  /// 返回从开始时刻到当前时间的耗时文本；不足一秒使用 ms，否则使用 s。
  static String _formatDuration(
    DateTime startedAt,
  ) {
    final milliseconds = DateTime.now().difference(startedAt).inMilliseconds;

    if (milliseconds < 1000) return '$milliseconds ms';

    return '${(milliseconds / 1000).toStringAsFixed(2)} s';
  }

  /// 记录上传失败原因和已用时间。
  ///
  /// - [error]：本次操作的错误。
  /// - [startedAt]：当前操作的开始时间，用于计算耗时。
  static void _logUploadFailure(
    XmaxError error,
    DateTime startedAt,
  ) {
    XmaxLogger.error(
      category: XmaxLoggerCategory.storage,
      message:
          '上传失败 (Upload Failed)\n'
          '├─ ${XmaxLogger.localized('错误码：', 'Error Code: ')}${error.code.value}\n'
          '├─ ${XmaxLogger.localized('原因：', 'Reason: ')}${error.message}\n'
          '└─ ${XmaxLogger.localized('耗时：', 'Duration: ')}${_formatDuration(startedAt)}',
    );
  }

  /// 校验下载地址并将文件写入本地目标位置。
  ///
  /// - [remoteURL]：待下载文件的 HTTP 或 HTTPS URL。
  /// - [destinationURL]：下载目标的本地 file URI。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回已下载文件的本地 URI 和实际字节数。
  Future<DownloadedFile> _download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) async {
    _validateDownload(remoteURL, destinationURL);

    return _storageManager.download(
      remoteURL: remoteURL,
      destinationURL: destinationURL,
      progress: progress,
    );
  }

  /// 获取本次上传的存储区域、对象前缀和临时凭证。
  ///
  /// 返回云端授权的对象前缀及临时存储配置。
  Future<_TemporaryStorageConfiguration> _fetchStorageConfiguration() async {
    final payload = await _apiService.get<Map<String, dynamic>>(
      '/cos/sts',
      (json) => Map<String, dynamic>.from(json! as Map),
    );

    const message = 'Invalid storage credential payload';
    final credentials = payload['credentials'];
    final bucket = _requiredString(payload['bucket']);
    final region = _requiredString(payload['region']);
    final endpoint = _normalizedString(payload['endpoint']);
    final prefix = _normalizedString(payload['prefix']);

    if (credentials is! Map ||
        bucket == null ||
        region == null ||
        endpoint == null ||
        prefix == null) {
      throw const XmaxError(code: XmaxErrorCode.apiError, message: message);
    }

    final accessKeyID = _requiredString(credentials['accessKeyId']);
    final secretAccessKey = _requiredString(credentials['secretAccessKey']);
    final sessionToken = _requiredString(credentials['sessionToken']);

    if (accessKeyID == null ||
        secretAccessKey == null ||
        sessionToken == null) {
      throw const XmaxError(code: XmaxErrorCode.apiError, message: message);
    }

    return _TemporaryStorageConfiguration(
      prefix: prefix,
      configuration: StorageConfiguration(
        bucket: bucket,
        region: region,
        endpoint: endpoint,
        credential: StorageCredential(
          accessKeyID: accessKeyID,
          secretAccessKey: secretAccessKey,
          sessionToken: sessionToken,
        ),
      ),
    );
  }

  /// 请求图片内容安全检查，返回审核通过的访问地址。
  ///
  /// - [url]：上传对象的访问地址。
  ///
  /// 返回经过校验的访问地址或文件 URI。
  Future<Uri> _checkImage(
    Uri url,
  ) async {
    final payload = await _apiService.post<Map<String, dynamic>>(
      '/cos/image/check',
      (json) => Map<String, dynamic>.from(json! as Map),
      body: <String, Object?>{'url': url.toString()},
    );

    const message = 'Invalid image safety check payload';
    final safe = payload['safe'];

    if (safe is! bool) {
      throw const XmaxError(code: XmaxErrorCode.apiError, message: message);
    }

    if (!safe) {
      throw const XmaxError(
        code: XmaxErrorCode.unsafeImage,
        message: 'The image did not pass the safety check',
      );
    }

    final value = _normalizedString(payload['url']);
    final checkedURL = value == null ? null : Uri.tryParse(value);

    if (checkedURL == null || !_isHTTPURL(checkedURL)) {
      throw const XmaxError(code: XmaxErrorCode.apiError, message: message);
    }

    return checkedURL;
  }

  /// 校验上传来源、对象信息和凭证是否满足传输要求。
  ///
  /// - [source]：待上传的内存字节或本地文件来源。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [mediaType]：上传文件的媒体类型：图片或视频。
  ///
  /// 返回清理后的文件名；文件来源或 MIME 类型不合法时抛出配置错误。
  String _validateUpload({
    required StorageUploadSource source,
    required String fileName,
    required String contentType,
    required _StorageMediaType mediaType,
  }) {
    switch (source) {
      case StorageDataUploadSource(:final data):
        if (data.isEmpty) {
          throw XmaxError(
            code: XmaxErrorCode.invalidConfiguration,
            message: '${mediaType.displayName} data cannot be empty',
          );
        }
      case StorageFileUploadSource(:final fileURL):
        if (!fileURL.isScheme('file') ||
            fileURL.toFilePath().isEmpty ||
            !File(fileURL.toFilePath()).existsSync()) {
          throw XmaxError(
            code: XmaxErrorCode.invalidConfiguration,
            message:
                '${mediaType.displayName} file URL must reference an '
                'existing file',
          );
        }
    }

    if (!contentType.trim().toLowerCase().startsWith('${mediaType.value}/')) {
      throw XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message:
            '${mediaType.displayName} content type must begin with '
            '${mediaType.value}/',
      );
    }

    final safeName = _sanitizeFileName(fileName);

    if (safeName.isEmpty) {
      throw XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: '${mediaType.displayName} file name cannot be empty',
      );
    }

    return safeName;
  }

  /// 校验远程下载地址和本地目标文件 URI。
  ///
  /// - [remoteURL]：待下载文件的 HTTP 或 HTTPS URL。
  /// - [destinationURL]：下载目标的本地 file URI。
  void _validateDownload(
    Uri remoteURL,
    Uri destinationURL,
  ) {
    if (!_isHTTPURL(remoteURL)) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Invalid download URL',
      );
    }

    if (!destinationURL.isScheme('file') || destinationURL.path.isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Download destination URL must be a file URL',
      );
    }
  }

  /// 根据受支持的图片扩展名推断 MIME 类型。
  ///
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  ///
  /// 返回受支持图片格式的 MIME 类型；无法推断时抛出配置错误。
  String _inferImageContentType(
    String fileName,
  ) => _inferContentType(fileName, const <String, String>{
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'jpe': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'heif': 'image/heif',
    'bmp': 'image/bmp',
    'svg': 'image/svg+xml',
    'tif': 'image/tiff',
    'tiff': 'image/tiff',
    'avif': 'image/avif',
  }, 'image');

  /// 根据受支持的视频扩展名推断 MIME 类型。
  ///
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  ///
  /// 返回受支持视频格式的 MIME 类型；无法推断时抛出配置错误。
  String _inferVideoContentType(
    String fileName,
  ) => _inferContentType(fileName, const <String, String>{
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4v': 'video/x-m4v',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    '3gp': 'video/3gpp',
    '3g2': 'video/3gpp2',
    'ts': 'video/mp2t',
  }, 'video');

  /// 根据媒体类别和扩展名映射推断 MIME 类型；不支持时抛出配置错误。
  ///
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [types]：扩展名与 MIME 类型的映射。
  /// - [mediaType]：上传文件的媒体类型：图片或视频。
  ///
  /// 返回扩展名映射的 MIME 类型；未命中时抛出配置错误。
  String _inferContentType(
    String fileName,
    Map<String, String> types,
    String mediaType,
  ) {
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    final contentType = types[extension];

    if (contentType == null) {
      throw XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'Unable to infer $mediaType content type from file extension',
      );
    }

    return contentType;
  }

  /// 清理文件名中的非法字符，避免将本地目录写入对象键。
  ///
  /// - [value]：需要去除不安全字符和首尾标点的原始文件名。
  ///
  /// 返回仅保留安全字符并去除首尾标点的文件名，结果可能为空。
  String _sanitizeFileName(
    String value,
  ) {
    var result = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp('_+'), '_');

    result = result.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');

    return result;
  }

  /// 组合授权前缀、毫秒时间戳、随机标识和安全文件名，生成存储对象键。
  ///
  /// - [prefix]：云端允许写入的对象键前缀。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  ///
  /// 返回包含授权前缀、毫秒时间戳和随机标识的对象键。
  String _makeObjectKey(
    String prefix,
    String fileName,
  ) =>
      '$prefix${_dateGenerator().millisecondsSinceEpoch}_'
      '${_identifierGenerator().toLowerCase()}_$fileName';

  /// 从本地文件 URI 提取文件名。
  ///
  /// - [uri]：待校验或读取的 URI。
  ///
  /// 返回 URI 的最后一段路径；没有路径段时为空字符串。
  static String _fileName(
    Uri uri,
  ) {
    if (uri.pathSegments.isEmpty) {
      return '';
    }

    return uri.pathSegments.last;
  }

  /// 去除字符串响应字段两端空白；非字符串字段返回 null。
  ///
  /// - [value]：需要清除首尾空白的响应字段；非字符串返回 null。
  ///
  /// 返回去除两端空白的字符串，包括空字符串；输入不是字符串时为 null。
  static String? _normalizedString(
    Object? value,
  ) => value is String ? value.trim() : null;

  /// 读取非空字符串字段。
  ///
  /// - [value]：响应字段；不是字符串或去除首尾空白后为空时返回 null。
  static String? _requiredString(
    Object? value,
  ) {
    final normalized = _normalizedString(value);

    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  /// 检查 URI 是否具有有效的 HTTP 或 HTTPS 服务地址。
  ///
  /// - [uri]：待校验或读取的 URI。
  ///
  /// 返回 URI 是否使用 HTTP 或 HTTPS 且包含非空主机名。
  static bool _isHTTPURL(
    Uri uri,
  ) =>
      (uri.isScheme('https') || uri.isScheme('http')) &&
      uri.host.trim().isNotEmpty;

  /// 生成用于存储对象键的随机 UUID。
  static String _makeIdentifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // 按 RFC 4122 设置版本位和变体位，再生成 UUID 文本。
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final value = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

/// 云端签发的对象键前缀和临时存储配置。
final class _TemporaryStorageConfiguration {

  /// 保存临时凭证及允许写入的对象键前缀。
  const _TemporaryStorageConfiguration({
    required this.prefix,
    required this.configuration,
  });

  /// 云端允许写入的对象键前缀。
  final String prefix;

  /// 本次上传使用的区域、存储桶和临时访问凭证。
  final StorageConfiguration configuration;
}

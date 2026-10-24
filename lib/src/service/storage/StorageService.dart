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
import '../../foundation/storage/DownloadedFile.dart';
import '../../foundation/storage/StorageConfiguration.dart';
import '../../foundation/storage/StorageCredential.dart';
import '../../foundation/storage/StorageManaging.dart';
import '../../foundation/storage/StorageProgressListener.dart';
import '../../foundation/storage/StorageUploadSource.dart';
import '../../foundation/storage/StoredFile.dart';
import '../network/ApiServicing.dart';
import 'StorageServicing.dart';

/// An upload media type and its display name for logging.
enum _StorageMediaType {

  /// An image file.
  image(
    'image',
    'Image',
  ),

  /// A video file.
  video(
    'video',
    'Video',
  );

  /// Defines an upload media type and log display name.
  const _StorageMediaType(
    this.value,
    this.displayName,
  );

  /// The serialized value.
  final String value;

  /// The name used in UI or logs.
  final String displayName;
}

/// Coordinates media transfers, temporary credentials, and image safety checks.
final class StorageService implements StorageServicing {

  /// Creates a service for credentials, transfer validation, and file safety checks.
  ///
  /// Parameters:
  /// - [apiService]: The API service for credentials and safety checks.
  /// - [storageManager]: The object upload and file download transport.
  /// - [dateGenerator]: The timestamp provider for object keys; defaults to the system time.
  /// - [identifierGenerator]: The random identifier provider for object keys; defaults to UUID
  ///   generation.
  StorageService({
    required ApiServicing apiService,
    required StorageManaging storageManager,
    DateTime Function()? dateGenerator,
    String Function()? identifierGenerator,
  }) : _apiService = apiService,
       _storageManager = storageManager,
       _dateGenerator = dateGenerator ?? DateTime.now,
       _identifierGenerator = identifierGenerator ?? _makeIdentifier;

  /// The service used for API requests.
  final ApiServicing _apiService;

  /// The underlying object upload and HTTP download transport.
  final StorageManaging _storageManager;

  /// The timestamp provider for object keys.
  final DateTime Function() _dateGenerator;

  /// The random object identifier generator.
  final String Function() _identifierGenerator;

  /// Uploads an in-memory image to object storage.
  ///
  /// See [StorageServicing.uploadImage] for the usage contract.
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

  /// Uploads a local image, inferring its MIME type from the extension if unspecified.
  ///
  /// See [StorageServicing.uploadImageFile] for the usage contract.
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

  /// Uploads an image and checks content safety; throws unsafeImage if rejected.
  ///
  /// See [StorageServicing.uploadImageWithSafetyCheck] for the usage contract.
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

  /// Uploads a local image and checks content safety; throws unsafeImage if rejected.
  ///
  /// See [StorageServicing.uploadImageFileWithSafetyCheck] for the usage contract.
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

  /// Uploads a video file without creating a realtime video input stream.
  ///
  /// See [StorageServicing.uploadVideo] for the usage contract.
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

  /// Uploads a local video, inferring its MIME type from the extension if unspecified.
  ///
  /// See [StorageServicing.uploadVideoFile] for the usage contract.
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

  /// Downloads an image to a local file.
  ///
  /// See [StorageServicing.downloadImage] for the usage contract.
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

  /// Downloads a video to a local file.
  ///
  /// See [StorageServicing.downloadVideo] for the usage contract.
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

  /// Validates an upload source and returns the stored object.
  ///
  /// Parameters:
  /// - [source]: The in-memory bytes or local file to upload.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [mediaType]: The upload media type: image or video.
  /// - [checksSafety]: Whether to check image safety after uploading.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
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
      final objectKey = _makeObjectKey(
        temporary.prefix,
        safeName,
      );

      final stored = await _storageManager.upload(
        source: source,
        objectKey: objectKey,
        contentType: contentType.trim(),
        configuration: temporary.configuration,
        progress: progress,
      );

      final StoredFile result;

      if (checksSafety) {
        // The safety endpoint requires an image URL; upload to COS before requesting the check.
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
      _logUploadFailure(
        error,
        startedAt,
      );
      rethrow;
    } catch (error) {
      if (ErrorNormalizer.isCancellation(error)) {
        const cancelledError = XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'Storage upload was cancelled',
        );

        _logUploadFailure(
          cancelledError,
          startedAt,
        );
        throw cancelledError;
      }

      final uploadError = XmaxError(
        code: XmaxErrorCode.uploadError,
        message: ErrorMessageFormatter.format(error),
      );

      _logUploadFailure(
        uploadError,
        startedAt,
      );
      throw uploadError;
    }
  }

  /// Reads the upload source's actual byte count.
  ///
  /// Parameters:
  /// - [source]: The in-memory bytes or local file source; the complete file is not read into
  ///   memory.
  ///
  /// Returns the source byte count; throws a file access error if a local file does not exist.
  static int _sourceByteCount(
    StorageUploadSource source,
  ) => switch (source) {
    StorageDataUploadSource(:final data) => data.length,
    StorageFileUploadSource(:final fileURL) => File(
      fileURL.toFilePath(),
    ).lengthSync(),
  };

  /// Formats a byte count using readable size units.
  ///
  /// Parameters:
  /// - [byteCount]: The file size, in bytes.
  ///
  /// Returns the file size in B, KB, MB, or GB.
  static String _formatByteCount(
    int byteCount,
  ) {
    final count = byteCount.toDouble();

    if (byteCount < 1024) {
      return '$byteCount B';
    }

    if (byteCount < 1024 * 1024) {
      return '${(count / 1024).toStringAsFixed(1)} KB';
    }

    if (byteCount < 1024 * 1024 * 1024) {
      return '${(count / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return '${(count / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats the elapsed operation time in milliseconds or seconds.
  ///
  /// Parameters:
  /// - [startedAt]: The operation start time used to calculate elapsed time.
  ///
  /// Returns elapsed time using ms below one second, or s otherwise.
  static String _formatDuration(
    DateTime startedAt,
  ) {
    final milliseconds = DateTime.now().difference(startedAt).inMilliseconds;

    if (milliseconds < 1000) {
      return '$milliseconds ms';
    }

    return '${(milliseconds / 1000).toStringAsFixed(2)} s';
  }

  /// Logs an upload failure reason and elapsed time.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  /// - [startedAt]: The operation start time used to calculate elapsed time.
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

  /// Validates the download URL and writes the file to the local destination.
  ///
  /// Parameters:
  /// - [remoteURL]: The HTTP or HTTPS URL of the file to download.
  /// - [destinationURL]: The destination file URI.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the downloaded file's local URI and actual byte count.
  Future<DownloadedFile> _download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  }) async {
    _validateDownload(
      remoteURL,
      destinationURL,
    );

    return _storageManager.download(
      remoteURL: remoteURL,
      destinationURL: destinationURL,
      progress: progress,
    );
  }

  /// Obtains the region, object prefix, and temporary credentials for this upload.
  ///
  /// Returns the authorized object prefix and temporary storage configuration.
  Future<_TemporaryStorageConfiguration> _fetchStorageConfiguration() async {
    final payload = await _apiService.get<Map<String, dynamic>>(
      '/cos/sts',
      (
        json,
      ) => Map<String, dynamic>.from(json! as Map),
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
      throw const XmaxError(
        code: XmaxErrorCode.apiError,
        message: message,
      );
    }

    final accessKeyID = _requiredString(credentials['accessKeyId']);
    final secretAccessKey = _requiredString(credentials['secretAccessKey']);
    final sessionToken = _requiredString(credentials['sessionToken']);

    if (accessKeyID == null ||
        secretAccessKey == null ||
        sessionToken == null) {
      throw const XmaxError(
        code: XmaxErrorCode.apiError,
        message: message,
      );
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

  /// Requests an image safety check and returns the approved URL.
  ///
  /// Parameters:
  /// - [url]: The uploaded object's access URL.
  ///
  /// Returns the validated access URL or file URI.
  Future<Uri> _checkImage(
    Uri url,
  ) async {
    final payload = await _apiService.post<Map<String, dynamic>>(
      '/cos/image/check',
      (
        json,
      ) => Map<String, dynamic>.from(json! as Map),
      body: <String, Object?>{'url': url.toString()},
    );

    const message = 'Invalid image safety check payload';
    final safe = payload['safe'];

    if (safe is! bool) {
      throw const XmaxError(
        code: XmaxErrorCode.apiError,
        message: message,
      );
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
      throw const XmaxError(
        code: XmaxErrorCode.apiError,
        message: message,
      );
    }

    return checkedURL;
  }

  /// Validates the upload source, object information, and credentials for transfer.
  ///
  /// Parameters:
  /// - [source]: The in-memory bytes or local file to upload.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [mediaType]: The upload media type: image or video.
  ///
  /// Returns the sanitized filename; throws a configuration error for an invalid source or MIME
  /// type.
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

  /// Validates the remote download URL and local destination file URI.
  ///
  /// Parameters:
  /// - [remoteURL]: The HTTP or HTTPS URL of the file to download.
  /// - [destinationURL]: The destination file URI.
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

  /// Infers the MIME type from a supported image extension.
  ///
  /// Parameters:
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  ///
  /// Returns a supported image MIME type; throws a configuration error if it cannot be inferred.
  String _inferImageContentType(
    String fileName,
  ) => _inferContentType(
    fileName,
    const <String, String>{
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
  },
    'image',
  );

  /// Infers the MIME type from a supported video extension.
  ///
  /// Parameters:
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  ///
  /// Returns a supported video MIME type; throws a configuration error if it cannot be inferred.
  String _inferVideoContentType(
    String fileName,
  ) => _inferContentType(
    fileName,
    const <String, String>{
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
    'm4v': 'video/x-m4v',
    'webm': 'video/webm',
    'avi': 'video/x-msvideo',
    'mkv': 'video/x-matroska',
    '3gp': 'video/3gpp',
    '3g2': 'video/3gpp2',
    'ts': 'video/mp2t',
  },
    'video',
  );

  /// Infers a MIME type using the media category and extension map; throws if unsupported.
  ///
  /// Parameters:
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [types]: The mapping of file extensions to MIME types.
  /// - [mediaType]: The upload media type: image or video.
  ///
  /// Returns the MIME type mapped to the extension; throws a configuration error if unmapped.
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

  /// Sanitizes filenames to prevent local directory paths from entering object keys.
  ///
  /// Parameters:
  /// - [value]: The raw filename to strip of unsafe characters and leading or trailing punctuation.
  ///
  /// Returns a filename containing safe characters without surrounding punctuation; may be empty.
  String _sanitizeFileName(
    String value,
  ) {
    var result = value
        .trim()
        .replaceAll(
          RegExp(r'[^A-Za-z0-9._-]+'),
          '_',
        )
        .replaceAll(
          RegExp('_+'),
          '_',
        );

    result = result.replaceAll(
      RegExp(r'^[._-]+|[._-]+$'),
      '',
    );

    return result;
  }

  /// Builds an object key from the authorized prefix, millisecond timestamp, random ID, and safe
  /// filename.
  ///
  /// Parameters:
  /// - [prefix]: The object key prefix authorized for writing.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  ///
  /// Returns an object key containing the authorized prefix, millisecond timestamp, and random
  /// identifier.
  String _makeObjectKey(
    String prefix,
    String fileName,
  ) =>
      '$prefix${_dateGenerator().millisecondsSinceEpoch}_'
      '${_identifierGenerator().toLowerCase()}_$fileName';

  /// Extracts the filename from a local file URI.
  ///
  /// Parameters:
  /// - [uri]: The URI to validate or read.
  ///
  /// Returns the last URI path segment, or an empty string if no segment exists.
  static String _fileName(
    Uri uri,
  ) {
    if (uri.pathSegments.isEmpty) {
      return '';
    }

    return uri.pathSegments.last;
  }

  /// Trims a string response field; returns null for non-string values.
  ///
  /// Parameters:
  /// - [value]: The response field to trim; non-string values produce null.
  ///
  /// Returns the trimmed string, including an empty string, or null if the input is not a string.
  static String? _normalizedString(
    Object? value,
  ) => value is String ? value.trim() : null;

  /// Reads a nonempty string field.
  ///
  /// Parameters:
  /// - [value]: The response field; null is returned for non-string values or strings that are
  ///   blank after trimming.
  static String? _requiredString(
    Object? value,
  ) {
    final normalized = _normalizedString(value);

    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  /// Checks whether a URI is a valid HTTP or HTTPS endpoint.
  ///
  /// Parameters:
  /// - [uri]: The URI to validate or read.
  ///
  /// Returns whether the URI uses HTTP or HTTPS and has a nonempty host.
  static bool _isHTTPURL(
    Uri uri,
  ) =>
      (uri.isScheme('https') || uri.isScheme('http')) &&
      uri.host.trim().isNotEmpty;

  /// Generates a random UUID for a storage object key.
  static String _makeIdentifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      16,
      (
        _,
      ) => random.nextInt(256),
    );

    // Set RFC 4122 version and variant bits before encoding the UUID.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final value = bytes
        .map((
          byte,
        ) => byte.toRadixString(16).padLeft(
          2,
          '0',
        ))
        .join();

    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}

/// A server-issued object key prefix and temporary storage configuration.
final class _TemporaryStorageConfiguration {

  /// Stores temporary credentials and the authorized object key prefix.
  const _TemporaryStorageConfiguration({
    required this.prefix,
    required this.configuration,
  });

  /// The object key prefix authorized for writing.
  final String prefix;

  /// The region, bucket, and temporary credentials used for this upload.
  final StorageConfiguration configuration;
}

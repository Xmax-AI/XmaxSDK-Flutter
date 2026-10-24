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
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/fetch_credentials.dart';
import 'package:tencentcloud_cos_sdk_plugin_nobeacon/pigeon.dart';

import '../errors/ErrorMessageFormatter.dart';
import '../errors/ErrorNormalizer.dart';
import '../errors/XmaxError.dart';
import 'DownloadedFile.dart';
import 'StorageConfiguration.dart';
import 'StorageDownloadOperation.dart';
import 'StorageManaging.dart';
import 'StorageProgressListener.dart';
import 'StorageUploadSource.dart';
import 'StorageUploadOperation.dart';
import 'StoredFile.dart';
import 'XmaxStorageCancellationToken.dart';

/// The simple PUT threshold preventing automatic multipart uploads.
/// Combined with forced simple upload, ensures every file size uses a single PUT request.
const int _simpleUploadThreshold = 0x7FFFFFFFFFFFFFFF;

/// Provides Tencent COS uploads and HTTP file downloads.
final class StorageManager implements StorageManaging {

  /// Creates an object upload and file download transport.
  ///
  /// Parameters:
  /// - [httpClient]: The HTTP client for downloads; defaults to a dedicated client.
  StorageManager({
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? HttpClient();

  /// The HTTP download client; defaults to a dedicated client.
  final HttpClient _httpClient;

  /// The shared credential provider initialization task.
  static Future<void>? _credentialProviderInitialization;

  /// Uploads with a single PUT using request-scoped temporary credentials, without multipart
  /// fallback.
  ///
  /// See [StorageManaging.upload] for the usage contract.
  @override
  Future<StoredFile> upload({
    required StorageUploadSource source,
    required String objectKey,
    required String contentType,
    required StorageConfiguration configuration,
    StorageProgressListener? progress,
    XmaxStorageCancellationToken? cancellationToken,
  }) async {
    _validateUpload(
      source: source,
      objectKey: objectKey,
      contentType: contentType,
      configuration: configuration,
    );

    return StorageUploadOperation(
      progress: progress,
      cancellationToken: cancellationToken,
    ).value(
      transferManager: () => _transferManager(configuration),
      source: source,
      objectKey: objectKey,
      contentType: contentType,
      configuration: configuration,
      resolveURL: (
        candidate,
      ) => resolveObjectURL(
        candidate: candidate,
        configuration: configuration,
        objectKey: objectKey,
      ),
    );
  }

  /// Downloads to a staged file and replaces the destination only after the transfer succeeds.
  ///
  /// See [StorageManaging.download] for the usage contract.
  @override
  Future<DownloadedFile> download({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
    XmaxStorageCancellationToken? cancellationToken,
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

    try {
      return await StorageDownloadOperation(
        progress: progress,
        cancellationToken: cancellationToken,
      ).value(
        client: _httpClient,
        remoteURL: remoteURL,
        destinationURL: destinationURL,
      );
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
    }
  }

  /// Prepares a transfer manager for the current region and credential policy.
  ///
  /// Parameters:
  /// - [configuration]: The bucket, region, endpoint, and temporary credentials for this upload.
  ///
  /// Returns the COS transfer manager for the current region.
  Future<CosTransferManger> _transferManager(
    StorageConfiguration configuration,
  ) async {
    // Initialize native signing before registering transfers; concurrent uploads share initialization.
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

  /// Validates the upload source, object information, and credentials for transfer.
  ///
  /// Parameters:
  /// - [source]: The in-memory bytes or local file to upload.
  /// - [objectKey]: The full object key within the bucket, not a local file path.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [configuration]: The bucket, region, endpoint, and temporary credentials for this upload.
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

  /// Resolves a valid object URL, constructing one from storage settings and the object key if
  /// needed.
  ///
  /// Parameters:
  /// - [candidate]: The candidate URL returned by object storage.
  /// - [configuration]: The bucket, region, endpoint, and temporary credentials for this upload.
  /// - [objectKey]: The full object key within the bucket, not a local file path.
  ///
  /// Returns a validated object URL or one constructed from the object key.
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
      ...endpoint.pathSegments.where((
        segment,
      ) => segment.isNotEmpty),
      ...objectKey.split('/'),
    ];

    return endpoint.replace(pathSegments: segments);
  }

  /// Normalizes nonblank endpoints to HTTP or HTTPS URIs; throws an upload error for invalid
  /// endpoints.
  ///
  /// Parameters:
  /// - [value]: The object storage endpoint text; the https prefix may be omitted.
  ///
  /// Returns a normalized HTTP or HTTPS URI, or null for blank input; throws on invalid endpoints.
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

  /// Checks whether a URI is a valid HTTP or HTTPS endpoint.
  ///
  /// Parameters:
  /// - [uri]: The URI to validate or read.
  ///
  /// Returns whether the URI uses HTTP or HTTPS and has a nonempty host.
  static bool _isHTTPURL(
    Uri uri,
  ) => (uri.isScheme('http') || uri.isScheme('https')) && uri.host.isNotEmpty;
}

/// Disables global credential fallback so uploads use only request-scoped temporary credentials.
final class _RequestOnlyCredentials implements IFetchCredentials {

  /// Rejects global credential fallback; uploads must explicitly supply request-scoped credentials.
  ///
  /// The future always fails with an upload error; no global fallback credentials are returned.
  @override
  Future<SessionQCloudCredentials> fetchSessionCredentials() async {
    throw const XmaxError(
      code: XmaxErrorCode.uploadError,
      message: 'Storage request is missing its temporary credential',
    );
  }
}

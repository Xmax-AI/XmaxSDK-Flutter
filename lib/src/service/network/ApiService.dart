//
//  ApiService.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../foundation/errors/ErrorMessageFormatter.dart';
import '../../foundation/errors/ErrorNormalizer.dart';
import '../../foundation/errors/XmaxError.dart';
import '../../foundation/runtime/RuntimeInfo.dart';
import '../../foundation/tasks/OperationCancellation.dart';
import '../../core/XmaxEnvironment.dart';
import 'ApiLogger.dart';
import 'ApiServicing.dart';

/// The status code and body of an HTTP response.
final class ApiTransportResponse {

  /// Creates an HTTP response result.
  const ApiTransportResponse({
    required this.statusCode,
    required this.body,
  });

  /// The HTTP response status.
  final int statusCode;

  /// The raw HTTP response body bytes.
  final List<int> body;
}

/// A replaceable HTTP request transport interface.
abstract interface class ApiTransport {

  /// Executes an HTTP request and collects its status code and complete response body.
  ///
  /// Parameters:
  /// - [method]: The request's HTTP method.
  /// - [url]: The complete request URL.
  /// - [headers]: The HTTP request headers.
  /// - [body]: The encoded request body bytes; null sends no body.
  /// - [timeout]: The inactivity limit for connection, response headers, and each response body read.
  /// - [cancellation]: Completes to abort this request and release its response.
  ///
  /// Returns the HTTP status code and complete response body.
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
    Future<void>? cancellation,
  });
}

/// Executes HTTP requests with timeouts through HttpClient.
final class HttpApiTransport implements ApiTransport {

  /// Creates an HTTP transport.
  ///
  /// Parameters:
  /// - [client]: The underlying client; defaults to a dedicated HttpClient.
  HttpApiTransport({
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  /// The HTTP client used to send requests and read responses.
  final HttpClient _client;

  /// Executes an HTTP request and collects its status code and complete response body.
  ///
  /// See [ApiTransport.send] for the usage contract.
  @override
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
    Future<void>? cancellation,
  }) async {
    final operation = OperationCancellation(cancellation: cancellation);
    HttpClientRequest? request;
    HttpClientResponse? response;
    StreamIterator<List<int>>? chunks;
    var subscribed = false;
    var completed = false;

    operation.observe(() {
      try {
        request?.abort(OperationCancellation.error);
      } catch (_) {}
    });

    try {
      // Allow a completed parent signal to cancel before opening a connection.
      await operation.wait(Future<void>.value());
      final activeRequest = await operation.wait(
        _client.openUrl(
          method.value,
          url,
        ).then((
          opened,
        ) {
          opened.done.ignore();
          if (operation.isCancelled || operation.isFinished) {
            opened.abort(OperationCancellation.error);
          } else {
            request = opened;
          }
          return opened;
        }),
        timeout: timeout,
      );

      headers.forEach(activeRequest.headers.set);
      if (body != null) {
        activeRequest.add(body);
      }

      final activeResponse = await operation.wait(
        activeRequest.close().then((
          received,
        ) async {
          if (operation.isCancelled || operation.isFinished) {
            await received.listen(null).cancel();
            operation.check();
            throw OperationCancellation.error;
          }

          response = received;
          return received;
        }),
        timeout: timeout,
      );
      chunks = StreamIterator<List<int>>(activeResponse);
      final bytes = <int>[];

      subscribed = true;
      while (await operation.wait(
        chunks.moveNext(),
        timeout: timeout,
      )) {
        bytes.addAll(chunks.current);
      }

      operation.check();
      completed = true;
      return ApiTransportResponse(
        statusCode: activeResponse.statusCode,
        body: bytes,
      );
    } finally {
      operation.finish();
      if (!completed) {
        try {
          request?.abort();
        } catch (_) {}
      }

      try {
        if (subscribed) {
          await chunks?.cancel();
        } else {
          await response?.listen(null).cancel();
        }
      } catch (_) {}
    }
  }
}

/// Sends Xmax API requests and handles responses, logging, and errors.
final class ApiService implements ApiServicing {

  /// Creates an API service.
  ///
  /// Parameters:
  /// - [apiKey]: The API key used to authenticate requests.
  /// - [environment]: The environment selecting the default service endpoint.
  /// - [baseURL]: The API base URL overriding the environment default.
  /// - [timeout]: The request timeout; defaults to 15 seconds.
  /// - [transport]: The HTTP transport; defaults to [HttpApiTransport].
  ApiService({
    required String apiKey,
    XmaxEnvironment environment = XmaxEnvironment.china,
    Uri? baseURL,
    Duration timeout = defaultTimeoutInterval,
    ApiTransport? transport,
  }) : _apiKey = apiKey.trim(),
       _baseURL = baseURL ?? _baseURLFor(environment),
       _timeout = timeout,
       _transport = transport ?? HttpApiTransport();

  /// The default API endpoint when no environment or endpoint is specified.
  static final Uri defaultBaseURL = _baseURLFor(XmaxEnvironment.china);

  /// The default API request timeout.
  static const Duration defaultTimeoutInterval = Duration(seconds: 15);

  /// Resolves the API base URL for the specified storage environment.
  ///
  /// Parameters:
  /// - [environment]: The service environment and log detail language: Chinese for China, English
  ///   for global.
  ///
  /// Returns the API base URL for the specified storage environment.
  static Uri _baseURLFor(
    XmaxEnvironment environment,
  ) => switch (environment) {
    XmaxEnvironment.china => Uri.parse(
      'https://cloud.xmax.22duck.cn/open/api/v1',
    ),
    XmaxEnvironment.global => Uri.parse('https://api.xmax.cloud/open/api/v1'),
  };

  /// The API key used to access Xmax services. Do not include it in public source or logs.
  final String _apiKey;

  /// The API base URL resolved from an override or environment at creation.
  final Uri _baseURL;

  /// The request timeout limit.
  final Duration _timeout;

  /// The replaceable HTTP request transport.
  final ApiTransport _transport;

  /// Executes an authenticated request with a timeout and decodes its response into the target
  /// type.
  ///
  /// See [ApiServicing.request] for the usage contract.
  @override
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(
      Object? json,
    )
    decode,
    Future<void>? cancellation,
  }) async {
    final operation = OperationCancellation(cancellation: cancellation);

    try {
      return await _request(
        method,
        path: path,
        body: body,
        decode: decode,
        operation: operation,
      );
    } finally {
      operation.finish();
    }
  }

  /// Executes one request while retaining cancellation ownership through response decoding.
  ///
  /// Parameters:
  /// - [method]: The HTTP method.
  /// - [path]: The API path relative to this service.
  /// - [body]: The JSON request payload.
  /// - [decode]: The business response decoder.
  /// - [operation]: The scoped cancellation owner.
  ///
  /// Returns the decoded business response.
  Future<T> _request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(
      Object? json,
    ) decode,
    required OperationCancellation operation,
  }) async {
    _validateConfiguration();

    final url = _makeURL(path);
    final runtime = await operation.wait(RuntimeInfo.resolve());
    final encodedBody = body == null ? null : utf8.encode(jsonEncode(body));
    final stopwatch = Stopwatch()..start();

    // Convert transport exceptions to network errors; response decoding handles server-reported errors.
    final ApiTransportResponse response;

    try {
      response = await _transport.send(
        method: method,
        url: url,
        headers: <String, String>{
          HttpHeaders.acceptHeader: ContentType.json.mimeType,
          HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
          'X-Api-Key': _apiKey,
          'X-Platform': runtime.platform,
          'X-OS-Version': runtime.osVersion,
          'X-SDK-Version': runtime.sdkVersion,
          'X-Device-Model': runtime.deviceModel,
        },
        body: encodedBody,
        timeout: _timeout,
        cancellation: operation.signal,
      );
    } on XmaxError catch (error) {
      ApiLogger.logFailure(
        method: method,
        path: path,
        error: error,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    } catch (error) {
      ApiLogger.logFailure(
        method: method,
        path: path,
        error: error,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      if (ErrorNormalizer.isCancellation(error)) {
        throw const XmaxError(
          code: XmaxErrorCode.cancelled,
          message: 'API request was cancelled',
        );
      }

      throw XmaxError(
        code: XmaxErrorCode.networkError,
        message: 'HTTP request failed: ${ErrorMessageFormatter.format(error)}',
      );
    }

    try {
      operation.check();
      final value = _parseResponse(
        response,
        decode,
      );

      operation.check();
      ApiLogger.logResponse(
        method: method,
        path: path,
        statusCode: response.statusCode,
        bodyByteCount: response.body.length,
        durationMs: stopwatch.elapsedMilliseconds,
        successful: true,
      );

      return value;
    } on XmaxError {
      ApiLogger.logResponse(
        method: method,
        path: path,
        statusCode: response.statusCode,
        bodyByteCount: response.body.length,
        durationMs: stopwatch.elapsedMilliseconds,
        successful: false,
      );
      rethrow;
    } catch (error) {
      ApiLogger.logResponse(
        method: method,
        path: path,
        statusCode: response.statusCode,
        bodyByteCount: response.body.length,
        durationMs: stopwatch.elapsedMilliseconds,
        successful: false,
      );
      throw XmaxError(
        code: XmaxErrorCode.apiError,
        message: ErrorMessageFormatter.format(error),
        httpStatus: response.statusCode,
      );
    }
  }

  /// Validates the API key and service endpoint before a request.
  void _validateConfiguration() {
    if (_apiKey.isEmpty) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidAPIKey,
        message: 'API key cannot be empty',
      );
    }

    if (_baseURL.scheme.toLowerCase() != 'https' ||
        _baseURL.host.isEmpty ||
        _timeout <= Duration.zero) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'API service configuration is invalid',
      );
    }
  }

  /// Combines the base URL and relative API path into a request URL.
  ///
  /// Parameters:
  /// - [path]: The relative API path.
  ///
  /// Returns the complete URL combining the API base URL and request path.
  Uri _makeURL(
    String path,
  ) {
    final normalizedPath = path.trim();

    if (normalizedPath.isEmpty ||
        normalizedPath.contains('://') ||
        normalizedPath.startsWith('//')) {
      throw const XmaxError(
        code: XmaxErrorCode.invalidConfiguration,
        message: 'API request path is invalid',
      );
    }

    final basePath = _baseURL.path.endsWith('/')
        ? _baseURL.path.substring(
          0,
          _baseURL.path.length - 1,
        )
        : _baseURL.path;
    final relativePath = normalizedPath.startsWith('/')
        ? normalizedPath
        : '/$normalizedPath';

    return _baseURL.replace(path: '$basePath$relativePath');
  }

  /// Validates HTTP and application response status, then decodes a successful response.
  ///
  /// Parameters:
  /// - [response]: The HTTP response to decode.
  /// - [decode]: The function converting the application response into the target type.
  ///
  /// Returns the application response converted by [decode].
  T _parseResponse<T>(
    ApiTransportResponse response,
    T Function(
      Object? json,
    )
    decode,
  ) {
    final Object? json;

    try {
      json = jsonDecode(utf8.decode(response.body));
    } catch (_) {
      throw XmaxError(
        code: XmaxErrorCode.apiError,
        message: 'Server returned invalid JSON',
        httpStatus: response.statusCode,
      );
    }

    if (json is! Map<String, dynamic>) {
      throw XmaxError(
        code: XmaxErrorCode.apiError,
        message: 'Server returned invalid JSON',
        httpStatus: response.statusCode,
      );
    }

    final success = json['success'];

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        success != true) {
      final rawMessage = json['message'];
      final message = rawMessage is String && rawMessage.trim().isNotEmpty
          ? rawMessage.trim()
          : 'Xmax API request failed';

      throw XmaxError(
        code: XmaxErrorCode.apiError,
        message: message,
        apiCode: json['code'] is int ? json['code'] as int : null,
        httpStatus: response.statusCode,
      );
    }

    if (!json.containsKey('data') || json['data'] == null) {
      throw XmaxError(
        code: XmaxErrorCode.apiError,
        message: 'Server returned invalid response data',
        httpStatus: response.statusCode,
      );
    }

    try {
      return decode(json['data']);
    } catch (_) {
      throw XmaxError(
        code: XmaxErrorCode.apiError,
        message: 'Server returned invalid response data',
        httpStatus: response.statusCode,
      );
    }
  }
}

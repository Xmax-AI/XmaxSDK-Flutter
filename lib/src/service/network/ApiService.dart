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
import '../../core/XmaxEnvironment.dart';
import 'ApiLogger.dart';
import 'ApiServicing.dart';

/// HTTP 传输的状态码和响应体。
final class ApiTransportResponse {

  /// 创建 HTTP 响应结果。
  const ApiTransportResponse({
    required this.statusCode,
    required this.body,
  });

  /// HTTP 响应状态码。
  final int statusCode;

  /// HTTP 响应正文的原始字节。
  final List<int> body;
}

/// 可替换的 HTTP 请求传输接口。
abstract interface class ApiTransport {

  /// 执行一次 HTTP 请求，并收集状态码和完整响应正文。
  ///
  /// - [method]：请求使用的 HTTP 方法。
  /// - [url]：完整请求地址。
  /// - [headers]：HTTP 请求头。
  /// - [body]：请求正文的编码字节；null 表示不发送正文。
  /// - [timeout]：建立请求和等待响应头各自的超时时限；默认实现不限制响应体读取时长。
  ///
  /// 返回 HTTP 状态码及完整响应正文。
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
  });
}

/// 通过 HttpClient 执行带超时限制的 HTTP 请求。
final class HttpApiTransport implements ApiTransport {

  /// 创建 HTTP 传输入口。
  ///
  /// - [client]：底层客户端；默认创建独立的 HttpClient。
  HttpApiTransport({
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  /// 发送请求和读取响应使用的 HTTP 客户端。
  final HttpClient _client;

  /// 执行一次 HTTP 请求，并收集状态码和完整响应正文。
  ///
  /// 详细说明见 [ApiTransport.send]。
  @override
  Future<ApiTransportResponse> send({
    required ApiMethod method,
    required Uri url,
    required Map<String, String> headers,
    required List<int>? body,
    required Duration timeout,
  }) async {
    final request = await _client.openUrl(method.value, url).timeout(timeout);

    headers.forEach(request.headers.set);

    if (body != null) {
      request.add(body);
    }

    final response = await request.close().timeout(timeout);
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );

    return ApiTransportResponse(statusCode: response.statusCode, body: bytes);
  }
}

/// 负责发送 Xmax API 请求并统一处理响应、日志和错误。
final class ApiService implements ApiServicing {

  /// 创建 API 服务，规范化密钥并解析请求地址。
  ///
  /// - [apiKey]：访问密钥，创建时去除首尾空白。
  /// - [environment]：用于选择默认服务地址的环境。
  /// - [baseURL]：覆盖环境默认地址的 API 根地址。
  /// - [timeout]：请求等待时限，默认 15 秒。
  /// - [transport]：HTTP 传输实现；默认创建 [HttpApiTransport]。
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

  /// 未显式指定环境或路由时使用的默认 API 地址。
  static final Uri defaultBaseURL = _baseURLFor(XmaxEnvironment.china);

  /// API 请求的默认超时时限。
  static const Duration defaultTimeoutInterval = Duration(seconds: 15);

  /// 解析指定存储环境对应的 API 基础地址。
  ///
  /// - [environment]：存储服务区域及 SDK 日志语言配置。
  ///
  /// 返回指定存储环境的基础 API 地址。
  static Uri _baseURLFor(
    XmaxEnvironment environment,
  ) => switch (environment) {
    XmaxEnvironment.china => Uri.parse(
      'https://cloud.xmax.22duck.cn/open/api/v1',
    ),
    XmaxEnvironment.global => Uri.parse('https://api.xmax.cloud/open/api/v1'),
  };

  /// 开放平台签发的 API key，不应写入公开仓库或日志。
  final String _apiKey;

  /// 创建时根据覆盖地址或环境解析的 API 根地址。
  final Uri _baseURL;

  /// 请求允许使用的最长等待时限。
  final Duration _timeout;

  /// 可替换的 HTTP 请求传输实现。
  final ApiTransport _transport;

  /// 执行带鉴权和超时限制的请求，并将业务响应解码为目标类型。
  ///
  /// 详细说明见 [ApiServicing.request]。
  @override
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(
      Object? json,
    )
    decode,
  }) async {
    _validateConfiguration();

    final url = _makeURL(path);
    final runtime = await RuntimeInfo.resolve();
    final encodedBody = body == null ? null : utf8.encode(jsonEncode(body));
    final stopwatch = Stopwatch()..start();

    // 传输异常转换为网络错误；服务端响应中的错误由后续解析处理。
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
      final value = _parseResponse(response, decode);

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

  /// 校验 API key 和服务地址是否满足请求要求。
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

  /// 将基础地址与相对 API 路径合并为请求 URL。
  ///
  /// - [path]：API 相对路径。
  ///
  /// 返回基础 API 地址与业务路径合并后的完整 URL。
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
        ? _baseURL.path.substring(0, _baseURL.path.length - 1)
        : _baseURL.path;
    final relativePath = normalizedPath.startsWith('/')
        ? normalizedPath
        : '/$normalizedPath';

    return _baseURL.replace(path: '$basePath$relativePath');
  }

  /// 校验 HTTP 和业务响应状态，并解码成功响应。
  ///
  /// - [response]：待解析的 HTTP 响应。
  /// - [decode]：将业务响应转换为目标类型的函数。
  ///
  /// 返回由 [decode] 转换后的业务响应。
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

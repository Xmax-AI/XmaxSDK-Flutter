//
//  ApiServicing.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// SDK 请求使用的 HTTP 方法。
enum ApiMethod {

  /// HTTP GET 请求。
  get('GET'),

  /// HTTP POST 请求。
  post('POST'),

  /// HTTP PUT 请求。
  put('PUT'),

  /// HTTP DELETE 请求。
  delete('DELETE');

  /// 定义 HTTP 方法名称。
  const ApiMethod(
    this.value,
  );

  /// 序列化时使用的值。
  final String value;
}

/// Xmax API 请求与业务响应解码的内部接口。
abstract interface class ApiServicing {

  /// 执行带鉴权和超时限制的请求，并将业务响应解码为目标类型。
  ///
  /// - [method]：请求使用的 HTTP 方法。
  /// - [path]：API 相对路径。
  /// - [body]：可编码为 JSON 的请求正文；null 表示不发送正文。
  /// - [decode]：将业务响应转换为目标类型的函数。
  ///
  /// 返回由 [decode] 转换后的业务响应。
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(
      Object? json,
    )
    decode,
  });
}

/// 提供 GET、POST、PUT 和 DELETE 请求的便捷入口。
extension ApiServicingConvenience on ApiServicing {

  /// 执行 GET 请求并解码业务结果。
  ///
  /// - [path]：API 相对路径。
  /// - [decode]：将业务响应转换为目标类型的函数。
  ///
  /// 返回由 [decode] 转换后的业务响应。
  Future<T> get<T>(
    String path,
    T Function(
      Object? json,
    )
    decode,
  ) => request(ApiMethod.get, path: path, decode: decode);

  /// 执行 POST 请求并解码业务结果。
  ///
  /// - [path]：API 相对路径。
  /// - [decode]：将业务响应转换为目标类型的函数。
  /// - [body]：可编码为 JSON 的请求正文；null 表示不发送正文。
  ///
  /// 返回由 [decode] 转换后的业务响应。
  Future<T> post<T>(
    String path,
    T Function(
      Object? json,
    )
    decode, {
    Object? body,
  }) => request(ApiMethod.post, path: path, body: body, decode: decode);

  /// 执行 PUT 请求并解码业务结果。
  ///
  /// - [path]：API 相对路径。
  /// - [decode]：将业务响应转换为目标类型的函数。
  /// - [body]：可编码为 JSON 的请求正文；null 表示不发送正文。
  ///
  /// 返回由 [decode] 转换后的业务响应。
  Future<T> put<T>(
    String path,
    T Function(
      Object? json,
    )
    decode, {
    Object? body,
  }) => request(ApiMethod.put, path: path, body: body, decode: decode);

  /// 执行 DELETE 请求并解码业务结果。
  ///
  /// - [path]：API 相对路径。
  /// - [decode]：将业务响应转换为目标类型的函数。
  ///
  /// 返回由 [decode] 转换后的业务响应。
  Future<T> delete<T>(
    String path,
    T Function(
      Object? json,
    )
    decode,
  ) => request(ApiMethod.delete, path: path, decode: decode);
}

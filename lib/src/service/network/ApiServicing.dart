//
//  ApiServicing.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// An HTTP method used by SDK requests.
enum ApiMethod {

  /// An HTTP GET request.
  get('GET'),

  /// An HTTP POST request.
  post('POST'),

  /// An HTTP PUT request.
  put('PUT'),

  /// An HTTP DELETE request.
  delete('DELETE');

  /// Defines an HTTP method name.
  const ApiMethod(
    this.value,
  );

  /// The serialized value.
  final String value;
}

/// An internal interface for Xmax API requests and response decoding.
abstract interface class ApiServicing {

  /// Executes an authenticated request with a timeout and decodes its response into the target
  /// type.
  ///
  /// Parameters:
  /// - [method]: The request's HTTP method.
  /// - [path]: The relative API path.
  /// - [body]: The JSON-encodable request body; null sends no body.
  /// - [decode]: The function converting the application response into the target type.
  /// - [cancellation]: Completes to abort this request without interrupting other requests.
  ///
  /// Returns the application response converted by [decode].
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(
      Object? json,
    )
    decode,
    Future<void>? cancellation,
  });
}

/// Provides convenience methods for GET, POST, PUT, and DELETE requests.
extension ApiServicingConvenience on ApiServicing {

  /// Executes a GET request and decodes the result.
  ///
  /// Parameters:
  /// - [path]: The relative API path.
  /// - [decode]: The function converting the application response into the target type.
  /// - [cancellation]: The cancellation signal for this request.
  ///
  /// Returns the application response converted by [decode].
  Future<T> get<T>(
    String path,
    T Function(
      Object? json,
    )
    decode, {
    Future<void>? cancellation,
  }) => request(
    ApiMethod.get,
    path: path,
    decode: decode,
    cancellation: cancellation,
  );

  /// Executes a POST request and decodes the result.
  ///
  /// Parameters:
  /// - [path]: The relative API path.
  /// - [decode]: The function converting the application response into the target type.
  /// - [body]: The JSON-encodable request body; null sends no body.
  /// - [cancellation]: The cancellation signal for this request.
  ///
  /// Returns the application response converted by [decode].
  Future<T> post<T>(
    String path,
    T Function(
      Object? json,
    )
    decode, {
    Object? body,
    Future<void>? cancellation,
  }) => request(
    ApiMethod.post,
    path: path,
    body: body,
    decode: decode,
    cancellation: cancellation,
  );

  /// Executes a PUT request and decodes the result.
  ///
  /// Parameters:
  /// - [path]: The relative API path.
  /// - [decode]: The function converting the application response into the target type.
  /// - [body]: The JSON-encodable request body; null sends no body.
  /// - [cancellation]: The cancellation signal for this request.
  ///
  /// Returns the application response converted by [decode].
  Future<T> put<T>(
    String path,
    T Function(
      Object? json,
    )
    decode, {
    Object? body,
    Future<void>? cancellation,
  }) => request(
    ApiMethod.put,
    path: path,
    body: body,
    decode: decode,
    cancellation: cancellation,
  );

  /// Executes a DELETE request and decodes the result.
  ///
  /// Parameters:
  /// - [path]: The relative API path.
  /// - [decode]: The function converting the application response into the target type.
  /// - [cancellation]: The cancellation signal for this request.
  ///
  /// Returns the application response converted by [decode].
  Future<T> delete<T>(
    String path,
    T Function(
      Object? json,
    )
    decode, {
    Future<void>? cancellation,
  }) => request(
    ApiMethod.delete,
    path: path,
    decode: decode,
    cancellation: cancellation,
  );
}

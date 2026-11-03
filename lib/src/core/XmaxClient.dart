//
//  XmaxClient.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../foundation/errors/XmaxError.dart';
import '../foundation/logging/XmaxLogger.dart';
import '../foundation/storage/StorageManager.dart';
import '../service/media/MediaService.dart';
import '../service/media/MediaServicing.dart';
import '../service/network/ApiService.dart';
import '../service/network/ApiServicing.dart';
import '../service/realtime/RealtimeModel.dart';
import '../service/storage/StorageService.dart';
import 'XmaxConfiguration.dart';
import 'account/XmaxCreditBalance.dart';
import 'realtime/RealtimeConfiguration.dart';
import 'realtime/XmaxRealtimeManager.dart';
import 'realtime/XmaxRealtimeManaging.dart';
import 'storage/XmaxStorageManager.dart';
import 'storage/XmaxStorageManaging.dart';

/// A client for account queries, realtime generation, storage, and media services.
final class XmaxClient {

  /// Creates a client with the specified configuration.
  ///
  /// API credentials are validated when sending requests, not during client creation.
  ///
  /// Parameters:
  /// - [configuration]: The API credentials, service environment, and logging options.
  XmaxClient({
    required this.configuration,
  }) : _apiService = ApiService(
    apiKey: configuration.apiKey,
    environment: configuration.environment,
  ) {
    XmaxLogger.configure(
      options: configuration.loggerOptions,
      environment: configuration.environment,
    );
  }

  /// Creates a client with an injected API service.
  ///
  /// Parameters:
  /// - [configuration]: The API credentials, service environment, and logging options.
  /// - [apiService]: The service used for account, realtime session, and storage requests.
  XmaxClient.internal({
    required this.configuration,
    required ApiServicing apiService,
  }) : _apiService = apiService {
    _realtimeApiOverride = apiService;
    XmaxLogger.configure(
      options: configuration.loggerOptions,
      environment: configuration.environment,
    );
  }

  /// The configuration used by this client.
  final XmaxConfiguration configuration;

  /// The service for account queries, storage credentials, and media safety checks.
  final ApiServicing _apiService;

  /// The injected realtime service, or null to use the client's environment routing.
  ApiServicing? _realtimeApiOverride;

  /// Fetches remaining credits for the account owning this client's API key.
  ///
  /// Each call reads the current server balance using the configured general API environment.
  /// Fractional credits are preserved. This query does not create a realtime session.
  ///
  /// Returns the account's remaining credits.
  ///
  /// The returned future completes with an [XmaxError] if credentials, transport, or the response
  /// are invalid.
  Future<XmaxCreditBalance> getCreditBalance() async {
    configuration.validate();

    return _apiService.get(
      '/balance',
      (
        json,
      ) {
        final value = json is Map<String, dynamic> ? json['currentBalance'] : null;
        final currentBalance = value is num ? value.toDouble() : null;

        if (currentBalance == null ||
            !currentBalance.isFinite || currentBalance < 0) {
          throw const XmaxError(
            code: XmaxErrorCode.apiError,
            message: 'Credit balance must be a finite, nonnegative number',
          );
        }

        return createXmaxCreditBalance(currentBalance: currentBalance);
      },
    );
  }

  /// Creates a manager for local media inputs and realtime generation.
  ///
  /// Managers maintain independent state but must take turns owning the shared RTC engine.
  ///
  /// Parameters:
  /// - [options]: The realtime model configuration.
  XmaxRealtimeManaging createRealtimeManager({
    required RealtimeConfiguration options,
  }) => XmaxRealtimeManager(
    options: options,
    apiService:
        _realtimeApiOverride ??
        ApiService(
          apiKey: configuration.apiKey,
          baseURL: configuration.environment.realtimeApiBaseURL,
        ),
  );

  /// Creates a manager for uploading and downloading media files. Throws if the API key is empty.
  ///
  /// Returns a storage manager independent of the realtime connection.
  XmaxStorageManaging createStorageManager() {
    configuration.validate();

    return XmaxStorageManager(
      storageService: StorageService(
        apiService: _apiService,
        storageManager: StorageManager(),
      ),
    );
  }

  /// Creates a service for media sizing.
  ///
  /// Parameters:
  /// - [model]: The model whose sizing rules the service uses; defaults to X2.1.
  ///
  /// Returns the media sizing service for the model.
  MediaServicing createMediaService({
    RealtimeModel model = RealtimeModel.x2_1,
  }) => MediaService(model: model);
}

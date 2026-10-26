//
//  XmaxClient.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../foundation/logging/XmaxLogger.dart';
import '../foundation/storage/StorageManager.dart';
import '../service/media/MediaService.dart';
import '../service/media/MediaServicing.dart';
import '../service/network/ApiService.dart';
import '../service/network/ApiServicing.dart';
import '../service/realtime/RealtimeModel.dart';
import '../service/storage/StorageService.dart';
import 'XmaxConfiguration.dart';
import 'realtime/RealtimeConfiguration.dart';
import 'realtime/XmaxRealtimeManager.dart';
import 'realtime/XmaxRealtimeManaging.dart';
import 'storage/XmaxStorageManager.dart';
import 'storage/XmaxStorageManaging.dart';

/// A client that provides access to Xmax realtime generation, storage, and media services.
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
  /// - [apiService]: The service used for realtime session and storage requests.
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

  /// The service used for API requests.
  final ApiServicing _apiService;

  /// The injected realtime service, or null to use the client's environment routing.
  ApiServicing? _realtimeApiOverride;

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

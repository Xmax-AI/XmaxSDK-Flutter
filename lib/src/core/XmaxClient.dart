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
import '../service/storage/StorageService.dart';
import 'realtime/RealtimeConfiguration.dart';
import 'realtime/RealtimeModel.dart';
import 'realtime/XmaxRealtimeManager.dart';
import 'realtime/XmaxRealtimeManaging.dart';
import 'storage/XmaxStorageManager.dart';
import 'storage/XmaxStorageManaging.dart';
import 'XmaxConfiguration.dart';

/// SDK 统一入口，用于创建实时生成、对象存储和媒体尺寸服务。
final class XmaxClient {

  /// 创建客户端，并配置进程内共享的 SDK 日志选项。
  ///
  /// - [configuration]：访问凭证、服务环境和日志配置。
  ///
  /// 网络服务在创建时初始化；访问凭证在执行服务请求前校验。
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

  /// 使用指定的网络服务创建客户端，并配置共享日志选项。
  ///
  /// - [configuration]：访问凭证、服务环境和日志配置。
  /// - [apiService]：供实时会话及存储服务使用的网络服务。
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

  /// 创建客户端时传入的访问凭证、环境和日志配置。
  final XmaxConfiguration configuration;

  /// 云端 API 请求服务。
  final ApiServicing _apiService;

  /// 显式注入的实时请求服务；为空时按客户端环境选择地址。
  ApiServicing? _realtimeApiOverride;

  /// 创建使用指定模型的实时管理器。
  ///
  /// - [options]：实时模型配置。
  ///
  /// 各管理器分别管理自己的状态，但按顺序独占同一个 RTC 引擎。
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

  /// 创建独立对象存储管理器；API key 为空时抛出错误。
  ///
  /// 返回独立于实时连接的对象存储管理器。
  XmaxStorageManaging createStorageManager() {
    configuration.validate();

    return XmaxStorageManager(
      storageService: StorageService(
        apiService: _apiService,
        storageManager: StorageManager(),
      ),
    );
  }

  /// 创建用于解析指定模型媒体尺寸的服务。
  ///
  /// - [model]：媒体规格约束所属模型，默认使用 X2.1。
  ///
  /// 返回指定模型的媒体尺寸解析服务。
  MediaServicing createMediaService({
    RealtimeModel model = RealtimeModel.x2_1,
  }) => MediaService(model: model);
}

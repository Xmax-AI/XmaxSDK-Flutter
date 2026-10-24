//
//  XmaxSDK.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The Flutter entry point for XmaxSDK.
library;

export 'src/core/realtime/RealtimeConfiguration.dart';
export 'src/core/realtime/RealtimeModel.dart';
export 'src/core/realtime/RealtimeCameraPreset.dart';
export 'src/core/realtime/RealtimeQualityLevel.dart';
export 'src/core/realtime/RealtimeMediaSource.dart';
export 'src/foundation/rtc/VideoStatistics.dart';
export 'src/core/realtime/XmaxRealtimeManaging.dart';
export 'src/core/storage/XmaxDownloadedFile.dart' show XmaxDownloadedFile;
export 'src/core/storage/XmaxStorageManaging.dart';
export 'src/core/storage/XmaxStorageProgressHandler.dart';
export 'src/core/storage/XmaxUploadedFile.dart' show XmaxUploadedFile;
export 'src/core/XmaxConfiguration.dart';
export 'src/core/XmaxClient.dart';
export 'src/core/XmaxEnvironment.dart';
export 'src/foundation/errors/XmaxError.dart';
export 'src/foundation/logging/XmaxLoggerOption.dart';
export 'src/foundation/media/camera/CameraPosition.dart';
export 'src/foundation/media/video/VideoContentMode.dart';
export 'src/service/media/MediaServicing.dart';
export 'src/service/realtime/RealtimeContext.dart';
export 'src/service/realtime/RealtimeMediaStream.dart' show RealtimeMediaStream;
export 'src/service/realtime/RealtimeNetworkQuality.dart';
export 'src/service/realtime/RealtimePerformanceAlarm.dart';
export 'src/service/realtime/RealtimeState.dart';
export 'src/service/realtime/RealtimeVideoFormat.dart';
export 'src/service/realtime/RealtimeVideoTrack.dart' show RealtimeVideoTrack;
export 'src/render/trajectory/DefaultTrajectoryEffectRenderer.dart';
export 'src/render/trajectory/TrajectoryEffectRendering.dart'
    show TrajectoryEffectRendering, TrajectoryID, TrajectoryPoint;
export 'src/render/video/XmaxRealtimeVideoView.dart';
export 'src/render/video/XmaxVideoView.dart';
export 'src/XmaxSDKInfo.dart';

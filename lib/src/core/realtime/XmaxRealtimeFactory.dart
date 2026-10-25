//
//  XmaxRealtimeFactory.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/rtc/RtcManager.dart';
import '../../media/MediaController.dart';
import '../../media/MediaControlling.dart';
import '../../media/camera/CameraController.dart';
import '../../media/external/ExternalVideoController.dart';
import '../../render/RenderController.dart';
import '../../render/RenderControlling.dart';
import '../../service/media/MediaService.dart';
import '../../service/media/MediaServicing.dart';
import '../../service/network/ApiServicing.dart';
import '../../service/realtime/RealtimeSessionService.dart';
import '../../service/realtime/RealtimeTiming.dart';
import '../../stream/StreamController.dart';
import '../../stream/StreamControlling.dart';
import 'RealtimeConfiguration.dart';
import 'XmaxRealtimeConnectionManager.dart';
import 'XmaxRealtimeErrorManager.dart';
import 'XmaxRealtimeGenerationManager.dart';
import 'XmaxRealtimeLifecycleManager.dart';

/// The shared components used by the public facade and its lifecycle manager.
final class XmaxRealtimeComponents {

  /// Creates a realtime component bundle.
  const XmaxRealtimeComponents({
    required this.lifecycleManager,
    required this.connectionManager,
    required this.generationManager,
    required this.errorManager,
    required this.mediaController,
    required this.streamController,
    required this.mediaService,
    required this.renderController,
    required this.timing,
  });

  /// The manager coordinating operation validity, state, and resource cleanup.
  final XmaxRealtimeLifecycleManager lifecycleManager;

  /// The manager owning the server session and RTC connection.
  final XmaxRealtimeConnectionManager connectionManager;

  /// The manager starting generation and updating conditions.
  final XmaxRealtimeGenerationManager generationManager;

  /// The manager logging and routing runtime failures.
  final XmaxRealtimeErrorManager errorManager;

  /// The controller owning local media and interactions.
  final MediaControlling mediaController;

  /// The controller managing RTC publishing and signaling.
  final StreamControlling streamController;

  /// The shared model-aware sizing service for capture, generation, and returned media.
  final MediaServicing mediaService;

  /// The renderer shared by generation readiness and remote cleanup.
  final RenderControlling renderController;

  /// The recorder shared by connection and generation startup.
  final RealtimeTiming timing;
}

/// Creates realtime components and wires their readiness, failure, and cleanup callbacks.
abstract final class XmaxRealtimeFactory {

  /// Creates the components for a realtime manager without starting capture or a connection.
  ///
  /// Parameters:
  /// - [options]: The realtime model configuration.
  /// - [apiService]: The service used to create and maintain server sessions.
  ///
  /// Returns the configured components and their shared lifecycle manager.
  static XmaxRealtimeComponents make({
    required RealtimeConfiguration options,
    required ApiServicing apiService,
  }) {
    final errorManager = XmaxRealtimeErrorManager();
    final rtcManager = RtcManager();
    final mediaService = MediaService(model: options.model);
    final renderController = RenderController();
    final timing = RealtimeTiming();
    final streamController = StreamController(
      rtcManager: rtcManager,
      errorListener: errorManager.forward,
      localMediaErrorListener: (
        error,
      ) => errorManager.forward(
        error,
        scope: RealtimeFailureScope.all,
      ),
      remoteStreamListener: renderController.setRemoteStream,
      remoteFrameRenderedListener: renderController.markRemoteFrameRendered,
      remoteFrameReadyListener: renderController.markRemoteFrameReady,
    );
    final mediaController = MediaController(
      rtcManager: rtcManager,
      cameraController: CameraController(
        rtcManager: rtcManager,
        mediaService: mediaService,
      ),
      interactionListener: (
        taskID,
        points,
      ) => streamController.sendTracks(
        taskID: taskID,
        points: points,
      ),
      externalController: ExternalVideoController(
        rtcManager: rtcManager,
        mediaService: mediaService,
        errorListener: (
          error,
        ) => errorManager.forward(
          error,
          scope: RealtimeFailureScope.all,
        ),
      ),
    );
    final connectionManager = XmaxRealtimeConnectionManager(
      sessionService: RealtimeSessionService(apiService: apiService),
      interactionController: mediaController,
      renderController: renderController,
      streamController: streamController,
      mediaService: mediaService,
      timing: timing,
    );
    final generationManager = XmaxRealtimeGenerationManager(
      interactionController: mediaController,
      streamController: streamController,
      renderController: renderController,
      timing: timing,
    );

    return assemble(
      mediaController: mediaController,
      streamController: streamController,
      connectionManager: connectionManager,
      generationManager: generationManager,
      errorManager: errorManager,
      mediaService: mediaService,
    );
  }

  /// Connects realtime components to shared failure handling and resource cleanup.
  ///
  /// Parameters:
  /// - [mediaController]: The local media and interaction controller.
  /// - [streamController]: The RTC publication and signaling controller.
  /// - [connectionManager]: The server session and RTC connection manager.
  /// - [generationManager]: The generation request and confirmation manager.
  /// - [errorManager]: The shared runtime failure manager.
  /// - [mediaService]: The shared sizing rules; defaults to the default model's service.
  ///
  /// Returns the components with lifecycle coordination and cleanup configured.
  static XmaxRealtimeComponents assemble({
    required MediaControlling mediaController,
    required StreamControlling streamController,
    required XmaxRealtimeConnectionManager connectionManager,
    required XmaxRealtimeGenerationManager generationManager,
    required XmaxRealtimeErrorManager errorManager,
    MediaServicing? mediaService,
  }) {
    final lifecycleManager = XmaxRealtimeLifecycleManager(
      errorManager: errorManager,
      cleanup: (
        scope,
        taskID,
      ) async {
        streamController.setAdaptiveQualityListener(null);
        final activeSessionID = connectionManager.currentSessionID;
        String? sessionID = activeSessionID.isEmpty ? null : activeSessionID;

        // Every resource owner is given a cleanup opportunity even if another fails.
        if (scope != RealtimeTerminationScope.generation) {
          try {
            await mediaController.stopMicrophoneCapture();
          } catch (error) {
            errorManager.report(error);
          }
        }

        try {
          if (scope == RealtimeTerminationScope.generation) {
            await generationManager.stop(taskID: taskID);
          } else {
            await generationManager.reset(taskID: taskID);
          }
        } catch (error) {
          errorManager.report(error);
        }
        if (scope != RealtimeTerminationScope.generation) {
          try {
            sessionID = await connectionManager.disconnect() ?? sessionID;
          } catch (error) {
            errorManager.report(error);
          }
        }
        if (scope == RealtimeTerminationScope.all) {
          try {
            await mediaController.stopLocalStream();
          } catch (error) {
            errorManager.report(error);
          }
        }
        return RealtimeCleanupResult(
          sessionID: sessionID,
          hasLocalMedia: mediaController.currentTrack != null,
        );
      },
    );

    mediaController.setCameraPreviewReadyListener(() {
      if (mediaController.currentTrack != null) {
        lifecycleManager.markPreviewReady();
      }
    });
    errorManager.setFailureHandler(lifecycleManager.handleFailure);

    return XmaxRealtimeComponents(
      lifecycleManager: lifecycleManager,
      connectionManager: connectionManager,
      generationManager: generationManager,
      errorManager: errorManager,
      mediaController: mediaController,
      streamController: streamController,
      mediaService: mediaService ?? MediaService(),
      renderController: connectionManager.renderController,
      timing: generationManager.timing,
    );
  }
}

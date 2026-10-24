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
import '../../render/RenderController.dart';
import '../../service/media/MediaService.dart';
import '../../service/network/ApiServicing.dart';
import '../../service/realtime/RealtimeSessionService.dart';
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
    final streamController = StreamController(
      rtcManager: rtcManager,
      mediaService: mediaService,
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
    );
    final connectionManager = XmaxRealtimeConnectionManager(
      sessionService: RealtimeSessionService(apiService: apiService),
      interactionController: mediaController,
      renderController: renderController,
      streamController: streamController,
    );
    final generationManager = XmaxRealtimeGenerationManager(
      interactionController: mediaController,
      streamController: streamController,
    );

    return assemble(
      mediaController: mediaController,
      streamController: streamController,
      connectionManager: connectionManager,
      generationManager: generationManager,
      errorManager: errorManager,
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
  ///
  /// Returns the components with lifecycle coordination and cleanup configured.
  static XmaxRealtimeComponents assemble({
    required MediaControlling mediaController,
    required StreamControlling streamController,
    required XmaxRealtimeConnectionManager connectionManager,
    required XmaxRealtimeGenerationManager generationManager,
    required XmaxRealtimeErrorManager errorManager,
  }) {
    final lifecycleManager = XmaxRealtimeLifecycleManager(
      errorManager: errorManager,
      cleanupConnection: (
        taskID,
      ) async {
        // Conceal the result before releasing native video resources.
        // Each cleanup step must run even when another resource owner fails.
        try {
          await connectionManager.prepareForRemoteRemoval();
        } catch (error) {
          errorManager.report(error);
        }

        try {
          await generationManager.reset(taskID: taskID);
        } catch (error) {
          errorManager.report(error);
        }

        final activeSessionID = connectionManager.currentSessionID;
        String? sessionID = activeSessionID.isEmpty ? null : activeSessionID;

        try {
          sessionID = await connectionManager.disconnect() ?? sessionID;
        } catch (error) {
          errorManager.report(error);
        }

        return RealtimeCleanupResult(
          sessionID: sessionID,
          hasLocalMedia: mediaController.currentTrack != null,
        );
      },
      stopLocalMedia: mediaController.stopLocalStream,
      stopGeneration: (
        taskID,
      ) async {
        await connectionManager.prepareForRemoteRemoval();
        await generationManager.stop(taskID: taskID);
      },
      cancelPendingStart: generationManager.cancelPendingStart,
      currentSessionID: () => connectionManager.currentSessionID,
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
    );
  }
}

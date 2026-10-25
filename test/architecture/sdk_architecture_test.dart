import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/XmaxSDK.dart' as compatibility;
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeFactory.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeLifecycleManager.dart';
import 'package:xmax_sdk/src/service/media/RealtimeMediaSource.dart' as media;
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeCameraPreset.dart'
    as camera;
import 'package:xmax_sdk/src/service/realtime/RealtimeModel.dart' as model;
import 'package:xmax_sdk/src/stream/quality/RealtimeQualityLevel.dart'
    as quality;

void main() {
  test(
    'public video widgets distinguish single-track and dual-track rendering',
    () {
      const single = XmaxRealtimeVideo();
      const dual = XmaxRealtimeDualVideo();
      expect(single.track, isNull);
      expect(dual.localTrack, isNull);
      expect(dual.remoteTrack, isNull);
      expect(dual.remoteVideoFadeInDuration, 0.3);
      expect(
        const compatibility.XmaxRealtimeVideo(),
        isA<XmaxRealtimeVideo>(),
      );
      expect(
        const compatibility.XmaxRealtimeDualVideo(),
        isA<XmaxRealtimeDualVideo>(),
      );
    },
  );

  test('video widget sources use the public component names', () {
    for (final name in ['XmaxRealtimeVideo', 'XmaxRealtimeDualVideo']) {
      expect(File('lib/src/render/video/$name.dart').existsSync(), isTrue);
      expect(File('lib/src/render/video/${name}View.dart').existsSync(), isFalse);
    }
  });

  test('public entry points expose the same relocated domain types', () {
    expect(
      identical(
        RealtimeModel.x2_1_1_preview_cn,
        model.RealtimeModel.x2_1_1_preview_cn,
      ),
      isTrue,
    );
    expect(
      identical(
        RealtimeModel.x2_1_1_preview_cn,
        compatibility.RealtimeModel.x2_1_1_preview_cn,
      ),
      isTrue,
    );
    expect(
      identical(RealtimeMediaSource.camera, media.RealtimeMediaSource.camera),
      isTrue,
    );
    expect(
      identical(
        RealtimeCameraPreset.resolution1408x1408,
        camera.RealtimeCameraPreset.resolution1408x1408,
      ),
      isTrue,
    );
    expect(
      identical(RealtimeQualityLevel.l2, quality.RealtimeQualityLevel.l2),
      isTrue,
    );
  });

  test('public model capabilities expose the supported regional previews', () {
    expect(RealtimeModel.values, [
      RealtimeModel.x2_1_1_preview_cn,
      RealtimeModel.x2_1_1_preview_us,
    ]);
    expect(
      RealtimeModel.x2_1_1_preview_cn.defaultCameraVideoFormat,
      const RealtimeVideoFormat(width: 1024, height: 1920, fps: 30),
    );
    expect(RealtimeModel.x2_1_1_preview_cn.supportedVideoFormats.length, 2);
    expect(RealtimeModel.x2_1_1_preview_cn.minimumInputPixels, 200000);
    expect(RealtimeModel.x2_1_1_preview_cn.maximumInputPixels, 2100000);
    expect(RealtimeModel.x2_1_1_preview_cn.inputSizeAlignment, 32);
  });

  test('lower layers do not import realtime domain types from Core', () {
    final violations = <String>[];
    for (final directory in [
      'service',
      'stream',
      'media',
      'render',
      'foundation',
    ]) {
      for (final entity in Directory(
        'lib/src/$directory',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final line in entity.readAsLinesSync()) {
          if (RegExp(
            r'''^(import|export) ['"].*core/realtime/''',
          ).hasMatch(line)) {
            violations.add('${entity.path}: $line');
          }
        }
      }
    }
    expect(violations, isEmpty);
  });

  test(
    'foundation models have dedicated files instead of aggregate libraries',
    () {
      for (final path in [
        'rtc/RoomJoinConfiguration.dart',
        'rtc/VideoEncodingConfiguration.dart',
        'rtc/RemoteStream.dart',
        'storage/StorageProgressListener.dart',
        'storage/StorageCredential.dart',
        'storage/StorageConfiguration.dart',
        'storage/StorageUploadSource.dart',
        'storage/StoredFile.dart',
        'storage/DownloadedFile.dart',
      ]) {
        expect(
          File('lib/src/foundation/$path').existsSync(),
          isTrue,
          reason: path,
        );
      }
      expect(
        File('lib/src/foundation/rtc/RtcModels.dart').existsSync(),
        isFalse,
      );
      expect(
        File('lib/src/foundation/storage/StorageModels.dart').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'the component factory does not start capture or request a session',
    () async {
      final api = _RecordingApi();
      final components = XmaxRealtimeFactory.make(
        options: const RealtimeConfiguration(
          model: RealtimeModel.x2_1_1_preview_cn,
        ),
        apiService: api,
      );
      expect(
        components.lifecycleManager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
      expect(components.mediaController.currentTrack, isNull);
      expect(components.connectionManager.currentSessionID, isEmpty);
      expect(
        components.renderController,
        same(components.connectionManager.renderController),
      );
      expect(components.timing, same(components.connectionManager.timing));
      expect(components.timing, same(components.generationManager.timing));
      expect(api.requests, 0);
      await components.lifecycleManager.terminate(RealtimeTerminationScope.all);
      expect(api.requests, 0);
    },
  );
}

final class _RecordingApi implements ApiServicing {
  int requests = 0;

  @override
  Future<T> request<T>(
    ApiMethod method, {
    required String path,
    Object? body,
    required T Function(Object? json) decode,
    Future<void>? cancellation,
  }) async {
    requests++;
    throw StateError('No API request is expected during component assembly');
  }
}

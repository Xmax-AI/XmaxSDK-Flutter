import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/XmaxSDK.dart' as compatibility;
import 'package:xmax_sdk/xmax_sdk.dart';
import 'package:xmax_sdk/src/core/realtime/XmaxRealtimeFactory.dart';
import 'package:xmax_sdk/src/service/media/RealtimeMediaSource.dart' as media;
import 'package:xmax_sdk/src/service/network/ApiServicing.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeCameraPreset.dart'
    as camera;
import 'package:xmax_sdk/src/service/realtime/RealtimeModel.dart' as model;
import 'package:xmax_sdk/src/stream/quality/RealtimeQualityLevel.dart'
    as quality;

void main() {
  test('public entry points expose the same relocated domain types', () {
    expect(identical(RealtimeModel.x2_1, model.RealtimeModel.x2_1), isTrue);
    expect(
      identical(RealtimeModel.x2_1, compatibility.RealtimeModel.x2_1),
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

  test('model capability values remain unchanged by layer relocation', () {
    expect(RealtimeModel.values, [RealtimeModel.x2_1]);
    expect(
      RealtimeModel.x2_1.defaultCameraVideoFormat,
      const RealtimeVideoFormat(width: 1080, height: 1920, fps: 30),
    );
    expect(RealtimeModel.x2_1.supportedVideoFormats.length, 5);
    expect(RealtimeModel.x2_1.minimumInputPixels, 600000);
    expect(RealtimeModel.x2_1.maximumInputPixels, 2100000);
    expect(RealtimeModel.x2_1.inputSizeAlignment, 32);
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
        options: const RealtimeConfiguration(model: RealtimeModel.x2_1),
        apiService: api,
      );
      expect(
        components.lifecycleManager.currentState.connectionState,
        RealtimeConnectionState.idle,
      );
      expect(components.mediaController.currentTrack, isNull);
      expect(components.connectionManager.currentSessionID, isEmpty);
      expect(api.requests, 0);
      await components.lifecycleManager.close();
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
  }) async {
    requests++;
    throw StateError('No API request is expected during component assembly');
  }
}

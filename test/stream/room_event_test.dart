import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/runtime/RuntimeInfo.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeContext.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimePoint.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoFormat.dart';
import 'package:xmax_sdk/src/stream/room/RoomEvent.dart';

void main() {
  const format = RealtimeVideoFormat(width: 1024, height: 576, fps: 30);

  for (final padding in [true, false]) {
    test(
      'generation messages encode contain padding only when requested ($padding)',
      () {
        for (final encode in [RoomEvent.start, RoomEvent.changeCondition]) {
          final event =
              jsonDecode(
                    encode(
                      userID: 'user',
                      taskID: 'task',
                      videoFormat: format,
                      context: RealtimeContext(prompt: 'test'),
                      paddingContain: padding,
                    ),
                  )
                  as Map<String, dynamic>;
          final params = event['params'] as Map<String, dynamic>;
          expect(params['size'], [1024, 576]);
          expect(params['padding'], padding ? 'contain' : isNull);
          expect(params.containsKey('target_size'), isFalse);
          if (event['event'] == 'change_condition') {
            expect(params.containsKey('min_bitrate'), isFalse);
            expect(params.containsKey('max_bitrate'), isFalse);
          }
        }
      },
    );
  }

  test('start event matches iOS room signaling contract', () {
    final event = jsonDecode(
      RoomEvent.start(
        userID: 'user-1',
        taskID: 'task-1',
        videoFormat: format,
        context: RealtimeContext(
          prompt: 'turn it into ink',
          referencePath: 'cos/ref.png',
        ),
      ),
    );

    expect(event, <String, Object?>{
      'event': 'start',
      'params': <String, Object?>{
        'model': 'default',
        'size': <int>[1024, 576],
        'prompt': 'turn it into ink',
        'ref_image_path': 'cos/ref.png',
        'face_replace': false,
        'mirror': false,
        'min_bitrate': 100,
        'max_bitrate': 1263,
      },
      'user_id': 'user-1',
      'uid': 'task-1',
      'session_uid': 'task-1',
      'runtime': RuntimeInfo.current.toJson(),
    });
  });

  test('start and condition change encode optional target size', () {
    for (final message in <String>[
      RoomEvent.start(
        userID: 'user-1',
        taskID: 'task-1',
        videoFormat: format,
        targetSize: const Size(1920, 1080),
        context: RealtimeContext(prompt: 'start'),
      ),
      RoomEvent.changeCondition(
        userID: 'user-1',
        taskID: 'task-1',
        videoFormat: format,
        targetSize: const Size(1920, 1080),
        context: RealtimeContext(prompt: 'change'),
      ),
    ]) {
      final event = jsonDecode(message) as Map<String, dynamic>;
      final params = event['params'] as Map<String, dynamic>;
      expect(params['target_size'], <int>[1920, 1080]);
      expect(event['runtime'], RuntimeInfo.current.toJson());
    }
  });

  test('change target size matches iOS room signaling contract', () {
    expect(
      jsonDecode(
        RoomEvent.changeTargetSize(
          userID: 'user-1',
          taskID: 'task-1',
          targetSize: const Size(1280, 720),
        ),
      ),
      <String, Object?>{
        'event': 'change_target_size',
        'params': <String, Object?>{
          'target_size': <int>[1280, 720],
          'min_bitrate': 100,
          'max_bitrate': 1774,
        },
        'user_id': 'user-1',
        'uid': 'task-1',
        'session_uid': 'task-1',
        'runtime': RuntimeInfo.current.toJson(),
      },
    );
  });

  test('change condition omits a removed reference like iOS', () {
    final event =
        jsonDecode(
              RoomEvent.changeCondition(
                userID: 'user-1',
                taskID: 'task-1',
                videoFormat: format,
                context: RealtimeContext(prompt: 'animate without a reference'),
              ),
            )
            as Map<String, Object?>;
    final params = event['params'] as Map<String, Object?>;

    expect(event['event'], 'change_condition');
    expect(params['prompt'], 'animate without a reference');
    expect(params.containsKey('ref_image_path'), isFalse);
  });

  test('tracks, stop, and heartbeat events match iOS keys', () {
    expect(
      jsonDecode(
        RoomEvent.tracks(
          userID: 'user-1',
          taskID: 'task-1',
          points: const <RealtimePoint>[
            RealtimePoint(x: 10, y: 20),
            RealtimePoint(x: 30, y: 40),
          ],
        ),
      ),
      <String, Object?>{
        'event': 'tracks',
        'tracks': <List<double>>[
          <double>[10, 20],
          <double>[30, 40],
        ],
        'user_id': 'user-1',
        'uid': 'task-1',
        'session_uid': 'task-1',
        'runtime': RuntimeInfo.current.toJson(),
      },
    );
    expect(
      jsonDecode(RoomEvent.stop(userID: 'user-1', taskID: 'task-1')),
      <String, Object?>{
        'event': 'stop',
        'user_id': 'user-1',
        'uid': 'task-1',
        'session_uid': 'task-1',
        'runtime': RuntimeInfo.current.toJson(),
      },
    );
    expect(jsonDecode(RoomEvent.heartbeat(userID: 'user-1')), <String, Object?>{
      'event': 'heartbeat',
      'user_id': 'user-1',
      'runtime': RuntimeInfo.current.toJson(),
    });
  });

  test('runtime carries the native SDK field names', () {
    expect(RuntimeInfo.current.toJson().keys.toSet(), <String>{
      'platform',
      'os_version',
      'sdk_version',
      'device_model',
    });
    expect(RuntimeInfo.current.toJson()['sdk_version'], '1.0.2');
  });
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLoggerOption.dart';
import 'package:xmax_sdk/src/foundation/media/video/VideoContentMode.dart';
import 'package:xmax_sdk/src/media/interaction/InteractionController.dart';
import 'package:xmax_sdk/src/media/interaction/InteractionFrame.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeVideoFormat.dart';

const format = RealtimeVideoFormat(width: 100, height: 100, fps: 30);
InteractionFrame frame(double x) => InteractionFrame(
  points: <Offset>[Offset(x, 50)],
  viewportSize: const Size(100, 100),
  contentMode: VideoContentMode.fill,
);

void main() {
  for (final sameID in <bool>[false, true]) {
    for (final oldFails in <bool>[false, true]) {
      test(
        'new drain is independent (sameID=$sameID, oldFails=$oldFails)',
        () async {
          final sends = <(String, double)>[];
          final gates = <Completer<void>>[];
          final logs = <String>[];
          XmaxLogger.configure(options: XmaxLoggerOption.all);
          XmaxLogger.setSink((_, message) => logs.add(message));
          addTearDown(XmaxLogger.reset);
          final controller = InteractionController(
            listener: (task, points) {
              sends.add((task, points.single.x));
              final gate = Completer<void>();
              gates.add(gate);
              return gate.future;
            },
          );
          controller.startInteraction(taskID: 'old', videoFormat: format);
          controller.submitInteraction(frame(10));
          controller.submitInteraction(frame(20));
          final newID = sameID ? 'old' : 'new';
          controller.startInteraction(taskID: newID, videoFormat: format);
          controller.submitInteraction(frame(30));
          expect(sends, <(String, double)>[('old', 0.1), (newID, 0.3)]);

          if (oldFails) {
            gates[0].completeError(StateError('stale failure'));
          } else {
            gates[0].complete();
          }
          await Future<void>.delayed(Duration.zero);
          controller.submitInteraction(frame(40));
          controller.submitInteraction(frame(50));
          expect(
            sends,
            hasLength(2),
            reason: 'Old finally must not clear the new sending flag',
          );
          gates[1].complete();
          await Future<void>.delayed(Duration.zero);
          expect(sends.last, (
            newID,
            0.5,
          ), reason: 'Only the latest pending sample is sent');
          expect(sends, hasLength(3));
          expect(
            logs,
            isEmpty,
            reason: 'Discard failures from superseded tasks',
          );
          controller.stopInteraction();
          gates[2].complete();
          await Future<void>.delayed(Duration.zero);
        },
      );
    }
  }

  test('stop drops pending frames and same-ID restart does not wait', () async {
    final sends = <double>[];
    final old = Completer<void>();
    final controller = InteractionController(
      listener: (_, points) {
        sends.add(points.single.x);
        return sends.length == 1 ? old.future : Future<void>.value();
      },
    );
    controller.startInteraction(taskID: 'task', videoFormat: format);
    controller.submitInteraction(frame(10));
    controller.submitInteraction(frame(20));
    controller.stopInteraction();
    controller.submitInteraction(frame(30));
    expect(sends, <double>[0.1]);
    controller.startInteraction(taskID: 'task', videoFormat: format);
    controller.submitInteraction(frame(40));
    expect(sends, <double>[0.1, 0.4]);
    old.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sends, <double>[0.1, 0.4]);
    controller.stopInteraction();
  });
}

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/stream/room/RoomCommandController.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  _test('retries at fixed offsets with one frozen payload and UUID', (
    tester,
    h,
  ) async {
    var encodes = 0;
    final result = h.controller.send(
      kind: RoomCommandKind.start,
      taskID: 'task',
      createMessage: (xid) {
        encodes++;
        return xid;
      },
    );
    await tester.pump();
    await result;
    expect(h.attempts, hasLength(1));
    expect(
      h.attempts.single.message,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    for (final (delta, count) in [
      (299, 1),
      (1, 2),
      (700, 3),
      (2000, 4),
      (300, 5),
      (700, 6),
    ]) {
      await tester.pump(Duration(milliseconds: delta));
      expect(h.attempts, hasLength(count));
    }
    expect(h.attempts, hasLength(6));
    expect(h.attempts.map((a) => a.message).toSet(), hasLength(1));
    expect(encodes, 1);
    await tester.pump(const Duration(seconds: 20));
    expect(h.attempts, hasLength(6));
  });

  _test('matching ACK stops retries after transport success', (
    tester,
    h,
  ) async {
    h.send();
    await tester.pump();
    h.ack();
    await tester.pump(const Duration(seconds: 10));
    expect(h.attempts, hasLength(1));
  });

  _test('only positive safe counts and a matching sent xid stop retries', (
    tester,
    h,
  ) async {
    h.send();
    await tester.pump();
    for (final count in [0, -1, 9007199254740992]) {
      h.ack(count: count);
    }
    h.controller.acknowledge(xid: 'unknown', count: 1);
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.attempts, hasLength(2));
    h.ack(count: 9007199254740991);
    await tester.pump(const Duration(seconds: 10));
    expect(h.attempts, hasLength(2));
  });

  _test('ACK preserves unresolved original and never completes the caller', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    var complete = false;
    h.send().then((_) => complete = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    h.ack();
    await tester.pump();
    expect(complete, isFalse);
    expect(h.attempts.first.cancelled, isFalse);
    expect(h.attempts[1].cancelled, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(complete, isFalse);
    h.attempts.first.done.complete();
    await tester.pump();
    expect(complete, isTrue);
  });

  _test('deadline preserves unresolved original without failing the caller', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    var complete = false;
    h.send().then((_) => complete = true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(complete, isFalse);
    expect(h.attempts, hasLength(6));
    expect(h.attempts.first.cancelled, isFalse);
    expect(h.attempts.skip(1).every((a) => a.cancelled), isTrue);
    h.attempts.first.done.complete();
    await tester.pump();
    expect(complete, isTrue);
  });

  _test('redundant transport can resolve caller before original', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    var complete = false;
    h.send().then((_) => complete = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    h.attempts[1].done.complete();
    await tester.pump();
    expect(complete, isTrue);
    h.ack();
    await tester.pump();
    expect(h.attempts.first.cancelled, isTrue);
  });

  _test('initial failure fails caller and cancels dependent task updates', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    final result = h.send();
    final update = h.send(kind: RoomCommandKind.changeCondition);
    final rejected = expectLater(result, throwsA(isA<XmaxError>()));
    final cancelled = expectLater(
      update,
      throwsA(
        isA<XmaxError>().having((e) => e.code, 'code', XmaxErrorCode.cancelled),
      ),
    );
    await tester.pump();
    h.attempts.first.done.completeError(StateError('native failure'));
    await tester.pump();
    await rejected;
    await cancelled;
    expect(h.attempts, hasLength(1));
  });

  _test('retry failure after success does not fail room or later commands', (
    tester,
    h,
  ) async {
    h.send();
    await tester.pump();
    h.autoComplete = false;
    await tester.pump(const Duration(milliseconds: 300));
    h.attempts.last.done.completeError(StateError('retry failure'));
    await tester.pump();
    h.autoComplete = true;
    final update = h.send(kind: RoomCommandKind.changeCondition);
    await tester.pump();
    await update;
    expect(h.attempts.last.message, startsWith('changeCondition:'));
  });

  _test('new condition supersedes only the same kind and task', (
    tester,
    h,
  ) async {
    h.send();
    await tester.pump();
    h.send(kind: RoomCommandKind.changeTargetSize);
    await tester.pump();
    h.send(kind: RoomCommandKind.changeCondition);
    await tester.pump();
    final old = h.attempts.last.message;
    h.send(kind: RoomCommandKind.changeCondition);
    await tester.pump();
    final latest = h.attempts.last.message;
    await tester.pump(const Duration(milliseconds: 300));
    expect(h.attempts.where((a) => a.message == old), hasLength(1));
    expect(h.attempts.where((a) => a.message == latest), hasLength(2));
    expect(
      h.attempts.where((a) => a.message.startsWith('start:')),
      hasLength(2),
    );
    expect(
      h.attempts.where((a) => a.message.startsWith('changeTargetSize:')),
      hasLength(2),
    );
  });

  _test('superseded queued update retains initial command ordering barrier', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    h.send();
    await tester.pump();
    final old = h.send(kind: RoomCommandKind.changeCondition);
    final cancelled = expectLater(old, throwsA(isA<XmaxError>()));
    h.send(kind: RoomCommandKind.changeCondition);
    await tester.pump();
    await cancelled;
    expect(h.attempts, hasLength(1));
    h.attempts.first.done.complete();
    await tester.pump();
    expect(h.attempts, hasLength(2));
    expect(h.attempts.last.message, startsWith('changeCondition:'));
    h.attempts.last.done.complete();
    await tester.pump();
  });

  _test('new start cancels every older command and queued transport', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    final old = h.send();
    final cancelled = expectLater(old, throwsA(isA<XmaxError>()));
    await tester.pump();
    h.autoComplete = true;
    final next = h.send(task: 'next');
    await tester.pump();
    await cancelled;
    await next;
    expect(h.attempts.first.cancelled, isTrue);
    expect(h.attempts.last.message, contains(':next:'));
    h.ack(index: 1);
    await tester.pump(const Duration(seconds: 10));
    expect(h.attempts, hasLength(2));
  });

  _test('explicit cancellation stops unresolved original after ACK', (
    tester,
    h,
  ) async {
    h.autoComplete = false;
    final result = h.send();
    final rejected = expectLater(result, throwsA(isA<XmaxError>()));
    await tester.pump();
    h.ack();
    h.controller.cancel(taskID: 'task');
    await tester.pump();
    await rejected;
    expect(h.attempts.first.cancelled, isTrue);
  });

  _test(
    'validity is checked before queued work starts and close rejects sends',
    (tester, h) async {
      h.autoComplete = false;
      h.send();
      await tester.pump();
      var valid = true;
      final next = h.controller.send(
        kind: RoomCommandKind.changeTargetSize,
        taskID: 'task',
        createMessage: (xid) => xid,
        ensureCurrent: () {
          if (!valid) throw StateError('expired');
        },
      );
      final rejected = expectLater(next, throwsA(isA<XmaxError>()));
      valid = false;
      h.attempts.first.done.complete();
      await tester.pump();
      await rejected;
      expect(h.attempts, hasLength(1));
      h.controller.close();
      expect(h.send, throwsA(isA<XmaxError>()));
    },
  );
}

void _test(String name, Future<void> Function(WidgetTester, _Harness) body) {
  testWidgets(name, (tester) async {
    final harness = _Harness();
    try {
      await body(tester, harness);
    } finally {
      harness.controller.close();
      await tester.pump();
    }
  });
}

class _Harness {
  final attempts = <_Send>[];
  bool autoComplete = true;
  late final controller = RoomCommandController(
    sendMessage: (message, cancellation) {
      final attempt = _Send(message);
      attempts.add(attempt);
      cancellation.then((_) {
        attempt.cancelled = true;
        if (!attempt.done.isCompleted) {
          attempt.done.completeError(
            const XmaxError(
              code: XmaxErrorCode.cancelled,
              message: 'cancelled',
            ),
          );
        }
      });
      if (autoComplete) attempt.done.complete();
      return attempt.done.future;
    },
  );
  Future<void> send({
    RoomCommandKind kind = RoomCommandKind.start,
    String task = 'task',
  }) {
    final result = controller.send(
      kind: kind,
      taskID: task,
      createMessage: (xid) => '${kind.name}:$task:$xid',
    );
    result.ignore();
    return result;
  }

  void ack({int count = 1, int index = 0}) => controller.acknowledge(
    xid: attempts[index].message.split(':').last,
    count: count,
  );
}

class _Send {
  _Send(this.message);
  final String message;
  final done = Completer<void>();
  bool cancelled = false;
}

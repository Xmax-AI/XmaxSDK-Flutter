import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/foundation/rtc/RtcMessageQueue.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

void main() {
  test('cancelling queued control removes only that attempt', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final cancellation = Completer<void>();
    final sent = <String>[];
    final failures = <Object>[];
    final queue = RtcMessageQueue(
      onFailure: failures.add,
      send: (packet) async {
        final value = utf8.decode(packet);
        sent.add(value);
        if (value == 'first') {
          started.complete();
          await gate.future;
        }
      },
    );
    final first = queue.enqueue('first');
    await started.future;
    final obsolete = queue.enqueue(
      'obsolete',
      cancellation: cancellation.future,
    );
    final rejected = expectLater(
      obsolete,
      throwsA(
        isA<XmaxError>().having((e) => e.code, 'code', XmaxErrorCode.cancelled),
      ),
    );
    final next = queue.enqueue('next');
    cancellation.complete();
    await rejected;
    gate.complete();
    await Future.wait([first, next]);
    expect(sent, ['first', 'next']);
    expect(failures, isEmpty);
    queue.close();
  });

  test(
    'cancelled fragmented send settles its current packet before the next control',
    () async {
      final gate = Completer<void>(), started = Completer<void>();
      final cancellation = Completer<void>();
      final sent = <String>[];
      final failures = <Object>[];
      final queue = RtcMessageQueue(
        onFailure: failures.add,
        send: (packet) async {
          sent.add(utf8.decode(packet));
          if (sent.length == 1) {
            started.complete();
            await gate.future;
          }
        },
      );
      final fragmented = queue.enqueue(
        'x' * 2000,
        cancellation: cancellation.future,
      );
      final rejected = expectLater(fragmented, throwsA(isA<XmaxError>()));
      await started.future;
      final next = queue.enqueue('next');
      cancellation.complete();
      await rejected;
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1));
      // A late native failure from an already-cancelled packet cannot fault the room.
      gate.completeError(StateError('late native failure'));
      await next;
      expect(sent, hasLength(2));
      expect(sent.last, 'next');
      expect(failures, isEmpty);
      queue.close();
    },
  );

  test(
    'cancellation interrupts quota waits without retaining obsolete fragments',
    () async {
      final cancellation = Completer<void>();
      final waiting = Completer<void>();
      var sends = 0;
      final queue = RtcMessageQueue(
        now: () => Duration.zero,
        delay: (_) {
          if (!waiting.isCompleted) waiting.complete();
          return Completer<void>().future;
        },
        send: (_) async => sends++,
      );
      await Future.wait([for (var i = 0; i < 58; i++) queue.enqueue('$i')]);
      final blocked = queue.enqueue(
        'obsolete',
        cancellation: cancellation.future,
      );
      final rejected = expectLater(blocked, throwsA(isA<XmaxError>()));
      await waiting.future;
      cancellation.complete();
      await rejected;
      expect(sends, 58);
      queue.close();
    },
  );

  test(
    'an already completed cancellation prevents native submission',
    () async {
      var sends = 0;
      final queue = RtcMessageQueue(send: (_) async => sends++);
      await expectLater(
        queue.enqueue('cancelled', cancellation: Future.value()),
        throwsA(isA<XmaxError>()),
      );
      expect(sends, 0);
      await queue.enqueue('next');
      expect(sends, 1);
      queue.close();
    },
  );

  test('large unicode signals reassemble without splitting scalars', () {
    final message = jsonEncode({
      'event': 'start',
      'prompt': List.filled(400, '测试🙂\\"').join(),
    });
    final packets = RtcMessageCodec.encode(message);
    expect(packets.length, greaterThan(1));
    final fragments = packets
        .map(
          (packet) => jsonDecode(utf8.decode(packet)) as Map<String, dynamic>,
        )
        .toList();
    expect(fragments.map((f) => f['eventId']).toSet(), hasLength(1));
    expect(fragments.map((f) => f['data']).join(), message);
    for (var index = 0; index < packets.length; index++) {
      expect(packets[index].length, lessThanOrEqualTo(800));
      expect(fragments[index]['index'], index);
      expect(fragments[index]['count'], packets.length);
      expect(fragments[index]['event'], '__agora_chunk__');
    }
    expect(() => RtcMessageCodec.encode(''), throwsA(isA<XmaxError>()));
    expect(
      () => RtcMessageCodec.encode('x' * 262145),
      throwsA(isA<XmaxError>()),
    );
  });
  test('queued trajectories coalesce and preserve control ordering', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final sent = <String>[];
    final queue = RtcMessageQueue(
      send: (packet) async {
        final value = utf8.decode(packet);
        sent.add(value);
        if (value == 'start') {
          started.complete();
          await gate.future;
        }
      },
    );
    final start = queue.enqueue('start');
    await started.future;
    final a = queue.enqueue(
      'old',
      replacingPendingMessage: 'tracks:task',
      reportFailure: false,
    );
    final b = queue.enqueue(
      'latest',
      replacingPendingMessage: 'tracks:task',
      reportFailure: false,
    );
    final stop = queue.enqueue('stop');
    expect(identical(a, b), isTrue);
    gate.complete();
    await Future.wait([start, a, b, stop]);
    expect(sent, ['start', 'latest', 'stop']);
    queue.close();
  });
  test('discarding pending trajectories preserves queued controls', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final sent = <String>[];
    final queue = RtcMessageQueue(
      send: (packet) async {
        final value = utf8.decode(packet);
        sent.add(value);
        if (value == 'start') {
          started.complete();
          await gate.future;
        }
      },
    );
    final start = queue.enqueue('start');
    await started.future;
    final condition = queue.enqueue('condition');
    final tracks = queue.enqueue(
      'tracks',
      replacingPendingMessage: 'tracks:task',
    );
    queue.discardPendingMessages();
    await tracks;
    final stop = queue.enqueue('stop');
    gate.complete();
    await Future.wait([start, condition, stop]);
    expect(sent, ['start', 'condition', 'stop']);
    queue.close();
  });
  test(
    'nonfatal configuration errors do not poison subsequent controls',
    () async {
      final failures = <Object>[];
      final sent = <String>[];
      final queue = RtcMessageQueue(
        onFailure: failures.add,
        send: (packet) async {
          final value = utf8.decode(packet);
          sent.add(value);
          if (value == 'target') throw StateError('configuration rejected');
        },
      );
      final target = queue.enqueue('target', reportFailure: false);
      final condition = queue.enqueue('condition');
      await expectLater(target, throwsStateError);
      await condition;
      expect(failures, isEmpty);
      expect(sent, ['target', 'condition']);
      queue.close();
    },
  );
  test('packet and byte budgets use a sliding one-second window', () async {
    var now = Duration.zero;
    final times = <Duration>[];
    final queue = RtcMessageQueue(
      now: () => now,
      delay: (duration) async {
        now += duration;
      },
      send: (_) async {
        times.add(now);
      },
    );
    final sends = [for (var i = 0; i < 60; i++) queue.enqueue('$i')];
    await Future.wait(sends);
    expect(times.take(58), everyElement(Duration.zero));
    expect(times[58], const Duration(seconds: 1));
    queue.close();
    now = Duration.zero;
    times.clear();
    final bytes = RtcMessageQueue(
      now: () => now,
      delay: (duration) async {
        now += duration;
      },
      send: (_) async {
        times.add(now);
      },
    );
    await Future.wait([for (var i = 0; i < 40; i++) bytes.enqueue('a' * 800)]);
    expect(times[35], Duration.zero);
    expect(times[36], const Duration(seconds: 1));
    bytes.close();
  });
  test('close promptly cancels pending and active futures', () async {
    final gate = Completer<void>(), started = Completer<void>();
    final queue = RtcMessageQueue(
      send: (_) async {
        started.complete();
        await gate.future;
      },
    );
    final first = queue.enqueue('one');
    await started.future;
    final second = queue.enqueue('two');
    final rejected = Future.wait([
      expectLater(first, throwsA(isA<XmaxError>())),
      expectLater(second, throwsA(isA<XmaxError>())),
    ]);
    queue.close();
    await rejected;
    gate.complete();
    await expectLater(queue.enqueue('three'), throwsA(isA<XmaxError>()));
  });
}

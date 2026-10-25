import 'package:flutter_test/flutter_test.dart';
import 'package:xmax_sdk/src/service/realtime/RealtimeTiming.dart';
import 'package:xmax_sdk/src/core/XmaxEnvironment.dart';
import 'package:xmax_sdk/src/foundation/errors/XmaxError.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLogger.dart';
import 'package:xmax_sdk/src/foundation/logging/XmaxLoggerOption.dart';

void main() {
  final messages = <String>[];
  setUp(() {
    messages.clear();
    XmaxLogger.configure(
      options: XmaxLoggerOption.performance,
      environment: XmaxEnvironment.global,
    );
    XmaxLogger.setSink(
      (_, message) => messages.add(message.replaceAll('[Xmax][Realtime] ', '')),
    );
  });
  tearDown(XmaxLogger.reset);

  test('startup timing reports distinct monotonic stages once', () {
    var now = 0;
    final timing = RealtimeTiming(now: () => now);
    timing.beginSessionCreation();
    now = 2000;
    timing.finishSessionCreation();
    timing.beginRoomJoin();
    now = 5000;
    timing.finishRoomJoin();
    timing.beginLocalPublication();
    now = 5500;
    timing.finishLocalPublication();
    timing.beginSignal();
    now = 8000;
    timing.finishFirstFrame();
    now = 12000;
    timing.finish();
    timing.finish();
    expect(messages, hasLength(1));
    final log = messages.single;
    expect(log, contains('Total Duration: 12.0 ms'));
    expect(
      log,
      contains('''
└─ Total Duration: 12.0 ms
   ├─ Session Creation: 2.0 ms
   ├─ RTC Room Join: 3.0 ms
   ├─ Local Stream Publication: 0.5 ms
   └─ First Frame Arrival: 2.5 ms'''),
    );
    expect(log, isNot(contains('Realtime Connection:')));
    expect(log, isNot(contains('Remote Stream:')));
  });

  test(
    'failure records the pending stage and suppresses deliberate cancellation',
    () {
      var now = 0;
      final timing = RealtimeTiming(now: () => now)..beginSignal();
      now = 1000;
      timing.finishFirstFrame();
      now = 4000;
      timing.finishFailure(
        const XmaxError(code: XmaxErrorCode.timeout, message: 'frame timeout'),
      );
      expect(
        messages.single,
        contains('Current Stage: First Frame Ready, Completing Startup'),
      );
      expect(messages.single, contains('Elapsed Time: 4.0 ms'));
      expect(messages.single, contains('First Frame Arrival: 1.0 ms'));
      expect(messages.single, contains('Failure Reason: frame timeout'));
      RealtimeTiming().finishFailure(
        const XmaxError(code: XmaxErrorCode.cancelled, message: 'cancelled'),
      );
      expect(messages, hasLength(1));
    },
  );

  test('performance switch and language apply to timing diagnostics', () {
    XmaxLogger.configure(options: XmaxLoggerOption.business);
    RealtimeTiming().finish();
    expect(messages, isEmpty);
    XmaxLogger.configure(options: XmaxLoggerOption.performance);
    final timing = RealtimeTiming(now: () => 0);
    timing.beginSessionCreation();
    timing.finishSessionCreation();
    timing.beginRoomJoin();
    timing.finishRoomJoin();
    timing.beginLocalPublication();
    timing.finishLocalPublication();
    timing.beginSignal();
    timing.finishFirstFrame();
    timing.finish();
    expect(
      messages.single,
      contains('''
└─ 总耗时：0.0 ms
   ├─ 创建会话：0.0 ms
   ├─ RTC 进房：0.0 ms
   ├─ 发布本地流：0.0 ms
   └─ 首帧到达：0.0 ms'''),
    );

    messages.clear();
    final failed = RealtimeTiming(now: () => 0)..beginLocalPublication();
    failed.finishFailure(StateError('publication failed'));
    expect(messages.single, contains('│  ├─ 发布本地流：0.0 ms'));
    expect(messages.single, contains('停留阶段：发布本地流'));
  });

  test('overlapping attempts keep separate stage state', () {
    var now = 0;
    final old = RealtimeTiming(now: () => now)..beginSignal();
    now = 2000;
    final current = RealtimeTiming(now: () => now)..beginSessionCreation();
    now = 5000;
    old.finishFailure(
      const XmaxError(code: XmaxErrorCode.cancelled, message: 'superseded'),
    );
    current.finishFailure(
      const XmaxError(code: XmaxErrorCode.apiError, message: 'session failed'),
    );
    expect(messages, hasLength(1));
    expect(messages.single, contains('Current Stage: Creating Session'));
    expect(messages.single, contains('Elapsed Time: 3.0 ms'));
  });

  final failureStages = <(String, void Function(RealtimeTiming))>[
    ('Invocation and Local Preparation', (_) {}),
    ('Creating Session', (timing) => timing.beginSessionCreation()),
    ('RTC Connection Setup', (timing) => timing.finishSessionCreation()),
    ('Joining RTC Room', (timing) => timing.beginRoomJoin()),
    ('Preparing Local Stream Publication', (timing) => timing.finishRoomJoin()),
    ('Publishing Local Stream', (timing) => timing.beginLocalPublication()),
    ('Preparing Generation', (timing) => timing.finishLocalPublication()),
    ('Waiting for First Frame', (timing) => timing.beginSignal()),
  ];
  for (final (stage, prepare) in failureStages) {
    test('failure identifies $stage and retains all four stages', () {
      var now = 0;
      final timing = RealtimeTiming(now: () => now);
      prepare(timing);
      now = 4000;
      timing.finishFailure(
        const XmaxError(
          code: XmaxErrorCode.timeout,
          message: 'startup timeout',
        ),
      );
      timing.finishFailure(StateError('duplicate'));
      timing.finish();
      expect(messages, hasLength(1));
      final log = messages.single;
      expect(log, contains('Elapsed Time: 4.0 ms'));
      expect(log, contains('Current Stage: $stage'));
      expect(log, contains('Failure Reason: startup timeout'));
      expect(log, contains('│  ├─ Session Creation:'));
      expect(log, contains('│  ├─ RTC Room Join:'));
      expect(log, contains('│  ├─ Local Stream Publication:'));
      expect(log, contains('│  └─ First Frame Arrival:'));
      if (stage == 'Invocation and Local Preparation') {
        expect(log, contains('Local Stream Publication: —'));
        expect(log, contains('First Frame Arrival: —'));
      }
      if (stage == 'Publishing Local Stream') {
        expect(log, contains('Local Stream Publication: 4.0 ms'));
      }
      if (stage == 'Waiting for First Frame') {
        expect(log, contains('First Frame Arrival: 4.0 ms'));
      }
    });
  }

  test('completion without a first frame reports unavailable timing', () {
    RealtimeTiming().finish();
    expect(
      messages.single,
      contains('Realtime Generation Startup Timing Unavailable'),
    );
    expect(messages.single, isNot(contains('Total Duration:')));
  });

  test('a throwing log observer does not interrupt timing completion', () {
    XmaxLogger.setSink((_, _) => throw StateError('observer failed'));
    final timing = RealtimeTiming()..finishFirstFrame();
    expect(timing.finish, returnsNormally);
    expect(
      () => RealtimeTiming().finishFailure(StateError('startup failed')),
      returnsNormally,
    );
  });

  test('reset discards prior phases when reusing an existing connection', () {
    var now = 0;
    final timing = RealtimeTiming(now: () => now);
    timing.beginSessionCreation();
    timing.finishSessionCreation();
    timing.beginRoomJoin();
    timing.finishRoomJoin();
    timing.beginLocalPublication();
    timing.finishLocalPublication();
    timing.beginSignal();
    timing.finishFirstFrame();
    timing.finish();
    messages.clear();

    now = 2000;
    timing.reset();
    timing.beginSignal();
    now = 2500;
    timing.finishFirstFrame();
    timing.finish();
    expect(messages.single, contains('Total Duration: 0.5 ms'));
    expect(messages.single, contains('Session Creation: —'));
    expect(messages.single, contains('RTC Room Join: —'));
    expect(messages.single, contains('Local Stream Publication: —'));
    expect(messages.single, contains('First Frame Arrival: 0.5 ms'));
  });

  test(
    'reversed phase timestamps are unavailable rather than clamped to zero',
    () {
      var now = 1000;
      final timing = RealtimeTiming(now: () => now)..beginLocalPublication();
      now = 500;
      timing.finishLocalPublication();
      now = 2000;
      timing.beginSignal();
      timing.finishFirstFrame();
      timing.finish();
      expect(messages.single, contains('Local Stream Publication: —'));
    },
  );
}

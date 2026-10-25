//
//  RealtimeTiming.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';
import '../../foundation/logging/XmaxLogger.dart';
import '../../foundation/logging/XmaxLoggerOption.dart';

/// Records generation startup durations without controlling lifecycle state.
final class RealtimeTiming {

  /// Creates a startup duration recorder and records its start time.
  ///
  /// Parameters:
  /// - [now]: The monotonic microsecond clock; defaults to the process clock.
  RealtimeTiming({
    int Function()? now,
  }) : _now = now ?? _readClock {
    _startedAt = _now();
  }

  /// The monotonic clock used to measure elapsed time.
  static final _clock = Stopwatch()..start();

  /// Reads the process monotonic clock, in microseconds.
  ///
  /// Returns elapsed process clock microseconds.
  static int _readClock() => _clock.elapsedMicroseconds;

  /// The clock function returning monotonic microseconds.
  final int Function() _now;

  /// The generation startup time, in monotonic microseconds.
  late int _startedAt;

  /// The session creation start time, in monotonic microseconds.
  int? _sessionStart;

  /// The session creation completion time, in monotonic microseconds.
  int? _sessionEnd;

  /// The RTC join start time, in monotonic microseconds.
  int? _roomStart;

  /// The RTC join completion time, in monotonic microseconds.
  int? _roomEnd;

  /// The local stream publication start time, in monotonic microseconds.
  int? _publicationStart;

  /// The local stream publication completion time, in monotonic microseconds.
  int? _publicationEnd;

  /// The generation signaling start time, in monotonic microseconds.
  int? _signalStart;

  /// The first remote frame readiness time, in monotonic microseconds.
  int? _firstFrameAt;

  /// Whether this startup attempt has already been finalized.
  bool _finished = false;

  /// Starts a new admitted startup attempt without retaining earlier phase timestamps.
  void reset() {
    _startedAt = _now();
    _sessionStart = null;
    _sessionEnd = null;
    _roomStart = null;
    _roomEnd = null;
    _publicationStart = null;
    _publicationEnd = null;
    _signalStart = null;
    _firstFrameAt = null;
    _finished = false;
  }

  /// Records the session creation start time.
  void beginSessionCreation() => _sessionStart = _now();

  /// Records the session creation completion time.
  void finishSessionCreation() => _sessionEnd = _now();

  /// Records the RTC join start time.
  void beginRoomJoin() => _roomStart = _now();

  /// Records the RTC join completion time.
  void finishRoomJoin() => _roomEnd = _now();

  /// Records the start of local stream publication configuration.
  void beginLocalPublication() => _publicationStart = _now();

  /// Records when local stream publication configuration returns successfully.
  void finishLocalPublication() => _publicationEnd = _now();

  /// Records the start of generation signaling.
  void beginSignal() => _signalStart = _now();

  /// Records when the first remote result frame becomes ready for display.
  void finishFirstFrame() => _firstFrameAt = _now();

  /// Finalizes startup timing and logs phase durations.
  void finish() {
    if (_finished) {
      return;
    }

    _finished = true;

    if (_firstFrameAt == null) {
      _write(['实时生成启动耗时不可用 (Realtime Generation Startup Timing Unavailable)']);
      return;
    }

    final readyAt = _now();
    final lines = <String>[
      '实时生成启动耗时 (Realtime Generation Startup Timing)',
      '└─ ${_label('总耗时：', 'Total Duration: ')}${_duration(_startedAt, readyAt)}',
      ..._stageDetails(),
    ];
    _write(lines);
  }

  /// Finalizes a failed startup attempt; deliberate cancellation does not emit a failure
  /// diagnostic.
  ///
  /// Parameters:
  /// - [error]: The operation error.
  void finishFailure(
    Object error,
  ) {
    if (_finished) {
      return;
    }

    _finished = true;

    final failure = XmaxError.from(error);

    if (failure.code == XmaxErrorCode.cancelled) {
      return;
    }

    final failedAt = _now();
    final lines = <String>[
      '实时生成启动未完成耗时 (Incomplete Realtime Generation Startup Timing)',
      '├─ ${_label('已耗时：', 'Elapsed Time: ')}${_duration(_startedAt, failedAt)}',
      ..._stageDetails(failureAt: failedAt),
      '├─ ${_label('停留阶段：', 'Current Stage: ')}$_pendingStage',
      '└─ ${_label('失败原因：', 'Failure Reason: ')}${failure.message}',
    ];
    _write(lines);
  }

  /// Formats the four startup phases, including unavailable and submillisecond durations.
  ///
  /// [failureAt] closes unfinished phases at the failure time when provided.
  ///
  /// Returns indented stage lines in the configured log language.
  List<String> _stageDetails({
    int? failureAt,
  }) {
    final stages = <(String, int?, int?)>[
      (
        _label(
          '创建会话：',
          'Session Creation: ',
        ),
        _sessionStart,
        _sessionEnd,
      ),
      (
        _label(
          'RTC 进房：',
          'RTC Room Join: ',
        ),
        _roomStart,
        _roomEnd,
      ),
      (
        _label(
          '发布本地流：',
          'Local Stream Publication: ',
        ),
        _publicationStart,
        _publicationEnd,
      ),
      (
        _label(
          '首帧到达：',
          'First Frame Arrival: ',
        ),
        _signalStart,
        _firstFrameAt,
      ),
    ];
    final indent = failureAt == null ? '   ' : '│  ';
    final lines = <String>[];

    for (var index = 0; index < stages.length; index++) {
      final (label, start, end) = stages[index];
      final branch = index == stages.length - 1 ? '└─' : '├─';
      lines.add('$indent$branch $label${_duration(start, end ?? failureAt)}');
    }

    return lines;
  }

  /// The pending startup phase name.
  String get _pendingStage {
    if (_firstFrameAt != null) {
      return _label(
        '首帧已就绪，正在完成启动',
        'First Frame Ready, Completing Startup',
      );
    }

    if (_signalStart != null) {
      return _label(
        '等待首帧到达',
        'Waiting for First Frame',
      );
    }

    if (_publicationEnd != null) {
      return _label(
        '准备生成',
        'Preparing Generation',
      );
    }

    if (_publicationStart != null) {
      return _label(
        '发布本地流',
        'Publishing Local Stream',
      );
    }

    if (_roomEnd != null) {
      return _label(
        '准备发布本地流',
        'Preparing Local Stream Publication',
      );
    }

    if (_roomStart != null) {
      return _label(
        'RTC 进房',
        'Joining RTC Room',
      );
    }

    if (_sessionEnd != null) {
      return _label(
        'RTC 连接准备',
        'RTC Connection Setup',
      );
    }

    if (_sessionStart != null) {
      return _label(
        '创建会话',
        'Creating Session',
      );
    }

    return _label(
      '调用与本地准备',
      'Invocation and Local Preparation',
    );
  }

  /// Selects a metric label for the configured log language.
  ///
  /// Parameters:
  /// - [chinese]: The label for the China environment.
  /// - [english]: The label for the global environment.
  ///
  /// Returns the metric label in the configured log language.
  static String _label(
    String chinese,
    String english,
  ) => XmaxLogger.localized(
    chinese,
    english,
  );

  /// Formats an elapsed duration in milliseconds, using a placeholder for missing timestamps.
  ///
  /// Parameters:
  /// - [start]: The interval start time, in microseconds.
  /// - [end]: The interval end time, in microseconds.
  ///
  /// Returns milliseconds as text, or an em dash for missing or reversed timestamps.
  static String _duration(
    int? start,
    int? end,
  ) => start == null || end == null || end < start
      ? '—'
      : '${((end - start) / 1000).toStringAsFixed(1)} ms';

  /// Writes formatted logs using the current logging options.
  ///
  /// Parameters:
  /// - [lines]: The ordered startup duration log lines.
  static void _write(
    List<String> lines,
  ) {
    try {
      XmaxLogger.info(
        category: XmaxLoggerCategory.realtime,
        option: XmaxLoggerOption.performance,
        message: lines.join('\n'),
      );
    } catch (_) {
      // Timing diagnostics must not interrupt generation.
    }
  }
}

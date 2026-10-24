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
  late final int _startedAt;

  /// The connection start time, in monotonic microseconds.
  int? _connectionStart;

  /// The connection completion time, in monotonic microseconds.
  int? _connectionEnd;

  /// The session creation start time, in monotonic microseconds.
  int? _sessionStart;

  /// The session creation completion time, in monotonic microseconds.
  int? _sessionEnd;

  /// The RTC join start time, in monotonic microseconds.
  int? _roomStart;

  /// The RTC join completion time, in monotonic microseconds.
  int? _roomEnd;

  /// The signaling and result-confirmation start time, in monotonic microseconds.
  int? _signalStart;

  /// The result stream confirmation time, in monotonic microseconds.
  int? _streamConfirmed;

  /// Whether this startup attempt has already been finalized.
  bool _finished = false;

  /// Records the connection start time.
  void beginConnection() => _connectionStart = _now();

  /// Records the connection completion time.
  void finishConnection() => _connectionEnd = _now();

  /// Records the session creation start time.
  void beginSessionCreation() => _sessionStart = _now();

  /// Records the session creation completion time.
  void finishSessionCreation() => _sessionEnd = _now();

  /// Records the RTC join start time.
  void beginRoomJoin() => _roomStart = _now();

  /// Records the RTC join completion time.
  void finishRoomJoin() => _roomEnd = _now();

  /// Records the start of signaling and result confirmation.
  void beginSignal() => _signalStart = _now();

  /// Records the result stream confirmation time.
  void confirmRemoteStream() => _streamConfirmed = _now();

  /// Finalizes startup timing and logs phase durations.
  void finish() {
    if (_finished) {
      return;
    }

    _finished = true;

    final readyAt = _now();
    final lines = <String>[
      '实时生成启动耗时 (Realtime Generation Startup Timing)',
      '├─ ${_label('总耗时：', 'Total Duration: ')}${_duration(_startedAt, readyAt)}',
    ];

    if (_connectionStart != null && _connectionEnd != null) {
      lines.add(
        '├─ ${_label('实时连接：', 'Realtime Connection: ')}${_duration(_connectionStart, _connectionEnd)}',
      );

      final details = <String>[];

      _detail(
        details,
        _label(
          '服务端会话创建：',
          'Server Session Creation: ',
        ),
        _sessionStart,
        _sessionEnd,
      );
      _detail(
        details,
        _label(
          'RTC 房间连接：',
          'RTC Room Connection: ',
        ),
        _roomStart,
        _roomEnd,
      );
      for (var index = 0; index < details.length; index++) {
        lines.add(
          '│  ${index == details.length - 1 ? '└─' : '├─'} ${details[index]}',
        );
      }
    }

    lines.add(
      '├─ ${_label('等待生成结果流确认：', 'Waiting for Remote Stream: ')}${_duration(_signalStart, _streamConfirmed)}',
    );
    lines.add(
      '└─ ${_label('结果流确认到首帧就绪：', 'First Frame Ready: ')}${_duration(_streamConfirmed, readyAt)}',
    );
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
      '├─ ${_label('停留阶段：', 'Current Stage: ')}$_pendingStage',
    ];
    final details = <String>[];

    _detail(
      details,
      _label(
        '服务端会话创建：',
        'Server Session Creation: ',
      ),
      _sessionStart,
      _sessionEnd ?? failedAt,
    );
    _detail(
      details,
      _label(
        'RTC 房间连接：',
        'RTC Room Connection: ',
      ),
      _roomStart,
      _roomEnd ?? failedAt,
    );
    _detail(
      details,
      _label(
        '实时连接：',
        'Realtime Connection: ',
      ),
      _connectionStart,
      _connectionEnd ?? failedAt,
    );
    _detail(
      details,
      _label(
        '等待生成结果流确认：',
        'Waiting for Result Stream Confirmation: ',
      ),
      _signalStart,
      _streamConfirmed ?? failedAt,
    );
    _detail(
      details,
      _label(
        '结果流确认后等待首帧：',
        'Waiting for First Frame After Result Stream Confirmation: ',
      ),
      _streamConfirmed,
      failedAt,
    );
    lines.addAll(details.map((
      detail,
    ) => '├─ $detail'));
    lines.add('└─ ${_label('失败原因：', 'Failure Reason: ')}${failure.message}');
    _write(lines);
  }

  /// The pending startup phase name.
  String get _pendingStage {
    if (_streamConfirmed != null) {
      return _label(
        '结果流已确认，正在等待首帧',
        'Result Stream Confirmed, Waiting for First Frame',
      );
    }

    if (_signalStart != null) {
      return _label(
        '正在等待生成结果流确认',
        'Waiting for Result Stream Confirmation',
      );
    }

    if (_connectionEnd != null) {
      return _label(
        '连接完成后准备生成',
        'Preparing Generation After Connection',
      );
    }

    if (_roomStart != null && _roomEnd == null) {
      return _label(
        '正在连接 RTC 房间',
        'Connecting to RTC Room',
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
        '服务端会话创建',
        'Server Session Creation',
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
  /// Returns milliseconds as text, or -- if either timestamp is missing.
  static String _duration(
    int? start,
    int? end,
  ) => start == null || end == null
      ? '--'
      : '${((end - start) / 1000).clamp(0, double.infinity).toStringAsFixed(1)} ms';

  /// Appends valid duration metrics lasting at least one millisecond.
  ///
  /// Parameters:
  /// - [lines]: The ordered log lines.
  /// - [label]: The metric's display label.
  /// - [start]: The monotonic start time in microseconds; null omits this metric.
  /// - [end]: The monotonic end time in microseconds; null omits this metric.
  static void _detail(
    List<String> lines,
    String label,
    int? start,
    int? end,
  ) {
    if (start != null && end != null && end - start >= 1000) {
      lines.add('$label${_duration(start, end)}');
    }
  }

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

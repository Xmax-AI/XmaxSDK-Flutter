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

/// 记录单次生成启动各阶段的耗时，不参与业务状态控制。
final class RealtimeTiming {

  /// 创建启动计时器，并立即记录起点。
  ///
  /// - [now]：返回单调时间微秒值的函数；默认使用进程单调时钟。
  RealtimeTiming({
    int Function()? now,
  }) : _now = now ?? _readClock {
    _startedAt = _now();
  }

  /// 计算相对耗时的单调时钟。
  static final _clock = Stopwatch()..start();

  /// 读取进程内单调时钟，单位为微秒。
  ///
  /// 返回进程单调时钟经过的微秒数。
  static int _readClock() => _clock.elapsedMicroseconds;

  /// 返回单调时间微秒值的时钟函数。
  final int Function() _now;

  /// 整个生成启动过程的起始单调时间，单位为微秒。
  late final int _startedAt;

  /// 开始连接时的单调时钟时间，单位为微秒。
  int? _connectionStart;

  /// 连接完成时的单调时钟时间，单位为微秒。
  int? _connectionEnd;

  /// 开始创建云端会话时的单调时钟时间，单位为微秒。
  int? _sessionStart;

  /// 云端会话创建完成时的单调时钟时间，单位为微秒。
  int? _sessionEnd;

  /// 开始加入 RTC 房间时的单调时钟时间，单位为微秒。
  int? _roomStart;

  /// 加入 RTC 房间完成时的单调时钟时间，单位为微秒。
  int? _roomEnd;

  /// 开始等待启动信令发送和结果流确认时的单调时钟时间，单位为微秒。
  int? _signalStart;

  /// 结果流确认完成时的单调时钟时间，单位为微秒。
  int? _streamConfirmed;

  /// 当前启动计时是否已结束，避免重复输出。
  bool _finished = false;

  /// 记录连接阶段的开始时间。
  void beginConnection() => _connectionStart = _now();

  /// 记录连接阶段的结束时间。
  void finishConnection() => _connectionEnd = _now();

  /// 记录云端会话创建的开始时间。
  void beginSessionCreation() => _sessionStart = _now();

  /// 记录云端会话创建的结束时间。
  void finishSessionCreation() => _sessionEnd = _now();

  /// 记录 RTC 入房阶段的开始时间。
  void beginRoomJoin() => _roomStart = _now();

  /// 记录 RTC 入房阶段的结束时间。
  void finishRoomJoin() => _roomEnd = _now();

  /// 记录开始等待生成信令和结果确认的时间。
  void beginSignal() => _signalStart = _now();

  /// 记录结果流确认的时间。
  void confirmRemoteStream() => _streamConfirmed = _now();

  /// 结束当前计时并输出各阶段耗时。
  void finish() {
    if (_finished) return;

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
        _label('服务端会话创建：', 'Server Session Creation: '),
        _sessionStart,
        _sessionEnd,
      );
      _detail(
        details,
        _label('RTC 房间连接：', 'RTC Room Connection: '),
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

  /// 结束本次启动计时并记录失败阶段；主动取消不输出失败诊断。
  ///
  /// - [error]：本次操作的错误。
  void finishFailure(
    Object error,
  ) {
    if (_finished) return;

    _finished = true;

    final failure = XmaxError.from(error);

    if (failure.code == XmaxErrorCode.cancelled) return;

    final failedAt = _now();
    final lines = <String>[
      '实时生成启动未完成耗时 (Incomplete Realtime Generation Startup Timing)',
      '├─ ${_label('已耗时：', 'Elapsed Time: ')}${_duration(_startedAt, failedAt)}',
      '├─ ${_label('停留阶段：', 'Current Stage: ')}$_pendingStage',
    ];
    final details = <String>[];

    _detail(
      details,
      _label('服务端会话创建：', 'Server Session Creation: '),
      _sessionStart,
      _sessionEnd ?? failedAt,
    );
    _detail(
      details,
      _label('RTC 房间连接：', 'RTC Room Connection: '),
      _roomStart,
      _roomEnd ?? failedAt,
    );
    _detail(
      details,
      _label('实时连接：', 'Realtime Connection: '),
      _connectionStart,
      _connectionEnd ?? failedAt,
    );
    _detail(
      details,
      _label('等待生成结果流确认：', 'Waiting for Result Stream Confirmation: '),
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
    lines.addAll(details.map((detail) => '├─ $detail'));
    lines.add('└─ ${_label('失败原因：', 'Failure Reason: ')}${failure.message}');
    _write(lines);
  }

  /// 本次生成启动尚未完成的阶段名称。
  String get _pendingStage {
    if (_streamConfirmed != null) {
      return _label(
        '结果流已确认，正在等待首帧',
        'Result Stream Confirmed, Waiting for First Frame',
      );
    }

    if (_signalStart != null) {
      return _label('正在等待生成结果流确认', 'Waiting for Result Stream Confirmation');
    }

    if (_connectionEnd != null) {
      return _label('连接完成后准备生成', 'Preparing Generation After Connection');
    }

    if (_roomStart != null && _roomEnd == null) {
      return _label('正在连接 RTC 房间', 'Connecting to RTC Room');
    }

    if (_sessionEnd != null) return _label('RTC 连接准备', 'RTC Connection Setup');

    if (_sessionStart != null) {
      return _label('服务端会话创建', 'Server Session Creation');
    }

    return _label('调用与本地准备', 'Invocation and Local Preparation');
  }

  /// 按当前日志环境选择指标名称。
  ///
  /// - [chinese]：国内环境使用的中文文本。
  /// - [english]：海外环境使用的英文文本。
  ///
  /// 返回当前日志语言对应的指标名称。
  static String _label(
    String chinese,
    String english,
  ) => XmaxLogger.localized(chinese, english);

  /// 将两个单调时钟时刻格式化为毫秒耗时；缺失时输出占位符。
  ///
  /// - [start]：耗时区间的开始时刻，单位为微秒。
  /// - [end]：耗时区间的结束时刻，单位为微秒。
  ///
  /// 返回以毫秒为单位的耗时文本；时刻缺失时为 --。
  static String _duration(
    int? start,
    int? end,
  ) => start == null || end == null
      ? '--'
      : '${((end - start) / 1000).clamp(0, double.infinity).toStringAsFixed(1)} ms';

  /// 仅将至少持续一毫秒的有效耗时指标加入日志。
  ///
  /// - [lines]：需要按顺序输出的日志行。
  /// - [label]：日志指标的显示名称。
  /// - [start]：指标开始的单调时钟微秒值；为空时不输出该项。
  /// - [end]：指标结束的单调时钟微秒值；为空时不输出该项。
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

  /// 按当前日志选项输出已格式化的日志。
  ///
  /// - [lines]：需要顺序输出的启动阶段耗时日志行。
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
      // 记录启动耗时失败不能影响正常生成。
    }
  }
}

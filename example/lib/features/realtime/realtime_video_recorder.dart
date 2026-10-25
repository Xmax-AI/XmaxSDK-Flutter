import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:xmax_sdk/xmax_sdk.dart';

enum RealtimeRecordingState { idle, preparing, recording, saving }

/// Encodes remote SDK packets off the UI isolate and saves the completed MP4 to the gallery.
final class RealtimeVideoRecorder extends ChangeNotifier {
  RealtimeVideoRecorder({
    required this.manager,
    required this.onError,
    required this.onSaved,
  }) {
    _owner = this;
    channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (call.method == 'error' &&
          arguments is Map &&
          arguments['id'] == _id) {
        await _fail(arguments['message'] ?? 'record.encoderFailed');
      }
    });
  }

  static const channel = MethodChannel('ai.xmax.xlab/recording');
  static RealtimeVideoRecorder? _owner;
  static int _sequence = 0;
  String _id = '';
  final XmaxRealtimeManaging manager;
  final void Function(Object error) onError;
  final VoidCallback onSaved;
  RealtimeRecordingState state = RealtimeRecordingState.idle;
  Future<void>? _operation;
  bool _disposed = false;
  bool _accepting = false;
  bool _stopRequested = false;
  Future<void>? _saving;

  Future<T?> _native<T>(
    String method, [
    Map<String, Object?> data = const {},
  ]) => channel.invokeMethod<T>(method, {'id': _id, ...data});

  bool get isBusy =>
      state == RealtimeRecordingState.preparing ||
      state == RealtimeRecordingState.saving;

  Future<void> toggle() async {
    if (_disposed || isBusy) return;
    if (state == RealtimeRecordingState.recording) {
      await stop();
    } else {
      final operation = _start();
      _operation = operation;
      await operation;
    }
  }

  Future<void> _start() async {
    _id = '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    _stopRequested = false;
    _setState(RealtimeRecordingState.preparing);
    try {
      await _native<void>('start');
      if (_disposed || _stopRequested) {
        await _native<void>('cancel');
        _setState(RealtimeRecordingState.idle);
        return;
      }
      _accepting = true;
      await manager.setRemoteMediaFrameListener(_append);
      if (_disposed || _stopRequested || !_accepting) {
        _accepting = false;
        await manager.setRemoteMediaFrameListener(null);
        await _native<void>('cancel');
        _setState(RealtimeRecordingState.idle);
        return;
      }
      _setState(RealtimeRecordingState.recording);
    } catch (error) {
      await _fail(error);
    }
  }

  Future<void> _append(RealtimeMediaFrame frame) async {
    if (!_accepting || _disposed) return;
    final content = frame.content;
    final packet = <String, Object?>{
      'streamID': frame.streamID,
      'ptsUs': frame.presentationTimeStamp.inMicroseconds,
      'discontinuous': frame.isDiscontinuous,
      if (content is RealtimeVideoFrame) ...{
        'video': true,
        'data': content.data,
        'width': content.width,
        'height': content.height,
        'rotation': content.rotation,
      },
      if (content is RealtimeAudioFrame) ...{
        'video': false,
        'data': content.data,
        'sampleRate': content.sampleRate,
        'channels': content.channels,
        'samplesPerChannel': content.samplesPerChannel,
      },
    };
    try {
      await _native<void>('append', packet);
    } catch (error) {
      // Do not await listener removal from inside the listener's delivery loop.
      unawaited(_fail(error));
    }
  }

  Future<void> stop() async {
    _stopRequested = true;
    if (state == RealtimeRecordingState.preparing) {
      await _operation;
    }
    if (state == RealtimeRecordingState.saving) {
      await _saving;
      return;
    }
    if (state != RealtimeRecordingState.recording) return;
    final saving = _stop();
    _saving = saving;
    await saving;
  }

  Future<void> _stop() async {
    _accepting = false;
    _setState(RealtimeRecordingState.saving);
    try {
      await manager.setRemoteMediaFrameListener(null);
      await _native<String>('stop');
      if (!_disposed) onSaved();
    } catch (error) {
      if (!_disposed) onError(error);
    } finally {
      _setState(RealtimeRecordingState.idle);
    }
  }

  Future<void> _fail(Object error) async {
    if (!_accepting && state != RealtimeRecordingState.preparing) return;
    _accepting = false;
    _setState(RealtimeRecordingState.saving);
    try {
      await manager.setRemoteMediaFrameListener(null);
      await _native<void>('cancel');
    } catch (_) {
      // Preserve the original recording failure.
    }
    _setState(RealtimeRecordingState.idle);
    if (!_disposed) onError(error);
  }

  void _setState(RealtimeRecordingState value) {
    state = value;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _accepting = false;
    _stopRequested = true;
    if (identical(_owner, this)) {
      _owner = null;
      channel.setMethodCallHandler(null);
    }
    unawaited(manager.setRemoteMediaFrameListener(null).catchError((_) {}));
    unawaited(_native<void>('cancel').catchError((_) {}));
    super.dispose();
  }
}

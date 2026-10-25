import 'dart:async';

import 'package:flutter/foundation.dart';

/// Retains volume and mute intent while serializing slider writes.
class RealtimeAudioControls extends ChangeNotifier {
  RealtimeAudioControls({
    required this.readVolume,
    required this.writeVolume,
    required this.onError,
  });

  final Future<double> Function() readVolume;
  final Future<void> Function(double) writeVolume;
  final ValueChanged<Object> onError;
  double _value = 0;
  double _applied = 0;
  double _audibleValue = 1;
  double? _pending;
  Future<void>? _writing;
  int _revision = 0;
  bool _disposed = false;

  double get value => _value;
  bool get isMuted => _value == 0;
  Future<void> get settled async {
    while (_writing != null) {
      await _writing;
    }
  }

  Future<bool> refresh() async {
    final revision = _revision;
    await settled;
    if (!_isCurrent(revision)) return false;
    try {
      final volume = await readVolume();
      if (!_isCurrent(revision)) return false;
      _value = _applied = volume;
      if (volume > 0) _audibleValue = volume;
      notifyListeners();
      return true;
    } catch (error) {
      if (_isCurrent(revision)) onError(error);
      return false;
    }
  }

  Future<void> setVolume(double volume) {
    if (_disposed) return Future<void>.value();
    final value = (volume.clamp(0, 1) * 100).round() / 100;
    _value = value;
    if (value > 0) _audibleValue = value;
    _pending = value;
    notifyListeners();
    return _startWriting();
  }

  Future<void> toggleMute() => setVolume(isMuted ? _audibleValue : 0);

  void reset(double volume) {
    _revision++;
    _pending = null;
    _value = _applied = volume;
    _audibleValue = volume > 0 ? volume : 1;
    if (!_disposed) notifyListeners();
  }

  Future<void> _startWriting() {
    if (_writing case final pending?) return pending;
    final task = _flush(_revision);
    _writing = task;
    return task.whenComplete(() {
      _writing = null;
      if (!_disposed && _pending != null) unawaited(_startWriting());
    });
  }

  Future<void> _flush(int revision) async {
    while (_isCurrent(revision) && _pending != null) {
      final value = _pending!;
      _pending = null;
      try {
        await writeVolume(value);
        if (_isCurrent(revision)) _applied = value;
      } catch (error) {
        if (!_isCurrent(revision)) return;
        if (_pending == null) {
          _value = _applied;
          notifyListeners();
        }
        onError(error);
      }
    }
  }

  bool _isCurrent(int revision) => !_disposed && revision == _revision;

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _pending = null;
    super.dispose();
  }
}

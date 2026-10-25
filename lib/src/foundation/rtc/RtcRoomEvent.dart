//
//  RtcRoomEvent.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeNetworkQuality.dart';
import '../../service/realtime/RealtimePerformanceAlarm.dart';
import '../errors/XmaxError.dart';
import 'RemoteStream.dart';
import 'VideoStatistics.dart';

/// A vendor-independent RTC publication, first-frame, failure, or quality event.
sealed class RtcRoomEvent {

  /// Creates a room event.
  const RtcRoomEvent();
}

/// A remote user's video publication change.
final class RtcRoomVideoPublication extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomVideoPublication({
    required this.stream,
    required this.published,
  });

  /// The remote video stream.
  final RemoteStream stream;

  /// Whether the remote video is available.
  final bool published;
}

/// A remote user's audio publication change.
final class RtcRoomAudioPublication extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomAudioPublication({
    required this.stream,
    required this.published,
  });

  /// The remote audio stream.
  final RemoteStream stream;

  /// Whether the remote audio is available.
  final bool published;
}

/// The first valid decoded video frame for a remote stream.
final class RtcRoomFirstVideoDecoded extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomFirstVideoDecoded({
    required this.stream,
  });

  /// The decoded remote stream.
  final RemoteStream stream;
}

/// The first displayed native video frame for a remote stream.
final class RtcRoomFirstVideoRendered extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomFirstVideoRendered({
    required this.stream,
  });

  /// The rendered remote stream.
  final RemoteStream stream;
}

/// A room connection or signaling failure.
final class RtcRoomFailure extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomFailure({
    required this.error,
  });

  /// The normalized room failure.
  final XmaxError error;
}

/// An uplink and downlink network quality sample.
final class RtcRoomNetworkQuality extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomNetworkQuality({
    required this.quality,
  });

  /// The directional network quality.
  final RealtimeNetworkQuality quality;
}

/// A local encoding and sending statistics sample.
final class RtcRoomUplinkVideoStatistics extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomUplinkVideoStatistics({
    required this.statistics,
  });

  /// The outgoing video measurements.
  final UplinkVideoStatistics statistics;
}

/// A remote receiving and rendering statistics sample.
final class RtcRoomDownlinkVideoStatistics extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomDownlinkVideoStatistics({
    required this.statistics,
  });

  /// The incoming video measurements.
  final DownlinkVideoStatistics statistics;
}

/// An encoding performance limitation or recovery.
final class RtcRoomPerformanceAlarm extends RtcRoomEvent {

  /// Creates the room event.
  const RtcRoomPerformanceAlarm({
    required this.alarm,
  });

  /// The performance status and optional format suggestion.
  final RealtimePerformanceAlarm alarm;
}

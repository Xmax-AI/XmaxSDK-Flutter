//
//  RealtimePerformanceAlarm.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'RealtimeVideoFormat.dart';

/// A performance limitation or recovery state for realtime media transport.
enum RealtimePerformanceStatus {

  /// Device or transport performance is limited.
  limited('Limited'),

  /// Device or transport performance has recovered.
  recovered('Recovered');

  /// Defines a performance status identifier.
  const RealtimePerformanceStatus(
    this.value,
  );

  /// The serialized value.
  final String value;
}

/// A performance status and optional suggested format, not an applied capture configuration.
final class RealtimePerformanceAlarm {

  /// Creates a performance alarm and suggested video format.
  const RealtimePerformanceAlarm({
    required this.status,
    this.suggestedVideoFormat,
  });

  /// The performance limitation or recovery state for this event.
  final RealtimePerformanceStatus status;

  /// The suggested video format, when provided by the performance event.
  final RealtimeVideoFormat? suggestedVideoFormat;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimePerformanceAlarm &&
          status == other.status &&
          suggestedVideoFormat == other.suggestedVideoFormat;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    status,
    suggestedVideoFormat,
  );
}

/// A listener receiving performance status and any suggested format.
///
/// Parameters:
/// - [alarm]: The performance limitation or recovery event.
typedef RealtimePerformanceAlarmListener =
    void Function(
      RealtimePerformanceAlarm alarm,
    );

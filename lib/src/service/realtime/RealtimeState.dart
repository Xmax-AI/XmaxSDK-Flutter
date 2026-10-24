//
//  RealtimeState.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../foundation/errors/XmaxError.dart';

/// The reason for entering a realtime state.
final class RealtimeReason {

  /// Creates an internal state reason.
  const RealtimeReason._(
    this._kind,
    this.error,
  );

  /// An explicit stop or normal resource release.
  static const normal = RealtimeReason._(
    'normal',
    null,
  );

  /// A display orientation change requiring generation reconfiguration.
  static const orientationChanged = RealtimeReason._(
    'orientationChanged',
    null,
  );

  /// Creates a failure reason.
  ///
  /// Parameters:
  /// - [error]: The SDK error terminating the state, exposed through [RealtimeReason.error].
  factory RealtimeReason.failure(
    XmaxError error,
  ) => RealtimeReason._(
    'failure',
    error,
  );

  /// The internal reason category.
  final String _kind;

  /// The SDK error for a failure reason, or null for other reasons.
  final XmaxError? error;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeReason && _kind == other._kind && error == other.error;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    _kind,
    error,
  );
}

/// A realtime connection lifecycle state.
enum RealtimeConnectionState {

  /// No local media stream is available.
  idle('Idle'),

  /// Local media is preparing; cameras wait for a captured frame and a mounted preview.
  preparing('Preparing'),

  /// Local media is ready for preview, connection, and generation.
  ready('Ready'),

  /// A server session is being created and local video joined and published to RTC.
  connecting('Connecting'),

  /// Realtime is connected without an active generation task.
  connected('Connected'),

  /// The realtime connection is generating.
  generating('Generating'),

  /// Generation, the RTC room, and the server session are being closed.
  disconnecting('Disconnecting');

  /// Defines a realtime connection state identifier.
  const RealtimeConnectionState(
    this.value,
  );

  /// The serialized value.
  final String value;
}

/// A snapshot of the realtime lifecycle state.
final class RealtimeState {

  /// Creates a realtime state snapshot.
  const RealtimeState({
    required this.connectionState,
    this.sessionID,
    this.taskID,
    this.reason,
  });

  /// The current connection state.
  final RealtimeConnectionState connectionState;

  /// The current or most recent server session identifier.
  final String? sessionID;

  /// The current generation task identifier.
  final String? taskID;

  /// The reason for this state, cleared when a new operation begins.
  final RealtimeReason? reason;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeState &&
          connectionState == other.connectionState &&
          sessionID == other.sessionID &&
          taskID == other.taskID &&
          reason == other.reason;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    connectionState,
    sessionID,
    taskID,
    reason,
  );
}

/// A listener receiving realtime lifecycle snapshots.
///
/// Parameters:
/// - [state]: The current realtime lifecycle state.
typedef RealtimeStateListener =
    void Function(
      RealtimeState state,
    );

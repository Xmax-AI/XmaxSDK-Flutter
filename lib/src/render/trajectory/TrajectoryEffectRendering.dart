//
//  TrajectoryEffectRendering.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'package:flutter/widgets.dart';

/// The identifier of a pointer trail, distinguishing simultaneous trails.
final class TrajectoryID {

  /// Creates a pointer trail identifier.
  TrajectoryID._(
    this.rawValue,
  );

  /// The raw pointer identifier associated with this trail.
  final int rawValue;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is TrajectoryID && rawValue == other.rawValue;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => rawValue.hashCode;
}

/// Trail rendering input containing a pointer identifier, view position, normalized position, and
/// timestamp.
final class TrajectoryPoint {

  /// Creates a trail position and sampling time record.
  const TrajectoryPoint({
    required this.id,
    required this.location,
    required this.normalizedLocation,
    required this.timestamp,
  });

  /// The trail identifier associated with the current pointer.
  final TrajectoryID id;

  /// The pointer position within the view, in logical pixels.
  final Offset location;

  /// The view-normalized pointer position, before conversion to media coordinates using the video
  /// crop region.
  final Offset normalizedLocation;

  /// The pointer's elapsed time in the current sampling cycle.
  final Duration timestamp;
}

/// An interface for custom trail effects, handling pointer events and providing an overlay view.
abstract interface class TrajectoryEffectRendering {

  /// The overlay view displaying the current trail effects.
  Widget get view;

  /// Creates or replaces a pointer's trail and begins rendering its effects.
  ///
  /// Parameters:
  /// - [points]: The sampled interaction points, preserving their order.
  void renderBegan(
    List<TrajectoryPoint> points,
  );

  /// Updates a pointer's trail position, creating the trail if it does not exist.
  ///
  /// Parameters:
  /// - [points]: The sampled interaction points, preserving their order.
  void renderMoved(
    List<TrajectoryPoint> points,
  );

  /// Ends input for the specified trails, allowing them to fade according to the renderer policy.
  ///
  /// Parameters:
  /// - [identifiers]: The identifiers of trails whose input should end.
  void renderEnded(
    List<TrajectoryID> identifiers,
  );

  /// Clears all currently displayed trails.
  void reset();
}

/// Creates a trail identifier from a raw pointer identifier.
///
/// Parameters:
/// - [rawValue]: The serializable raw value.
///
/// Returns a trail identifier wrapping the raw pointer identifier.
TrajectoryID createTrajectoryID(
  int rawValue,
) => TrajectoryID._(rawValue);

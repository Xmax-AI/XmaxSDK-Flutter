//
//  RealtimeNetworkQuality.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// A network quality measurement for an uplink or downlink RTC connection.
enum RealtimeNetworkQualityLevel {

  /// No valid network quality measurement is available.
  unknown('Unknown'),

  /// Excellent network quality.
  excellent('Excellent'),

  /// Good network quality.
  good('Good'),

  /// Fair network quality.
  poor('Poor'),

  /// Poor network quality.
  bad('Bad'),

  /// Very poor network quality.
  veryBad('VeryBad'),

  /// The network connection is down.
  down('Down');

  /// Defines a network quality identifier.
  const RealtimeNetworkQualityLevel(
    this.value,
  );

  /// The serialized value.
  final String value;
}

/// The uplink and downlink quality from one RTC sample.
final class RealtimeNetworkQuality {

  /// Creates a network quality sample.
  const RealtimeNetworkQuality({
    required this.uplink,
    required this.downlink,
  });

  /// The local video uplink network quality.
  final RealtimeNetworkQualityLevel uplink;

  /// The local video downlink network quality.
  final RealtimeNetworkQualityLevel downlink;

  /// Whether [other] has the same value.
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(
        this,
        other,
      ) ||
      other is RealtimeNetworkQuality &&
          uplink == other.uplink &&
          downlink == other.downlink;

  /// The hash code consistent with value equality.
  @override
  int get hashCode => Object.hash(
    uplink,
    downlink,
  );
}

/// A listener receiving uplink and downlink quality from one sample.
///
/// Parameters:
/// - [quality]: The uplink and downlink measurements from the same sample.
typedef RealtimeNetworkQualityListener =
    void Function(
      RealtimeNetworkQuality quality,
    );

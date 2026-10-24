//
//  QualityConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../core/realtime/RealtimeQualityLevel.dart';
import '../../service/realtime/RealtimeVideoFormat.dart';
import 'QualityVideoFormat.dart';

/// The current connection's fixed media baseline and successfully applied link levels.
final class QualityConfiguration {

  /// Creates a transport configuration snapshot.
  const QualityConfiguration({
    required this.baseline,
    required this.uplinkLevel,
    required this.downlinkLevel,
  });

  /// The media format that remains fixed across transport quality changes.
  final RealtimeVideoFormat baseline;

  /// The successfully applied uplink level.
  final RealtimeQualityLevel uplinkLevel;

  /// The successfully submitted downlink target level.
  final RealtimeQualityLevel downlinkLevel;

  /// The current uplink encoding format.
  RealtimeVideoFormat get uplink => QualityVideoFormat.resolve(
    baseline,
    uplinkLevel,
    downlink: false,
  );

  /// The current downlink target format before applying server dimension alignment constraints.
  RealtimeVideoFormat get downlink => QualityVideoFormat.resolve(
    baseline,
    downlinkLevel,
    downlink: true,
  );
}

/// Candidate levels from one sample; null leaves that direction unchanged.
final class QualityChange {

  /// Creates an uplink and downlink adjustment proposal.
  const QualityChange({
    this.uplink,
    this.downlink,
  });

  /// The proposed uplink level.
  final RealtimeQualityLevel? uplink;

  /// The proposed downlink level.
  final RealtimeQualityLevel? downlink;
}

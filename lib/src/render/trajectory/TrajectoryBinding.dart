//
//  TrajectoryBinding.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../media/interaction/InteractionFrame.dart';

/// Connects a video track's interaction samples to the current task handler.
final class TrajectoryBinding {

  /// Creates a track interaction binding.
  const TrajectoryBinding({
    required this.interactionListener,
  });

  /// The handler receiving interaction samples for the current track.
  final void Function(
    InteractionFrame frame,
  )
  interactionListener;
}

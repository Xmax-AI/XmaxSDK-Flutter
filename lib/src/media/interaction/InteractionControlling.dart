//
//  InteractionControlling.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import '../../service/realtime/RealtimeVideoFormat.dart';
import 'InteractionFrame.dart';

/// An interface for enabling task interaction and submitting input samples.
abstract interface class InteractionControlling {

  /// Enables interaction for the current task and clears pending samples from the previous task.
  ///
  /// Parameters:
  /// - [taskID]: The current generation task identifier.
  /// - [videoFormat]: The video dimensions, frame rate, and encoding settings.
  void startInteraction({
    required String taskID,
    required RealtimeVideoFormat videoFormat,
  });

  /// Stops interaction input and invalidates pending samples.
  void stopInteraction();

  /// Submits view interaction samples; ignored when no generation task is active.
  ///
  /// Parameters:
  /// - [frame]: A view interaction sample.
  void submitInteraction(
    InteractionFrame frame,
  );
}

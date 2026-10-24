//
//  VideoContentMode.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The scaling and cropping mode for video in a view.
enum VideoContentMode {

  /// Fits the entire video while preserving its aspect ratio, leaving unused areas black.
  fit('fit'),

  /// Fills the view while preserving the aspect ratio, cropping video outside its bounds.
  fill('fill');

  /// Defines a video scaling mode identifier.
  const VideoContentMode(
    this.value,
  );

  /// The serialized value.
  final String value;
}

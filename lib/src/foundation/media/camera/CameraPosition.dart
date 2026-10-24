//
//  CameraPosition.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// The position of a device camera.
enum CameraPosition {

  /// The front-facing camera.
  front('front'),

  /// The rear-facing camera.
  back('back');

  /// Defines a camera position identifier.
  const CameraPosition(
    this.value,
  );

  /// The serialized value.
  final String value;
}

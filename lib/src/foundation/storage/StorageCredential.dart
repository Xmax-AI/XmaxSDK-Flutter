//
//  StorageCredential.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// Temporary access keys and a session token for object storage requests.
final class StorageCredential {

  /// Creates temporary object storage credentials.
  const StorageCredential({
    required this.accessKeyID,
    required this.secretAccessKey,
    required this.sessionToken,
  });

  /// The temporary access key identifier.
  final String accessKeyID;

  /// The temporary secret access key; must not be logged.
  final String secretAccessKey;

  /// The temporary credential session token.
  final String sessionToken;
}

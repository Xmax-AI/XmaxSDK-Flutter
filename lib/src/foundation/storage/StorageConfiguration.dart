//
//  StorageConfiguration.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'StorageCredential.dart';

/// The bucket, region, endpoint, and temporary credentials for one object upload.
final class StorageConfiguration {

  /// Creates an object storage connection configuration.
  const StorageConfiguration({
    required this.bucket,
    required this.region,
    required this.endpoint,
    required this.credential,
  });

  /// The object storage bucket name.
  final String bucket;

  /// The object storage region identifier.
  final String region;

  /// The object storage service endpoint.
  final String endpoint;

  /// The temporary credentials used for this transfer.
  final StorageCredential credential;
}

//
//  XmaxUploadedFile.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/// 文件上传结果，包含访问地址、对象键和可用的 ETag。
final class XmaxUploadedFile {

  /// 创建文件上传结果。
  const XmaxUploadedFile._({
    required this.url,
    required this.objectKey,
    this.etag,
  });

  /// 上传对象的访问地址。
  final Uri url;

  /// 对象在存储桶内的完整键，不是本地文件路径。
  final String objectKey;

  /// 对象存储返回的 ETag；服务未返回时为空。
  final String? etag;

  /// 与 [other] 比较类型及 [url]、[objectKey]、[etag] 的值。
  @override
  bool operator ==(
    Object other,
  ) =>
      identical(this, other) ||
      other is XmaxUploadedFile &&
          url == other.url &&
          objectKey == other.objectKey &&
          etag == other.etag;

  /// 与相等判断一致的哈希值。
  @override
  int get hashCode => Object.hash(url, objectKey, etag);
}

/// 将对象访问地址、对象键及 ETag 封装为上传结果。
///
/// - [url]：上传对象的访问地址。
/// - [objectKey]：对象在存储桶内的完整键，不是本地文件路径。
/// - [etag]：对象存储返回的 ETag；服务未返回时为空。
///
/// 返回对象访问地址、对象键和可用的 ETag。
XmaxUploadedFile createXmaxUploadedFile({
  required Uri url,
  required String objectKey,
  String? etag,
}) => XmaxUploadedFile._(url: url, objectKey: objectKey, etag: etag);

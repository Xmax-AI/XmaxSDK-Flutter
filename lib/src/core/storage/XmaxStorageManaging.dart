//
//  XmaxStorageManaging.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import 'XmaxDownloadedFile.dart';
import 'XmaxStorageProgressHandler.dart';
import 'XmaxUploadedFile.dart';

/// 图片、视频的上传和下载接口。
///
/// 上传来源只能二选一：data 或 at。
/// 使用 data 上传内存数据时，必须同时提供 fileName 和 contentType。
/// 使用 at 上传本地文件时，文件名取自路径，contentType 可根据扩展名推断。
abstract interface class XmaxStorageManaging {

  /// 上传图片到对象存储；来源约束见 [XmaxStorageManaging]。
  ///
  /// - [data]：图片原始字节。
  /// - [at]：本地图片的 file URI。
  /// - [fileName]：内存上传使用的文件名，须包含扩展名；本地文件上传忽略此参数。
  /// - [contentType]：写入对象 Content-Type 的 MIME 类型，例如 image/jpeg。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回对象访问地址、对象键和可用的 ETag。
  Future<XmaxUploadedFile> uploadImage({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  });

  /// 上传图片，并检查内容是否安全；未通过时抛出 unsafeImage 错误。
  ///
  /// 检查在上传后执行，因此即使检查失败，文件也可能已存入 COS。
  /// 上传参数和来源限制见 [uploadImage]、[XmaxStorageManaging]。
  ///
  /// - [data]：图片原始字节。
  /// - [at]：本地图片的 file URI。
  /// - [fileName]：内存上传使用的文件名。
  /// - [contentType]：图片的 MIME 类型。
  /// - [progress]：进度回调，包含已上传字节数和总字节数。
  ///
  /// 返回对象访问地址、对象键及 ETag；服务端未提供 ETag 时，该字段为空。
  Future<XmaxUploadedFile> uploadImageWithSafetyCheck({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  });

  /// 上传视频并返回对象存储结果；不创建实时视频输入流。
  ///
  /// 来源约束见 [XmaxStorageManaging]，文件名规则与 [uploadImage] 相同。
  ///
  /// - [data]：视频原始字节。
  /// - [at]：本地视频的 file URI。
  /// - [fileName]：内存上传使用的文件名。
  /// - [contentType]：视频 MIME 类型，例如 video/mp4。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回对象访问地址、对象键和可用的 ETag。
  Future<XmaxUploadedFile> uploadVideo({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  });

  /// 将远程图片下载到指定本地文件位置。
  ///
  /// - [from]：远程文件的 HTTP 或 HTTPS URL。
  /// - [to]：下载目标的本地 file URI。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回下载后的本地文件 URI 和实际字节数。
  Future<XmaxDownloadedFile> downloadImage({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
  });

  /// 将远程视频下载到指定本地文件位置。
  ///
  /// - [from]：远程文件的 HTTP 或 HTTPS URL。
  /// - [to]：下载目标的本地 file URI。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回下载后的本地文件 URI 和实际字节数。
  Future<XmaxDownloadedFile> downloadVideo({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
  });
}

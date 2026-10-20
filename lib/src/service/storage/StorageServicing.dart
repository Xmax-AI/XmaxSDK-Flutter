//
//  StorageServicing.dart
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import 'dart:typed_data';

import '../../foundation/storage/StorageModels.dart';

/// 图片和视频的内存或文件上传、安全检查及下载接口。
abstract interface class StorageServicing {

  /// 上传内存图片到对象存储。
  ///
  /// - [data]：待上传的原始文件字节。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> uploadImage({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  });

  /// 上传本地图片文件；未指定 MIME 类型时按扩展名推断。
  ///
  /// - [fileURL]：本地文件的 file URI。
  /// - [contentType]：图片 MIME 类型；未指定时按文件扩展名推断。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> uploadImageFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  });

  /// 上传图片并执行内容安全检查；未通过时抛出 unsafeImage。
  ///
  /// - [data]：待上传的原始文件字节。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> uploadImageWithSafetyCheck({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  });

  /// 上传本地图片并执行内容安全检查；未通过时抛出 unsafeImage。
  ///
  /// - [fileURL]：本地文件的 file URI。
  /// - [contentType]：图片 MIME 类型；未指定时按文件扩展名推断。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> uploadImageFileWithSafetyCheck({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  });

  /// 上传视频并返回对象存储结果；不创建实时视频输入流。
  ///
  /// - [data]：待上传的原始文件字节。
  /// - [fileName]：包含扩展名的文件名；内存上传时必须提供。
  /// - [contentType]：对象的 MIME 类型，例如 image/jpeg 或 video/mp4。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> uploadVideo({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  });

  /// 上传本地视频文件；未指定 MIME 类型时按扩展名推断。
  ///
  /// - [fileURL]：本地文件的 file URI。
  /// - [contentType]：视频 MIME 类型；未指定时按文件扩展名推断。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回上传后对象的访问地址、对象键和可用的 ETag。
  Future<StoredFile> uploadVideoFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  });

  /// 将远程图片下载到指定本地文件位置。
  ///
  /// - [remoteURL]：待下载文件的 HTTP 或 HTTPS URL。
  /// - [destinationURL]：下载目标的本地 file URI。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回已下载文件的本地 URI 和实际字节数。
  Future<DownloadedFile> downloadImage({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  });

  /// 将远程视频下载到指定本地文件位置。
  ///
  /// - [remoteURL]：待下载文件的 HTTP 或 HTTPS URL。
  /// - [destinationURL]：下载目标的本地 file URI。
  /// - [progress]：传输进度回调，按已完成和总字节数通知。
  ///
  /// 返回已下载文件的本地 URI 和实际字节数。
  Future<DownloadedFile> downloadVideo({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  });
}

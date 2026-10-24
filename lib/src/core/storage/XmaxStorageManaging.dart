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

/// An interface for uploading and downloading media files.
///
/// Provide exactly one upload source: data or at.
/// Byte-backed uploads require both fileName and contentType.
/// File-backed uploads use the path's filename and infer contentType from its extension when
/// omitted.
abstract interface class XmaxStorageManaging {

  /// Uploads an image to object storage; see [XmaxStorageManaging] for source constraints.
  ///
  /// Parameters:
  /// - [data]: The encoded image bytes.
  /// - [at]: The local image file URI.
  /// - [fileName]: The filename including its extension for byte uploads; ignored for local files.
  /// - [contentType]: The MIME type stored as Content-Type, such as image/jpeg.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the object URL, key, and ETag when provided by storage.
  Future<XmaxUploadedFile> uploadImage({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  });

  /// Uploads an image and performs a safety check, rejecting unsafe content with unsafeImage.
  ///
  /// Safety checking runs after upload, so a rejected file may already exist in COS.
  /// See [uploadImage] and [XmaxStorageManaging] for upload source constraints.
  ///
  /// Parameters:
  /// - [data]: The encoded image bytes.
  /// - [at]: The local image file URI.
  /// - [fileName]: The filename for byte-backed uploads.
  /// - [contentType]: The image MIME type.
  /// - [progress]: The progress handler receiving uploaded and total bytes.
  ///
  /// Returns the object URL and key, with a null ETag if storage does not provide one.
  Future<XmaxUploadedFile> uploadImageWithSafetyCheck({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  });

  /// Uploads a video file without creating a realtime video input stream.
  ///
  /// Source constraints follow [XmaxStorageManaging]; filename rules follow [uploadImage].
  ///
  /// Parameters:
  /// - [data]: The encoded video bytes.
  /// - [at]: The local video file URI.
  /// - [fileName]: The filename for byte-backed uploads.
  /// - [contentType]: The video MIME type, such as video/mp4.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the object URL, key, and ETag when provided by storage.
  Future<XmaxUploadedFile> uploadVideo({
    Uint8List? data,
    Uri? at,
    String? fileName,
    String? contentType,
    XmaxStorageProgressHandler? progress,
  });

  /// Downloads an image to a local file.
  ///
  /// Parameters:
  /// - [from]: The remote file's HTTP or HTTPS URL.
  /// - [to]: The destination file URI.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the downloaded file URI and its byte count.
  Future<XmaxDownloadedFile> downloadImage({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
  });

  /// Downloads a video to a local file.
  ///
  /// Parameters:
  /// - [from]: The remote file's HTTP or HTTPS URL.
  /// - [to]: The destination file URI.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the downloaded file URI and its byte count.
  Future<XmaxDownloadedFile> downloadVideo({
    required Uri from,
    required Uri to,
    XmaxStorageProgressHandler? progress,
  });
}

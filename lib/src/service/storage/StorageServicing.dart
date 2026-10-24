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

/// An interface for image and video uploads, image safety checks, and downloads.
abstract interface class StorageServicing {

  /// Uploads an in-memory image to object storage.
  ///
  /// Parameters:
  /// - [data]: The encoded file bytes to upload.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> uploadImage({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  });

  /// Uploads a local image, inferring its MIME type from the extension if unspecified.
  ///
  /// Parameters:
  /// - [fileURL]: The local file URI.
  /// - [contentType]: The image MIME type; inferred from the file extension if unspecified.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> uploadImageFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  });

  /// Uploads an image and checks content safety; throws unsafeImage if rejected.
  ///
  /// Parameters:
  /// - [data]: The encoded file bytes to upload.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> uploadImageWithSafetyCheck({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  });

  /// Uploads a local image and checks content safety; throws unsafeImage if rejected.
  ///
  /// Parameters:
  /// - [fileURL]: The local file URI.
  /// - [contentType]: The image MIME type; inferred from the file extension if unspecified.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> uploadImageFileWithSafetyCheck({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  });

  /// Uploads a video file without creating a realtime video input stream.
  ///
  /// Parameters:
  /// - [data]: The encoded file bytes to upload.
  /// - [fileName]: The filename including its extension; required for byte-backed uploads.
  /// - [contentType]: The object's MIME type, such as image/jpeg or video/mp4.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> uploadVideo({
    required Uint8List data,
    required String fileName,
    required String contentType,
    StorageProgressListener? progress,
  });

  /// Uploads a local video, inferring its MIME type from the extension if unspecified.
  ///
  /// Parameters:
  /// - [fileURL]: The local file URI.
  /// - [contentType]: The video MIME type; inferred from the file extension if unspecified.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the uploaded object's URL, key, and ETag when available.
  Future<StoredFile> uploadVideoFile({
    required Uri fileURL,
    String? contentType,
    StorageProgressListener? progress,
  });

  /// Downloads an image to a local file.
  ///
  /// Parameters:
  /// - [remoteURL]: The HTTP or HTTPS URL of the file to download.
  /// - [destinationURL]: The destination file URI.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the downloaded file's local URI and actual byte count.
  Future<DownloadedFile> downloadImage({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  });

  /// Downloads a video to a local file.
  ///
  /// Parameters:
  /// - [remoteURL]: The HTTP or HTTPS URL of the file to download.
  /// - [destinationURL]: The destination file URI.
  /// - [progress]: The progress callback receiving completed and total bytes.
  ///
  /// Returns the downloaded file's local URI and actual byte count.
  Future<DownloadedFile> downloadVideo({
    required Uri remoteURL,
    required Uri destinationURL,
    StorageProgressListener? progress,
  });
}

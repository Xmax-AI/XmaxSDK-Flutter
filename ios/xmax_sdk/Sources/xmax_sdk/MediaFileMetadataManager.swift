//
//  MediaFileMetadataManager.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import AVFoundation
import Flutter
import ImageIO

/// Reads media pixel dimensions without decoding full images or video frames.
///
/// Unavailable metadata does not prevent file uploads.
final class MediaFileMetadataManager: NSObject, FlutterPlugin {

    /// Registers the media metadata method channel.
    ///
    /// - Parameter registrar: The plugin registration context for the current Flutter engine.
    static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        let channel = FlutterMethodChannel(
            name: "ai.xmax.sdk/media",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(
            MediaFileMetadataManager(),
            channel: channel
        )
    }

    /// Dispatches image or video dimension requests and delivers metadata results on the main thread.
    ///
    /// - Parameters:
    ///   - call: The request containing a local path or image bytes and a media type.
    ///   - result: The one-shot callback receiving dimensions, nil, or an unsupported-method result.
    func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard call.method == "readResolution" else {
            result(FlutterMethodNotImplemented)
            return
        }

        guard let arguments = call.arguments as? [String: Any] else {
            result(nil)
            return
        }

        let fileURL = (arguments["filePath"] as? String).map { URL(fileURLWithPath: $0) }
        if arguments["mediaType"] as? String == "video" {
            Task {
                let resolution = await Self.videoResolution(fileURL)
                await MainActor.run { result(resolution) }
            }
        } else {
            let data = (arguments["data"] as? FlutterStandardTypedData)?.data
            DispatchQueue.global(qos: .utility).async {
                let resolution = Self.imageResolution(data: data, fileURL: fileURL)
                DispatchQueue.main.async { result(resolution) }
            }
        }
    }

    /// Reads image header dimensions without caching a fully decoded bitmap.
    ///
    /// - Parameters:
    ///   - data: The image bytes, taking precedence over the file source when present.
    ///   - fileURL: The local image URL used when no bytes are provided.
    /// - Returns: Pixel dimensions containing width and height, or nil if unavailable.
    private static func imageResolution(
        data: Data?,
        fileURL: URL?
    ) -> [String: Int]? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        let source: CGImageSource?
        if let data {
            source = CGImageSourceCreateWithData(
                data as CFData,
                options
            )
        } else if let fileURL {
            source = CGImageSourceCreateWithURL(
                fileURL as CFURL,
                options
            )
        } else {
            return nil
        }
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  options
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        return ["width": width.intValue, "height": height.intValue]
    }

    /// Reads video track dimensions and applies the preferred transform to obtain display dimensions.
    ///
    /// - Parameter fileURL: The local video URL; nil skips reading.
    /// - Returns: Display pixel dimensions containing width and height, or nil if unavailable.
    private static func videoResolution(
        _ fileURL: URL?
    ) async -> [String: Int]? {
        guard let fileURL else { return nil }

        do {
            let asset = AVURLAsset(url: fileURL)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let displaySize = size.applying(transform)
            guard displaySize.width.isFinite, displaySize.height.isFinite else { return nil }
            return [
                "width": Int(abs(displaySize.width).rounded()),
                "height": Int(abs(displaySize.height).rounded())
            ]
        } catch {
            return nil
        }
    }
}

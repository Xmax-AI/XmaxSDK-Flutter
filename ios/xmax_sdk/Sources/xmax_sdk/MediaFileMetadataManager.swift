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

/// 读取媒体文件的像素尺寸，不解码完整图片或视频帧；结果不可用时不阻断上传。
final class MediaFileMetadataManager: NSObject, FlutterPlugin {

    /// 注册媒体元数据方法通道。
    ///
    /// - Parameter registrar: 当前 Flutter 引擎提供的插件注册上下文。
    static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        let channel = FlutterMethodChannel(
            name: "ai.xmax.sdk/media",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(MediaFileMetadataManager(), channel: channel)
    }

    /// 分发图片或视频尺寸读取请求，并在主线程交付读取结果。
    ///
    /// - Parameters:
    ///   - call: 包含本地路径或图片字节和媒体类别的请求。
    ///   - result: 接收宽高对象、空值或方法未实现通知的单次回调。
    ///
    /// 元数据结果通过 result 异步通知。
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

    /// 读取图片头部的宽高，不缓存完整解码位图。
    ///
    /// - Parameters:
    ///   - data: 图片原始字节；非空时优先于文件来源。
    ///   - fileURL: 本地图片文件地址；没有字节来源时使用。
    /// - Returns: 包含 width 和 height 的像素尺寸；无法读取时为 nil。
    private static func imageResolution(
        data: Data?,
        fileURL: URL?
    ) -> [String: Int]? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        let source: CGImageSource?
        if let data {
            source = CGImageSourceCreateWithData(data as CFData, options)
        } else if let fileURL {
            source = CGImageSourceCreateWithURL(fileURL as CFURL, options)
        } else {
            return nil
        }
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            return nil
        }

        return ["width": width.intValue, "height": height.intValue]
    }

    /// 读取视频轨道尺寸，并依据首选变换计算显示宽高。
    ///
    /// - Parameter fileURL: 本地视频文件地址；为空时不读取。
    /// - Returns: 包含 width 和 height 的显示像素尺寸；轨道不可用或读取失败时为 nil。
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

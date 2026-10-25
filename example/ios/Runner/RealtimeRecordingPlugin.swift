import Flutter
import UIKit
import Photos
import CoreMedia
import CoreVideo

/// Encodes SDK packets on a background queue, independently of Flutter rendering.
final class RealtimeRecordingPlugin: NSObject, FlutterPlugin {
    private let channel: FlutterMethodChannel
    private let queue = DispatchQueue(label: "ai.xmax.xlab.recording-input", qos: .userInitiated)
    private var recorder: RealtimeVideoRecorder?
    private var recordingID: String?
    private var pool: CVPixelBufferPool?
    private var poolSize: [Int] = []

    private init(channel: FlutterMethodChannel) { self.channel = channel }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "ai.xmax.xlab/recording", binaryMessenger: registrar.messenger())
        let instance = RealtimeRecordingPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        let id = arguments?["id"] as? String
        if call.method == "start" {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async { result(FlutterError(code: "record.permission", message: nil, details: nil)) }
                    return
                }
                self.queue.async {
                    do {
                        guard self.recorder == nil else { throw Failure.invalid("record.alreadyRecording") }
                        let recorder = RealtimeVideoRecorder { [weak self] error in
                            DispatchQueue.main.async {
                                self?.channel.invokeMethod("error", arguments: ["id": id ?? "", "message": error.localizedDescription])
                            }
                        }
                        try recorder.start()
                        self.recorder = recorder
                        self.recordingID = id
                        DispatchQueue.main.async { result(nil) }
                    } catch { self.complete(result, error: error) }
                }
            }
            return
        }
        queue.async {
            guard id != nil, self.recordingID == id else {
                DispatchQueue.main.async {
                    result(call.method == "cancel" ? nil : FlutterError(code: "record.notRecording", message: nil, details: nil))
                }
                return
            }
            do {
                switch call.method {
                case "append":
                    guard let recorder = self.recorder, let packet = call.arguments as? [String: Any] else {
                        throw Failure.invalid("record.notRecording")
                    }
                    recorder.append(try self.frame(packet))
                    DispatchQueue.main.async { result(nil) }
                case "cancel":
                    self.recorder?.cancel()
                    self.recorder = nil
                    self.recordingID = nil
                    self.pool = nil
                    self.poolSize = []
                    DispatchQueue.main.async { result(nil) }
                case "stop":
                    guard let recorder = self.recorder else { throw Failure.invalid("record.notRecording") }
                    self.recorder = nil
                    self.recordingID = nil
                    self.pool = nil
                    self.poolSize = []
                    Task {
                        do {
                            let url = try await recorder.stop()
                            defer { try? FileManager.default.removeItem(at: url) }
                            try await PHPhotoLibrary.shared().performChanges {
                                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                            }
                            DispatchQueue.main.async { result(url.lastPathComponent) }
                        } catch { self.complete(result, error: error) }
                    }
                default:
                    DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
                }
            } catch { self.complete(result, error: error) }
        }
    }

    private func complete(_ result: @escaping FlutterResult, error: Error) {
        DispatchQueue.main.async {
            result(FlutterError(code: "record.failed", message: error.localizedDescription, details: nil))
        }
    }

    private enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { switch self { case .invalid(let value): return value } }
    }

    private func frame(_ packet: [String: Any]) throws -> RealtimeMediaFrame {
        guard let stream = packet["streamID"] as? String,
            let timestamp = packet["ptsUs"] as? Int64,
            timestamp >= 0, let bytes = packet["data"] as? FlutterStandardTypedData
        else { throw Failure.invalid("record.timelineChanged") }
        let pts = CMTime(value: timestamp, timescale: 1_000_000)
        if packet["video"] as? Bool == true {
            guard let width = packet["width"] as? Int, let height = packet["height"] as? Int,
                width > 0, height > 0, width <= 8192, height <= 8192,
                width.isMultiple(of: 2), height.isMultiple(of: 2),
                bytes.data.count == width * height * 3 / 2
            else { throw Failure.invalid("record.invalidSize") }
            if poolSize != [width, height] {
                let attributes: [String: Any] = [
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height,
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [:]
                ]
                guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess else {
                    throw Failure.invalid("record.encoderFailed")
                }
                poolSize = [width, height]
            }
            var buffer: CVPixelBuffer?
            guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                let buffer
            else { throw Failure.invalid("record.encoderFailed") }
            CVPixelBufferLockBaseAddress(buffer, [])
            defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
            bytes.data.withUnsafeBytes { raw in
                let source = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
                let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!.assumingMemoryBound(to: UInt8.self)
                let ys = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
                let uvs = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
                for row in 0..<height { memcpy(y + row * ys, source + row * width, width) }
                let size = width * height
                for row in 0..<(height / 2) {
                    for column in 0..<(width / 2) {
                        let offset = row * width / 2 + column
                        uv[row * uvs + column * 2] = source[size + offset]
                        uv[row * uvs + column * 2 + 1] = source[size + size / 4 + offset]
                    }
                }
            }
            return RealtimeMediaFrame(
                streamID: stream,
                content: .video(RealtimeVideoFrame(
                    pixelBuffer: buffer, presentationTimeStamp: pts,
                    duration: .invalid, rotation: packet["rotation"] as? Int ?? 0
                ))
            )
        }
        guard let rate = packet["sampleRate"] as? Int, let channels = packet["channels"] as? Int,
            let samples = packet["samplesPerChannel"] as? Int
        else { throw Failure.invalid("record.timelineChanged") }
        return RealtimeMediaFrame(
            streamID: stream,
            content: .audio(RealtimeAudioFrame(
                data: bytes.data, sampleRate: rate, channels: channels,
                samplesPerChannel: samples, presentationTimeStamp: pts
            ))
        )
    }
}

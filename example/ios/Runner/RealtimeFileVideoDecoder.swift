import AVFoundation
import Flutter

/// File decoding belongs to the example, not the SDK's external input implementation.
final class RealtimeFileVideoDecoder: NSObject, FlutterPlugin {
    private let queue = DispatchQueue(label: "ai.xmax.xlab.file-decoder")
    private var sessions: [Int: Session] = [:]
    private var nextID = 0

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "ai.xmax.xlab/external_video",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(RealtimeFileVideoDecoder(), channel: channel)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        queue.async {
            do {
                let output: Any?
                switch call.method {
                case "probe":
                    guard let path = arguments["path"] as? String else { throw DecodeError.invalidFile }
                    output = try Session.metadata(path: path)
                case "open":
                    guard let path = arguments["path"] as? String,
                          let fps = arguments["fps"] as? Int, fps > 0, fps <= Int32.max,
                          let width = arguments["width"] as? Int, width > 0, width <= Int32.max, width.isMultiple(of: 2),
                          let height = arguments["height"] as? Int, height > 0, height <= Int32.max, height.isMultiple(of: 2)
                    else { throw DecodeError.invalidFile }
                    let session = try Session(path: path, fps: fps, width: width, height: height)
                    self.nextID += 1
                    self.sessions[self.nextID] = session
                    output = self.nextID
                case "read", "rewind", "close":
                    guard let id = arguments["id"] as? Int else { throw DecodeError.invalidFile }
                    if call.method == "close" {
                        self.sessions.removeValue(forKey: id)?.reader.cancelReading()
                        output = nil
                    } else {
                        guard let session = self.sessions[id] else { throw DecodeError.closed }
                        if call.method == "rewind" {
                            let replacement = try Session(path: session.path, fps: session.fps, width: session.width, height: session.height)
                            session.reader.cancelReading()
                            self.sessions[id] = replacement
                            output = nil
                        } else {
                            output = try session.read()
                        }
                    }
                default:
                    DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
                    return
                }
                DispatchQueue.main.async { result(output) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "external_video", message: error.localizedDescription, details: nil))
                }
            }
        }
    }

    func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        queue.async {
            self.sessions.values.forEach { $0.reader.cancelReading() }
            self.sessions.removeAll()
        }
    }

    private enum DecodeError: LocalizedError {
        case invalidFile, closed, decoding
        var errorDescription: String? {
            switch self {
            case .invalidFile: "The selected video has an invalid format or duration."
            case .closed: "The external file decoder is closed."
            case .decoding: "Could not decode the selected video or PCM audio."
            }
        }
    }

    /// Each session is confined to the serial worker and retains at most one sample per track.
    private final class Session {
        let path: String
        let fps: Int
        let width: Int
        let height: Int
        let reader: AVAssetReader
        let video: AVAssetReaderVideoCompositionOutput
        let audio: AVAssetReaderTrackOutput?
        var nextVideo: CMSampleBuffer?
        var nextAudio: CMSampleBuffer?

        static func metadata(path: String) throws -> [String: Any] {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = asset.tracks(withMediaType: .video).first else { throw DecodeError.invalidFile }
            let bounds = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform).standardized
            let seconds = CMTimeGetSeconds(asset.duration)
            guard bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width >= 2, bounds.height >= 2,
                  bounds.width < CGFloat(Int32.max), bounds.height < CGFloat(Int32.max),
                  seconds.isFinite, seconds > 0, seconds < Double(Int64.max) / 1_000_000 else {
                throw DecodeError.invalidFile
            }
            return [
                "width": Int(bounds.width) / 2 * 2,
                "height": Int(bounds.height) / 2 * 2,
                "durationUs": Int64(seconds * 1_000_000),
                "hasAudio": !asset.tracks(withMediaType: .audio).isEmpty
            ]
        }

        init(path: String, fps: Int, width: Int, height: Int) throws {
            self.path = path
            self.fps = fps
            self.width = width
            self.height = height
            _ = try Self.metadata(path: path)
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            guard let track = asset.tracks(withMediaType: .video).first else { throw DecodeError.invalidFile }
            reader = try AVAssetReader(asset: asset)
            let bounds = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform).standardized
            let transform = track.preferredTransform
                .concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: CGFloat(width) / bounds.width, y: CGFloat(height) / bounds.height))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            layer.setTransform(transform, at: .zero)
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            instruction.layerInstructions = [layer]
            let composition = AVMutableVideoComposition()
            composition.renderSize = CGSize(width: width, height: height)
            composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            composition.instructions = [instruction]
            video = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            video.videoComposition = composition
            video.alwaysCopiesSampleData = false
            guard reader.canAdd(video) else { throw DecodeError.decoding }
            reader.add(video)
            if let audioTrack = asset.tracks(withMediaType: .audio).first {
                let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                    AVLinearPCMIsNonInterleaved: false
                ])
                output.alwaysCopiesSampleData = false
                guard reader.canAdd(output) else { throw DecodeError.decoding }
                reader.add(output)
                audio = output
            } else {
                audio = nil
            }
            guard reader.startReading() else { throw reader.error ?? DecodeError.decoding }
            nextVideo = video.copyNextSampleBuffer()
            nextAudio = audio?.copyNextSampleBuffer()
            guard nextVideo != nil else { throw reader.error ?? DecodeError.decoding }
        }

        func read() throws -> [String: Any]? {
            guard nextVideo != nil || nextAudio != nil else {
                if reader.status == .failed { throw reader.error ?? DecodeError.decoding }
                return nil
            }
            let sendsVideo: Bool
            if let v = nextVideo, let a = nextAudio {
                sendsVideo = CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(v), CMSampleBufferGetPresentationTimeStamp(a)) <= 0
            } else { sendsVideo = nextVideo != nil }
            if sendsVideo, let sample = nextVideo {
                let result = try videoFrame(sample)
                nextVideo = video.copyNextSampleBuffer()
                return result
            }
            guard let sample = nextAudio else { throw DecodeError.decoding }
            let result = try audioFrame(sample)
            nextAudio = audio?.copyNextSampleBuffer()
            return result
        }

        private func time(_ sample: CMSampleBuffer) throws -> Int64 {
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time.isNumeric else { throw DecodeError.decoding }
            return CMTimeConvertScale(time, timescale: 1_000_000, method: .roundTowardZero).value
        }

        private func videoFrame(_ sample: CMSampleBuffer) throws -> [String: Any] {
            guard let pixels = CMSampleBufferGetImageBuffer(sample),
                  CVPixelBufferLockBaseAddress(pixels, .readOnly) == kCVReturnSuccess else { throw DecodeError.decoding }
            defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddress(pixels) else { throw DecodeError.decoding }
            let width = CVPixelBufferGetWidth(pixels)
            let height = CVPixelBufferGetHeight(pixels)
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            var data = Data(count: width * height * 4)
            data.withUnsafeMutableBytes { destination in
                for row in 0..<height {
                    destination.baseAddress!.advanced(by: row * width * 4)
                        .copyMemory(from: base.advanced(by: row * stride), byteCount: width * 4)
                }
            }
            return ["data": FlutterStandardTypedData(bytes: data), "timestampUs": try time(sample), "bgra": true]
        }

        private func audioFrame(_ sample: CMSampleBuffer) throws -> [String: Any] {
            guard let description = CMSampleBufferGetFormatDescription(sample),
                  let format = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                  let block = CMSampleBufferGetDataBuffer(sample) else { throw DecodeError.decoding }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { destination in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: destination.baseAddress!)
            }
            guard status == noErr else { throw DecodeError.decoding }
            return [
                "data": FlutterStandardTypedData(bytes: data), "timestampUs": try time(sample), "audio": true,
                "sampleRate": Int(format.pointee.mSampleRate), "channels": Int(format.pointee.mChannelsPerFrame)
            ]
        }
    }
}

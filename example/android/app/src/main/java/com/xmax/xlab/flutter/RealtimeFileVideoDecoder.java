package com.xmax.xlab.flutter;

import android.graphics.ImageFormat;
import android.graphics.Rect;
import android.media.AudioFormat;
import android.media.Image;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMetadataRetriever;
import android.os.Handler;
import android.os.Looper;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** File decoding owned by XLab; the SDK consumes the resulting video and PCM frames. */
public final class RealtimeFileVideoDecoder implements MethodChannel.MethodCallHandler {
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Map<Integer, Session> sessions = new HashMap<>();
    private final MethodChannel channel;
    private int nextId;

    public RealtimeFileVideoDecoder(BinaryMessenger messenger) {
        channel = new MethodChannel(messenger, "ai.xmax.xlab/external_video");
        channel.setMethodCallHandler(this);
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        worker.execute(() -> {
            try {
                Object output;
                switch (call.method) {
                    case "probe": output = probe(call.argument("path")); break;
                    case "open": {
                        Number fps = call.argument("fps");
                        Number width = call.argument("width"), height = call.argument("height");
                        if (fps == null || fps.intValue() <= 0 || width == null || height == null ||
                            width.intValue() <= 0 || height.intValue() <= 0 || width.intValue() % 2 != 0 || height.intValue() % 2 != 0)
                            throw new IOException("Invalid source video format");
                        Session session = new Session(call.argument("path"), fps.intValue(), width.intValue(), height.intValue());
                        sessions.put(++nextId, session);
                        output = nextId;
                        break;
                    }
                    case "read": {
                        Session session = required(call);
                        output = session.read();
                        break;
                    }
                    case "rewind": {
                        Session previous = required(call);
                        previous.close();
                        sessions.put(((Number) call.argument("id")).intValue(), new Session(previous.path, previous.fps, previous.width, previous.height));
                        output = null;
                        break;
                    }
                    case "close": {
                        Number id = call.argument("id");
                        Session previous = id == null ? null : sessions.remove(id.intValue());
                        if (previous != null) previous.close();
                        output = null;
                        break;
                    }
                    default: main.post(result::notImplemented); return;
                }
                main.post(() -> result.success(output));
            } catch (Exception error) {
                main.post(() -> result.error("external_video", error.getMessage(), null));
            }
        });
    }

    private Session required(MethodCall call) throws IOException {
        Number id = call.argument("id");
        Session session = id == null ? null : sessions.get(id.intValue());
        if (session == null) throw new IOException("The external file decoder is closed");
        return session;
    }

    public void dispose() {
        channel.setMethodCallHandler(null);
        worker.execute(() -> {
            sessions.values().forEach(Session::close);
            sessions.clear();
        });
        worker.shutdown();
    }

    private static Map<String, Object> probe(String path) throws Exception {
        if (path == null) throw new IOException("Missing video path");
        MediaMetadataRetriever metadata = new MediaMetadataRetriever();
        try {
            metadata.setDataSource(path);
            int width = Integer.parseInt(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH));
            int height = Integer.parseInt(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT));
            String rotationValue = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
            int rotation = rotationValue == null ? 0 : Integer.parseInt(rotationValue);
            long durationMs = Long.parseLong(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION));
            if (width < 2 || height < 2 || durationMs <= 0) throw new IOException("Invalid video format or duration");
            Map<String, Object> result = new HashMap<>();
            result.put("width", (rotation == 90 || rotation == 270 ? height : width) / 2 * 2);
            result.put("height", (rotation == 90 || rotation == 270 ? width : height) / 2 * 2);
            result.put("durationUs", durationMs * 1000);
            result.put("hasAudio", "yes".equals(metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO)));
            return result;
        } finally {
            metadata.release();
        }
    }

    /** Readers retain two video images for frame-rate conversion and never play audio locally. */
    private static final class Session {
        final String path;
        final int fps;
        final int width, height;
        final long videoDurationUs;
        final Track video;
        final Track audio;
        Map<String, Object> nextVideo;
        Map<String, Object> nextAudio;
        Map<String, Object> currentDecodedVideo;
        Map<String, Object> nextDecodedVideo;
        long outputVideoIndex;

        Session(String path, int fps, int width, int height) throws Exception {
            this.path = path;
            this.fps = fps;
            this.width = width;
            this.height = height;
            video = new Track(path, true, width, height);
            Track optionalAudio = null;
            try {
                Map<String, Object> metadata = probe(path);
                long trackDuration = video.format.containsKey(MediaFormat.KEY_DURATION)
                    ? video.format.getLong(MediaFormat.KEY_DURATION) : 0;
                videoDurationUs = trackDuration > 0 ? trackDuration : ((Number) metadata.get("durationUs")).longValue();
                if (Boolean.TRUE.equals(metadata.get("hasAudio"))) optionalAudio = new Track(path, false, 0, 0);
                audio = optionalAudio;
                currentDecodedVideo = video.next();
                if (currentDecodedVideo == null) throw new IOException("The video has no decodable frames");
                nextDecodedVideo = video.next();
                nextVideo = nextVideoFrame();
                nextAudio = audio == null ? null : audio.next();
            } catch (Exception error) {
                video.close();
                if (optionalAudio != null) optionalAudio.close();
                throw error;
            }
        }

        Map<String, Object> read() throws Exception {
            if (nextVideo == null && nextAudio == null) return null;
            boolean sendsVideo = nextAudio == null || (nextVideo != null &&
                ((Number) nextVideo.get("timestampUs")).longValue() <= ((Number) nextAudio.get("timestampUs")).longValue());
            Map<String, Object> result = sendsVideo ? nextVideo : nextAudio;
            if (sendsVideo) nextVideo = nextVideoFrame();
            else nextAudio = audio.next();
            return result;
        }

        /** Resamples file timing to the requested source rate, retaining only two decoded images. */
        private Map<String, Object> nextVideoFrame() throws Exception {
            long timestampUs = outputVideoIndex * 1_000_000L / fps;
            if (timestampUs >= videoDurationUs) return null;
            while (nextDecodedVideo != null && ((Number) nextDecodedVideo.get("timestampUs")).longValue() <= timestampUs) {
                currentDecodedVideo = nextDecodedVideo;
                nextDecodedVideo = video.next();
            }
            outputVideoIndex++;
            Map<String, Object> result = new HashMap<>(currentDecodedVideo);
            result.put("timestampUs", timestampUs);
            return result;
        }

        void close() {
            video.close();
            if (audio != null) audio.close();
        }
    }

    /** MediaCodec is used without a display surface so decoded pixels can enter the public sink. */
    private static final class Track {
        final MediaExtractor extractor = new MediaExtractor();
        final boolean video;
        final int width, height;
        MediaCodec codec;
        MediaFormat format;
        int rotation;
        boolean inputEnded;
        boolean outputEnded;
        boolean closed;

        Track(String path, boolean video, int width, int height) throws Exception {
            this.video = video;
            this.width = width;
            this.height = height;
            try {
                extractor.setDataSource(path);
                String prefix = video ? "video/" : "audio/";
                for (int index = 0; index < extractor.getTrackCount(); index++) {
                    MediaFormat candidate = extractor.getTrackFormat(index);
                    String mime = candidate.getString(MediaFormat.KEY_MIME);
                    if (mime != null && mime.startsWith(prefix)) {
                        extractor.selectTrack(index);
                        format = candidate;
                        if (video) {
                            rotation = candidate.containsKey(MediaFormat.KEY_ROTATION) ? candidate.getInteger(MediaFormat.KEY_ROTATION) : 0;
                            candidate.setInteger(MediaFormat.KEY_ROTATION, 0);
                            candidate.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
                        } else {
                            candidate.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT);
                        }
                        codec = MediaCodec.createDecoderByType(mime);
                        codec.configure(candidate, null, null, 0);
                        codec.start();
                        return;
                    }
                }
                throw new IOException("The requested media track is unavailable");
            } catch (Exception error) {
                close();
                throw error;
            }
        }

        Map<String, Object> next() throws Exception {
            if (outputEnded) return null;
            long deadline = System.nanoTime() + 5_000_000_000L;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (System.nanoTime() < deadline) {
                if (!inputEnded) {
                    int input = codec.dequeueInputBuffer(10_000);
                    if (input >= 0) {
                        ByteBuffer buffer = codec.getInputBuffer(input);
                        if (buffer == null) throw new IOException("Missing decoder input buffer");
                        int size = extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEnded = true;
                        } else {
                            codec.queueInputBuffer(input, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int output = codec.dequeueOutputBuffer(info, 10_000);
                if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    format = codec.getOutputFormat();
                } else if (output >= 0) {
                    outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    try {
                        if (info.size > 0 && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                            Map<String, Object> result = new HashMap<>();
                            result.put("timestampUs", info.presentationTimeUs);
                            if (video) {
                                try (Image image = codec.getOutputImage(output)) {
                                    if (image == null || image.getFormat() != ImageFormat.YUV_420_888)
                                        throw new IOException("The decoder cannot provide YUV video frames");
                                    result.put("data", nv12(image, rotation, width, height));
                                }
                            } else {
                                ByteBuffer buffer = codec.getOutputBuffer(output);
                                if (buffer == null) throw new IOException("Missing decoded PCM samples");
                                buffer.position(info.offset);
                                buffer.limit(info.offset + info.size);
                                byte[] data = new byte[info.size];
                                buffer.get(data);
                                result.put("data", data);
                                result.put("audio", true);
                                result.put("sampleRate", format.getInteger(MediaFormat.KEY_SAMPLE_RATE));
                                result.put("channels", format.getInteger(MediaFormat.KEY_CHANNEL_COUNT));
                                int encoding = format.containsKey(MediaFormat.KEY_PCM_ENCODING)
                                    ? format.getInteger(MediaFormat.KEY_PCM_ENCODING) : AudioFormat.ENCODING_PCM_16BIT;
                                if (encoding != AudioFormat.ENCODING_PCM_16BIT && encoding != AudioFormat.ENCODING_PCM_FLOAT)
                                    throw new IOException("The decoder returned unsupported PCM samples");
                                result.put("float32", encoding == AudioFormat.ENCODING_PCM_FLOAT);
                            }
                            return result;
                        }
                    } finally { codec.releaseOutputBuffer(output, false); }
                    if (outputEnded) return null;
                }
            }
            throw new IOException("Timed out while decoding the selected video");
        }

        void close() {
            if (closed) return;
            closed = true;
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) { }
                try { codec.release(); } catch (Exception ignored) { }
                codec = null;
            }
            extractor.release();
        }
    }

    /** Packs crop-aware planes and applies container rotation before SDK submission. */
    private static byte[] nv12(Image image, int rotation, int outputWidth, int outputHeight) {
        Rect crop = image.getCropRect();
        int width = crop.width() / 2 * 2;
        int height = crop.height() / 2 * 2;
        byte[] result = new byte[outputWidth * outputHeight * 3 / 2];
        Image.Plane[] planes = image.getPlanes();
        for (int plane = 0; plane < 3; plane++) {
            int divisor = plane == 0 ? 1 : 2;
            int w = width / divisor;
            int h = height / divisor;
            int targetWidth = outputWidth / divisor;
            int targetHeight = outputHeight / divisor;
            int orientedWidth = rotation == 90 || rotation == 270 ? h : w;
            int orientedHeight = rotation == 90 || rotation == 270 ? w : h;
            ByteBuffer input = planes[plane].getBuffer();
            int base = input.position() + (crop.top / divisor) * planes[plane].getRowStride()
                + (crop.left / divisor) * planes[plane].getPixelStride();
            for (int y = 0; y < targetHeight; y++) {
                for (int x = 0; x < targetWidth; x++) {
                    int ox = (int) ((long) x * orientedWidth / targetWidth);
                    int oy = (int) ((long) y * orientedHeight / targetHeight);
                    int sx = ox, sy = oy;
                    if (rotation == 90) { sx = oy; sy = h - 1 - ox; }
                    else if (rotation == 180) { sx = w - 1 - ox; sy = h - 1 - oy; }
                    else if (rotation == 270) { sx = w - 1 - oy; sy = ox; }
                    int index = y * targetWidth + x;
                    int destination = plane == 0 ? index : outputWidth * outputHeight + index * 2 + plane - 1;
                    result[destination] = input.get(base + sy * planes[plane].getRowStride() + sx * planes[plane].getPixelStride());
                }
            }
        }
        return result;
    }
}

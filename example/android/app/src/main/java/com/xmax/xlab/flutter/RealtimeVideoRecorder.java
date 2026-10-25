package com.xmax.xlab.flutter;

import android.content.ContentValues;
import android.content.Context;
import android.media.Image;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileInputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Encodes remote PCM and I420 in a background worker, preserving their shared PTS offset. */
public final class RealtimeVideoRecorder implements MethodChannel.MethodCallHandler {
    private final Context context;
    private final MethodChannel channel;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private Track video, audio;
    private File directory;
    private String streamID;
    private String recordingID;
    private int rotation;
    private boolean recording;

    public RealtimeVideoRecorder(Context context, BinaryMessenger messenger) {
        this.context = context;
        channel = new MethodChannel(messenger, "ai.xmax.xlab/recording");
        channel.setMethodCallHandler(this);
    }

    @Override public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        worker.execute(() -> {
            Map<?, ?> arguments = call.arguments instanceof Map ? (Map<?, ?>) call.arguments : null;
            String id = arguments == null ? null : (String) arguments.get("id");
            if (!call.method.equals("start") && (recordingID == null || !recordingID.equals(id))) {
                main.post(() -> {
                    if (call.method.equals("cancel")) result.success(null);
                    else result.error("record.notRecording", null, null);
                });
                return;
            }
            if (call.method.equals("start") && recording) {
                main.post(() -> result.error("record.alreadyRecording", null, null));
                return;
            }
            try {
                switch (call.method) {
                    case "start":
                        if (recording) throw new IllegalStateException("record.alreadyRecording");
                        if (Build.VERSION.SDK_INT < 29) throw new IllegalStateException("record.requiresAndroid10");
                        directory = new File(context.getCacheDir(), "record-" + UUID.randomUUID());
                        if (!directory.mkdir()) throw new IllegalStateException("record.encoderFailed");
                        recording = true;
                        recordingID = id;
                        main.post(() -> result.success(null));
                        break;
                    case "append":
                        if (!recording) throw new IllegalStateException("record.notRecording");
                        append((Map<?, ?>) call.arguments);
                        main.post(() -> result.success(null));
                        break;
                    case "stop":
                        if (!recording) throw new IllegalStateException("record.notRecording");
                        recording = false;
                        if (video == null) throw new IllegalStateException("record.noFrames");
                        video.finish();
                        if (audio != null) audio.finish();
                        File output = combine();
                        String uri;
                        if (Boolean.FALSE.equals(arguments.get("saveToGallery"))) {
                            File destination = new File(context.getCacheDir(), "XLab-" + UUID.randomUUID() + ".mp4");
                            if (!output.renameTo(destination)) throw new IllegalStateException("record.saveFailed");
                            uri = destination.toString();
                        } else {
                            uri = save(output);
                        }
                        cleanup();
                        main.post(() -> result.success(uri));
                        break;
                    case "cancel":
                        cleanup();
                        main.post(() -> result.success(null));
                        break;
                    default:
                        main.post(result::notImplemented);
                }
            } catch (Exception error) {
                cleanup();
                main.post(() -> result.error("record.failed", error.getMessage(), null));
            }
        });
    }

    private void append(Map<?, ?> packet) throws Exception {
        String incoming = (String) packet.get("streamID");
        long pts = number(packet, "ptsUs");
        if (incoming == null || pts < 0 || (streamID != null && !streamID.equals(incoming)))
            throw new IllegalStateException("record.timelineChanged");
        streamID = incoming;
        byte[] data = (byte[]) packet.get("data");
        if (Boolean.TRUE.equals(packet.get("video"))) {
            int width = (int) number(packet, "width"), height = (int) number(packet, "height");
            int angle = (int) number(packet, "rotation");
            if (width <= 0 || height <= 0 || width > 8192 || height > 8192 ||
                    width % 2 != 0 || height % 2 != 0 || data.length != width * height * 3 / 2)
                throw new IllegalStateException("record.invalidSize");
            if (video == null) {
                rotation = angle;
                video = new Track(new File(directory, "video.mp4"), width, height, pts);
            }
            if (video.width != width || video.height != height || rotation != angle)
                throw new IllegalStateException("record.sizeChanged");
            video.pushVideo(data, pts);
        } else {
            int rate = (int) number(packet, "sampleRate"), channels = (int) number(packet, "channels");
            int samples = (int) number(packet, "samplesPerChannel");
            if (rate < 8000 || rate > 192000 || channels < 1 || channels > 2 ||
                    samples <= 0 || samples > 192000 || data.length != samples * channels * 2)
                throw new IllegalStateException("record.timelineChanged");
            if (audio == null) audio = new Track(new File(directory, "audio.mp4"), rate, channels, pts, true);
            if (audio.rate != rate || audio.channels != channels) throw new IllegalStateException("record.timelineChanged");
            audio.pushAudio(data, pts);
        }
    }

    private static long number(Map<?, ?> packet, String key) {
        Object value = packet.get(key);
        if (!(value instanceof Number)) throw new IllegalArgumentException("record.timelineChanged");
        return ((Number) value).longValue();
    }

    private File combine() throws Exception {
        File output = new File(directory, "output.mp4");
        MediaMuxer muxer = new MediaMuxer(output.toString(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
        MediaExtractor ve = new MediaExtractor(), ae = new MediaExtractor();
        boolean started = false;
        try {
            muxer.setOrientationHint(rotation);
            ve.setDataSource(video.file.toString());
            ve.selectTrack(0);
            int vi = muxer.addTrack(ve.getTrackFormat(0));
            int ai = -1;
            if (audio != null) {
                ae.setDataSource(audio.file.toString());
                ae.selectTrack(0);
                ai = muxer.addTrack(ae.getTrackFormat(0));
            }
            muxer.start();
            started = true;
            long origin = audio == null ? video.origin : Math.min(video.origin, audio.origin);
            ByteBuffer buffer = ByteBuffer.allocateDirect(Math.max(video.width * video.height * 3 / 2, 1024 * 1024));
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            while (ve.getSampleTime() >= 0 || (audio != null && ae.getSampleTime() >= 0)) {
                boolean useVideo = audio == null || ae.getSampleTime() < 0 ||
                        (ve.getSampleTime() >= 0 && ve.getSampleTime() + video.origin <= ae.getSampleTime() + audio.origin);
                MediaExtractor extractor = useVideo ? ve : ae;
                buffer.clear();
                int size = extractor.readSampleData(buffer, 0);
                if (size < 0) break;
                info.set(0, size, extractor.getSampleTime() + (useVideo ? video.origin : audio.origin) - origin,
                        extractor.getSampleFlags());
                muxer.writeSampleData(useVideo ? vi : ai, buffer, info);
                extractor.advance();
            }
            return output;
        } finally {
            ve.release();
            ae.release();
            try { if (started) muxer.stop(); }
            finally { muxer.release(); }
        }
    }

    private String save(File output) throws Exception {
        ContentValues values = new ContentValues();
        values.put(MediaStore.Video.Media.DISPLAY_NAME, "XLab-" + System.currentTimeMillis() + ".mp4");
        values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
        values.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/XLab");
        values.put(MediaStore.Video.Media.IS_PENDING, 1);
        Uri uri = context.getContentResolver().insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
        if (uri == null) throw new IllegalStateException("record.saveFailed");
        try {
            try (FileInputStream input = new FileInputStream(output);
                 OutputStream target = context.getContentResolver().openOutputStream(uri)) {
                if (target == null) throw new IllegalStateException("record.saveFailed");
                byte[] buffer = new byte[256 * 1024];
                int count;
                while ((count = input.read(buffer)) >= 0) target.write(buffer, 0, count);
            }
            values.clear();
            values.put(MediaStore.Video.Media.IS_PENDING, 0);
            if (context.getContentResolver().update(uri, values, null, null) != 1)
                throw new IllegalStateException("record.saveFailed");
            return uri.toString();
        } catch (Exception error) {
            context.getContentResolver().delete(uri, null, null);
            throw error;
        }
    }

    private void cleanup() {
        recording = false;
        try { if (video != null) video.close(); } catch (Exception ignored) {}
        try { if (audio != null) audio.close(); } catch (Exception ignored) {}
        video = null;
        audio = null;
        streamID = null;
        recordingID = null;
        if (directory != null) {
            File[] files = directory.listFiles();
            if (files != null) for (File file : files) file.delete();
            directory.delete();
        }
        directory = null;
    }

    public void dispose() {
        channel.setMethodCallHandler(null);
        worker.execute(this::cleanup);
        worker.shutdown();
    }

    private static final class Track {
        final File file;
        final MediaCodec codec;
        final MediaMuxer muxer;
        final I420FrameWriter frameWriter;
        final int width, height, rate, channels;
        final long origin;
        long lastPTS = -1, audioSamples;
        int trackIndex = -1;
        boolean ended, closed;
        final MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();

        Track(File file, int width, int height, long origin) throws Exception {
            this(file, width, height, origin, false);
        }

        Track(File file, int first, int second, long origin, boolean audio) throws Exception {
            this.file = file;
            this.origin = origin;
            width = audio ? 0 : first;
            height = audio ? 0 : second;
            rate = audio ? first : 0;
            channels = audio ? second : 0;
            frameWriter = audio ? null : new I420FrameWriter(width, height);
            String mime = audio ? MediaFormat.MIMETYPE_AUDIO_AAC : MediaFormat.MIMETYPE_VIDEO_AVC;
            MediaFormat format = audio ? MediaFormat.createAudioFormat(mime, rate, channels) :
                    MediaFormat.createVideoFormat(mime, width, height);
            if (audio) {
                format.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
                format.setInteger(MediaFormat.KEY_BIT_RATE, 96000 * channels);
            } else {
                format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
                format.setInteger(MediaFormat.KEY_FRAME_RATE, 30);
                format.setInteger(MediaFormat.KEY_BIT_RATE, Math.min(12000000, Math.max(1500000, width * height * 6)));
                format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
            }
            codec = MediaCodec.createEncoderByType(mime);
            MediaMuxer createdMuxer = null;
            try {
                createdMuxer = new MediaMuxer(file.toString(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
                codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                codec.start();
            } catch (Exception error) {
                try { codec.release(); } catch (Exception ignored) {}
                if (createdMuxer != null) {
                    try { createdMuxer.release(); } catch (Exception ignored) {}
                }
                throw error;
            }
            muxer = createdMuxer;
        }

        private int input() throws Exception {
            long deadline = System.nanoTime() + 2_000_000_000L;
            do {
                drain(false);
                int index = codec.dequeueInputBuffer(10000);
                if (index >= 0) return index;
            } while (System.nanoTime() < deadline);
            throw new IllegalStateException("record.bufferFull");
        }

        void pushVideo(byte[] data, long pts) throws Exception {
            if (pts <= lastPTS) throw new IllegalStateException("record.timelineChanged");
            lastPTS = pts;
            int index = input();
            Image image = codec.getInputImage(index);
            if (image == null) throw new IllegalStateException("record.encoderFailed");
            try {
                Image.Plane[] planes = image.getPlanes();
                frameWriter.write(data,
                        new ByteBuffer[]{planes[0].getBuffer(), planes[1].getBuffer(), planes[2].getBuffer()},
                        new int[]{planes[0].getRowStride(), planes[1].getRowStride(), planes[2].getRowStride()},
                        new int[]{planes[0].getPixelStride(), planes[1].getPixelStride(), planes[2].getPixelStride()});
            } finally { image.close(); }
            codec.queueInputBuffer(index, 0, data.length, pts - origin, 0);
            drain(false);
        }

        void pushAudio(byte[] data, long pts) throws Exception {
            if (pts <= lastPTS) throw new IllegalStateException("record.timelineChanged");
            lastPTS = pts;
            long target = Math.round((pts - origin) * (double) rate / 1000000);
            long gap = target - audioSamples;
            if (gap < -1 || gap > rate * 10L) throw new IllegalStateException("record.timelineChanged");
            while (gap > 0) {
                int count = (int) Math.min(gap, 4800);
                feedAudio(new byte[count * channels * 2]);
                gap -= count;
            }
            feedAudio(data);
        }

        private void feedAudio(byte[] data) throws Exception {
            int offset = 0;
            while (offset < data.length) {
                int index = input();
                ByteBuffer buffer = codec.getInputBuffer(index);
                if (buffer == null) throw new IllegalStateException("record.encoderFailed");
                buffer.clear();
                int count = Math.min(buffer.remaining(), data.length - offset) / (channels * 2) * channels * 2;
                if (count <= 0) throw new IllegalStateException("record.encoderFailed");
                buffer.put(data, offset, count);
                codec.queueInputBuffer(index, 0, count, audioSamples * 1000000 / rate, 0);
                audioSamples += count / (channels * 2);
                offset += count;
                drain(false);
            }
        }

        private void drain(boolean finishing) throws Exception {
            while (true) {
                int index = codec.dequeueOutputBuffer(info, finishing ? 10000 : 0);
                if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return;
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    trackIndex = muxer.addTrack(codec.getOutputFormat());
                    muxer.start();
                } else if (index >= 0) {
                    ByteBuffer buffer = codec.getOutputBuffer(index);
                    if (info.size > 0 && (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                        if (trackIndex < 0 || buffer == null) throw new IllegalStateException("record.encoderFailed");
                        buffer.position(info.offset);
                        buffer.limit(info.offset + info.size);
                        muxer.writeSampleData(trackIndex, buffer, info);
                    }
                    ended = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                    codec.releaseOutputBuffer(index, false);
                    if (ended) return;
                }
            }
        }

        void finish() throws Exception {
            int index = input();
            long end = rate > 0 ? audioSamples * 1000000 / rate : Math.max(0, lastPTS - origin) + 33333;
            codec.queueInputBuffer(index, 0, 0, end, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
            long deadline = System.nanoTime() + 5_000_000_000L;
            while (!ended && System.nanoTime() < deadline) drain(true);
            if (!ended) throw new IllegalStateException("record.encoderFailed");
            close();
        }

        void close() {
            if (closed) return;
            closed = true;
            try { codec.stop(); } catch (Exception ignored) {}
            try { codec.release(); } catch (Exception ignored) {}
            try { if (trackIndex >= 0) muxer.stop(); } catch (Exception ignored) {}
            try { muxer.release(); } catch (Exception ignored) {}
        }
    }
}

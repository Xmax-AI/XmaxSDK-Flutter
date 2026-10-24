//
//  MediaFileMetadataManager.java
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

package ai.xmax.sdk;

import android.graphics.BitmapFactory;
import android.media.MediaMetadataRetriever;
import android.os.Handler;
import android.os.Looper;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Reads media pixel dimensions in the background without decoding full images or video frames.
 *
 * Unavailable metadata produces a null result without preventing file uploads.
 */
final class MediaFileMetadataManager implements MethodChannel.MethodCallHandler {

    /**
     * The background executor that reads file metadata sequentially.
     */
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    /**
     * The handler delivering method channel results on the main thread.
     */
    private final Handler main = new Handler(Looper.getMainLooper());

    /**
     * Whether the handler is detached from its engine and must stop delivering results.
     */
    private boolean detached;

    /**
     * Handles media dimension requests and delivers available dimensions on the main thread.
     *
     * Results are delivered asynchronously; pending read results are discarded after detachment.
     *
     * @param call the request containing a file path or image bytes and a media type
     * @param result the callback receiving dimensions, null, or an unsupported-method result
     */
    @Override
    public void onMethodCall(
        MethodCall call,
        MethodChannel.Result result
    ) {
        if (!"readResolution".equals(call.method)) {
            result.notImplemented();
            return;
        }

        if (!(call.arguments instanceof Map) || detached) {
            result.success(null);
            return;
        }

        Object path = call.argument("filePath");
        Object data = call.argument("data");
        boolean video = "video".equals(call.argument("mediaType"));

        worker.execute(() -> {
            Map<String, Integer> resolution = readResolution(
                path instanceof String ? (String) path : null,
                data instanceof byte[] ? (byte[]) data : null,
                video
            );
            main.post(() -> {
                if (!detached) result.success(resolution);
            });
        });
    }

    /**
     * Invalidates the handler and stops queued background reads.
     */
    void dispose() {
        detached = true;
        worker.shutdownNow();
    }

    /**
     * Reads media header dimensions, applying video rotation to obtain display dimensions.
     *
     * @param path the local file path, required for video and optional for images
     * @param data the image bytes used when no path is provided; ignored for video
     * @param video true to read video metadata, or false to read an image
     * @return positive pixel dimensions containing width and height, or null if unavailable
     */
    private static Map<String, Integer> readResolution(
        String path,
        byte[] data,
        boolean video
    ) {
        try {
            int width;
            int height;
            if (video) {
                if (path == null) return null;
                MediaMetadataRetriever retriever = new MediaMetadataRetriever();
                try {
                    retriever.setDataSource(path);
                    width = Integer.parseInt(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH));
                    height = Integer.parseInt(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT));
                    String rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION);
                    if ("90".equals(rotation) || "270".equals(rotation)) {
                        int originalWidth = width;
                        width = height;
                        height = originalWidth;
                    }
                } finally {
                    retriever.release();
                }
            } else {
                BitmapFactory.Options options = new BitmapFactory.Options();
                options.inJustDecodeBounds = true;
                if (path != null) {
                    BitmapFactory.decodeFile(
                        path,
                        options
                    );
                } else if (data != null) {
                    BitmapFactory.decodeByteArray(
                        data,
                        0,
                        data.length,
                        options
                    );
                } else {
                    return null;
                }
                width = options.outWidth;
                height = options.outHeight;
            }
            if (width <= 0 || height <= 0) return null;
            Map<String, Integer> resolution = new HashMap<>();
            resolution.put(
                "width",
                width
            );
            resolution.put(
                "height",
                height
            );
            return resolution;
        } catch (Exception ignored) {
            // Metadata is optional; unsupported formats or corrupt files must not prevent uploads.
            return null;
        }
    }
}

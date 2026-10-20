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
 * 在后台读取图片或视频的像素尺寸，不解码完整图像或视频帧。
 * 元数据不可用时返回空结果，不阻断实际文件上传。
 */
final class MediaFileMetadataManager implements MethodChannel.MethodCallHandler {

    /**
     * 按顺序执行文件元数据读取的后台线程。
     */
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    /**
     * 将方法通道结果送回主线程的调度入口。
     */
    private final Handler main = new Handler(Looper.getMainLooper());

    /**
     * 当前处理器是否已解除引擎绑定；解除后不再提交结果。
     */
    private boolean detached;

    /**
     * 处理媒体尺寸请求，并在主线程回传可用的宽高。
     *
     * @param call 包含文件路径或图片字节及媒体类别的请求
     * @param result 接收宽高对象、空值或方法未实现通知的回调
     *
     * 结果异步通过 result 交付，解除绑定后丢弃旧读取结果。
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
     * 使当前处理器失效，并停止等待中的后台读取任务。
     */
    void dispose() {
        detached = true;
        worker.shutdownNow();
    }

    /**
     * 读取媒体头部尺寸，视频按旋转信息转换为显示宽高。
     *
     * @param path 本地文件路径；视频必须提供，图片可省略
     * @param data 图片原始字节；没有路径时使用，视频不使用该参数
     * @param video 是否按视频文件解析；false 表示图片
     * @return 包含 width 和 height 的正整数像素尺寸；不可读取时返回 null
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
                    BitmapFactory.decodeFile(path, options);
                } else if (data != null) {
                    BitmapFactory.decodeByteArray(data, 0, data.length, options);
                } else {
                    return null;
                }
                width = options.outWidth;
                height = options.outHeight;
            }
            if (width <= 0 || height <= 0) return null;
            Map<String, Integer> resolution = new HashMap<>();
            resolution.put("width", width);
            resolution.put("height", height);
            return resolution;
        } catch (Exception ignored) {
            // 元数据读取是可选能力，格式不支持或文件损坏时不影响上传。
            return null;
        }
    }
}

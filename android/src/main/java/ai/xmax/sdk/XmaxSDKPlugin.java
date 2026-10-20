//
//  XmaxSDKPlugin.java
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

package ai.xmax.sdk;

import android.util.Log;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * 注册 SDK 原生日志和媒体元数据通道；实时生成及对象存储由 Dart 层管理。
 */
public final class XmaxSDKPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {

    /**
     * Logcat 中用于筛选 SDK 日志的标签。
     */
    private static final String TAG = "XmaxSDK";

    /**
     * 单段日志的 UTF-8 字节上限，避免系统截断长日志。
     */
    private static final int MAX_LINE_BYTES = 3000;

    /**
     * 接收 Dart 格式化日志的方法通道。
     */
    private MethodChannel channel;

    /**
     * 接收媒体尺寸读取请求的方法通道。
     */
    private MethodChannel mediaChannel;

    /**
     * 当前引擎绑定的后台媒体元数据读取器。
     */
    private MediaFileMetadataManager metadataManager;

    /**
     * 注册当前 Flutter 引擎的日志和媒体元数据处理器。
     *
     * @param binding 当前 Flutter 引擎提供的通道注册上下文
     */
    @Override
    public void onAttachedToEngine(
        @NonNull FlutterPluginBinding binding
    ) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "ai.xmax.sdk/logging");
        channel.setMethodCallHandler(this);

        metadataManager = new MediaFileMetadataManager();
        mediaChannel = new MethodChannel(binding.getBinaryMessenger(), "ai.xmax.sdk/media");
        mediaChannel.setMethodCallHandler(metadataManager);
    }

    /**
     * 解除当前引擎的通道监听，并停止后台元数据读取。
     *
     * @param binding 正在解除绑定的 Flutter 引擎上下文
     *
     * 解除绑定后不再接收新的通道请求。
     */
    @Override
    public void onDetachedFromEngine(
        @NonNull FlutterPluginBinding binding
    ) {
        if (mediaChannel != null) {
            mediaChannel.setMethodCallHandler(null);
            mediaChannel = null;
            metadataManager.dispose();
            metadataManager = null;
        }

        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    /**
     * 校验日志请求并按原始顺序将各行输出到 Logcat。
     *
     * @param call 包含日志等级和消息文本的通道请求
     * @param result 接收调用成功、参数错误或方法未实现的单次回调
     *
     * 处理结果通过 result 通知。
     */
    @Override
    public void onMethodCall(
        @NonNull MethodCall call,
        @NonNull MethodChannel.Result result
    ) {
        if (!"log".equals(call.method)) {
            result.notImplemented();
            return;
        }

        if (!(call.arguments instanceof java.util.Map)) {
            result.error("invalid_arguments", "Invalid log record", null);
            return;
        }

        Object level = call.argument("level");
        Object message = call.argument("message");
        int priority = priorityFor(level);
        if (priority == 0 || !(message instanceof String)) {
            result.error("invalid_arguments", "Invalid log record", null);
            return;
        }

        for (String line : ((String) message).split("\n", -1)) {
            writeLine(priority, line);
        }

        result.success(null);
    }

    /**
     * 将 Dart 日志等级转换为系统日志优先级。
     *
     * @param level debug、info、warning 或 error 等级名称
     * @return 对应 Logcat 优先级；不支持的名称返回 0
     */
    private static int priorityFor(
        Object level
    ) {
        if ("debug".equals(level)) return Log.DEBUG;
        if ("info".equals(level)) return Log.INFO;
        if ("warning".equals(level)) return Log.WARN;
        if ("error".equals(level)) return Log.ERROR;
        return 0;
    }

    /**
     * 按 UTF-8 字节限制分段输出一行日志，不拆分 Unicode 码点。
     *
     * @param priority 本行使用的 Logcat 优先级
     * @param line 需要输出的单行文本
     *
     * 所有分段保持原始顺序和日志等级。
     */
    private static void writeLine(
        int priority,
        String line
    ) {
        // 按码点累计 UTF-8 字节数，避免拆分字符或触发系统截断。
        int start = 0;
        int bytes = 0;
        for (int offset = 0; offset < line.length();) {
            int codePoint = line.codePointAt(offset);
            int size = codePoint <= 0x7f ? 1 : codePoint <= 0x7ff ? 2 : codePoint <= 0xffff ? 3 : 4;
            if (bytes + size > MAX_LINE_BYTES) {
                Log.println(priority, TAG, line.substring(start, offset));
                start = offset;
                bytes = 0;
            }
            bytes += size;
            offset += Character.charCount(codePoint);
        }

        Log.println(priority, TAG, line.substring(start));
    }
}

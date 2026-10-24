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
 * Registers native SDK logging and media metadata channels.
 */
public final class XmaxSDKPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {

    /**
     * The Logcat tag for filtering SDK messages.
     */
    private static final String TAG = "XmaxSDK";

    /**
     * The UTF-8 byte limit per log chunk, preventing system truncation.
     */
    private static final int MAX_LINE_BYTES = 3000;

    /**
     * The method channel receiving formatted Dart logs.
     */
    private MethodChannel channel;

    /**
     * The method channel receiving media dimension requests.
     */
    private MethodChannel mediaChannel;

    /**
     * The background metadata reader bound to the current engine.
     */
    private MediaFileMetadataManager metadataManager;

    /**
     * Registers logging and media metadata handlers for the current Flutter engine.
     *
     * @param binding the channel registration context for the current Flutter engine
     */
    @Override
    public void onAttachedToEngine(
        @NonNull FlutterPluginBinding binding
    ) {
        channel = new MethodChannel(
            binding.getBinaryMessenger(),
            "ai.xmax.sdk/logging"
        );
        channel.setMethodCallHandler(this);

        metadataManager = new MediaFileMetadataManager();
        mediaChannel = new MethodChannel(
            binding.getBinaryMessenger(),
            "ai.xmax.sdk/media"
        );
        mediaChannel.setMethodCallHandler(metadataManager);
    }

    /**
     * Removes channel handlers and stops background metadata reads for the detached engine.
     *
     * @param binding the Flutter engine context being detached
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
     * Validates log requests and writes their lines to Logcat in the original order.
     *
     * @param call the channel request containing the severity and message text
     * @param result the one-shot callback for success, invalid arguments, or an unsupported method
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
            result.error(
                "invalid_arguments",
                "Invalid log record",
                null
            );
            return;
        }

        Object level = call.argument("level");
        Object message = call.argument("message");
        int priority = priorityFor(level);
        if (priority == 0 || !(message instanceof String)) {
            result.error(
                "invalid_arguments",
                "Invalid log record",
                null
            );
            return;
        }

        for (String line : ((String) message).split("\n", -1)) {
            writeLine(
                priority,
                line
            );
        }

        result.success(null);
    }

    /**
     * Converts a Dart log severity to its system logging priority.
     *
     * @param level the debug, info, warning, or error severity name
     * @return the corresponding Logcat priority, or 0 for an unsupported name
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
     * Writes a log line in UTF-8 byte-limited chunks without splitting Unicode code points.
     *
     * All chunks retain the original order and severity.
     *
     * @param priority the Logcat priority for the line
     * @param line the single line of text to output
     */
    private static void writeLine(
        int priority,
        String line
    ) {
        // Count UTF-8 bytes by code point to avoid splitting characters or triggering truncation.
        int start = 0;
        int bytes = 0;
        for (int offset = 0; offset < line.length();) {
            int codePoint = line.codePointAt(offset);
            int size = codePoint <= 0x7f ? 1 : codePoint <= 0x7ff ? 2 : codePoint <= 0xffff ? 3 : 4;
            if (bytes + size > MAX_LINE_BYTES) {
                Log.println(
                    priority,
                    TAG,
                    line.substring(
                        start,
                        offset
                    )
                );
                start = offset;
                bytes = 0;
            }
            bytes += size;
            offset += Character.charCount(codePoint);
        }

        Log.println(
            priority,
            TAG,
            line.substring(start)
        );
    }
}

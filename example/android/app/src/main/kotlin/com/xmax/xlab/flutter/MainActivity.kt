package com.xmax.xlab.flutter

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var fileVideoDecoder: RealtimeFileVideoDecoder? = null
    private var videoRecorder: RealtimeVideoRecorder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fileVideoDecoder = RealtimeFileVideoDecoder(flutterEngine.dartExecutor.binaryMessenger)
        videoRecorder = RealtimeVideoRecorder(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        fileVideoDecoder?.dispose()
        fileVideoDecoder = null
        videoRecorder?.dispose()
        videoRecorder = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

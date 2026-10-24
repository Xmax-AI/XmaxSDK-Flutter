//
//  XmaxSDKPlugin.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import Flutter
import Foundation
import OSLog

/// Registers native logging and media metadata capabilities through Flutter's plugin lifecycle.
public final class XmaxSDKPlugin: NSObject, FlutterPlugin {

    /// The system logger receiving formatted SDK messages.
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// Registers logging and media metadata method channels.
    ///
    /// - Parameter registrar: The plugin registration context for the current Flutter engine.
    public static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        MediaFileMetadataManager.register(with: registrar)

        let channel = FlutterMethodChannel(
            name: "ai.xmax.sdk/logging",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(
            XmaxSDKPlugin(),
            channel: channel
        )
    }

    /// Validates log requests and writes each line to system logging in its original order.
    ///
    /// - Parameters:
    ///   - call: The log request containing a severity and message text.
    ///   - result: The one-shot callback for success, invalid arguments, or an unsupported method.
    public func handle(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard call.method == "log" else {
            result(FlutterMethodNotImplemented)
            return
        }

        guard let arguments = call.arguments as? [String: Any],
              let level = arguments["level"] as? String,
              let message = arguments["message"] as? String,
              ["debug", "info", "warning", "error"].contains(level) else {
            result(
                FlutterError(
                    code: "invalid_arguments",
                    message: "Invalid log record",
                    details: nil
                )
            )
            return
        }

        // Dart handles filtering and formatting; write individual lines to preserve readability.
        // System logs expose message text publicly, so messages must not contain credentials.
        for line in message.components(separatedBy: "\n") {
            switch level {
            case "debug": Self.logger.debug("\(line, privacy: .public)")
            case "info": Self.logger.info("\(line, privacy: .public)")
            case "warning": Self.logger.warning("\(line, privacy: .public)")
            default: Self.logger.error("\(line, privacy: .public)")
            }
        }

        result(nil)
    }
}

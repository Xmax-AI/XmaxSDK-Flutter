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

/// 注册原生日志和媒体元数据能力，由 Flutter 自动加载，无需宿主额外注册。
public final class XmaxSDKPlugin: NSObject, FlutterPlugin {

    /// 接收已格式化 SDK 日志的系统日志入口。
    private static let logger = Logger(
        subsystem: "ai.xmax.XmaxSDK",
        category: "XmaxSDK"
    )

    /// 注册日志与媒体元数据方法通道。
    ///
    /// - Parameter registrar: 当前 Flutter 引擎提供的插件注册上下文。
    public static func register(
        with registrar: FlutterPluginRegistrar
    ) {
        MediaFileMetadataManager.register(with: registrar)

        let channel = FlutterMethodChannel(
            name: "ai.xmax.sdk/logging",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(XmaxSDKPlugin(), channel: channel)
    }

    /// 校验日志请求，并按原有行序及等级输出到系统日志。
    ///
    /// - Parameters:
    ///   - call: 包含等级和消息文本的日志请求。
    ///   - result: 接收成功、参数错误或方法未实现通知的单次回调。
    ///
    /// 处理结果通过 result 通知。
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
            result(FlutterError(code: "invalid_arguments", message: "Invalid log record", details: nil))
            return
        }

        // Dart 层负责类别过滤和文本格式化；逐行输出以保留多行日志的可读性。
        // 系统日志使用公开文本，调用方不得在消息中包含访问凭证。
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

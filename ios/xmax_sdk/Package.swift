// swift-tools-version: 5.9
//
//  Package.swift
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-Flutter
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import PackageDescription

/// SDK 原生桥接模块的构建平台、产品和 Flutter 框架依赖配置。
let package = Package(
    name: "xmax_sdk",
    platforms: [.iOS("15.0")],
    products: [.library(name: "xmax-sdk", targets: ["xmax_sdk"])],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "xmax_sdk",
            dependencies: [.product(name: "FlutterFramework", package: "FlutterFramework")]
        )
    ]
)

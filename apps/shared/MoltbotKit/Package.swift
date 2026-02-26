// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MoltbotKit",
    platforms: [ // 支持的平台
        .iOS(.v18),     // iOS 18.0 及以上
        .macOS(.v15),   // macOS 15.0 及以上
    ],
    products: [ // 产品定义
        .library(name: "MoltbotProtocol", targets: ["MoltbotProtocol"]), // 协议库
        .library(name: "MoltbotKit", targets: ["MoltbotKit"]),             // 核心功能库
        .library(name: "MoltbotChatUI", targets: ["MoltbotChatUI"]),       // 聊天界面库
    ],
    dependencies: [ // 依赖包
        .package(url: "https://github.com/steipete/ElevenLabsKit", exact: "0.1.0"), // ElevenLabsKit 语音库
        .package(url: "https://github.com/gonzalezreal/textual", exact: "0.3.1"),   // Textual 文本处理库
    ],
    targets: [ // 目标模块
        .target(
            name: "MoltbotProtocol",  // 协议模块
            path: "Sources/MoltbotProtocol",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"), // 启用严格并发特性
            ]),
        .target(
            name: "MoltbotKit",  // 核心功能模块
            dependencies: [
                "MoltbotProtocol",
                .product(name: "ElevenLabsKit", package: "ElevenLabsKit"),
            ],
            path: "Sources/MoltbotKit",
            resources: [
                .process("Resources"), // 处理资源文件
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"), // 启用严格并发特性
            ]),
        .target(
            name: "MoltbotChatUI",  // 聊天界面模块
            dependencies: [
                "MoltbotKit",
                .product(
                    name: "Textual",
                    package: "textual",
                    condition: .when(platforms: [.macOS, .iOS])), // 仅在 macOS 和 iOS 平台使用
            ],
            path: "Sources/MoltbotChatUI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"), // 启用严格并发特性
            ]),
        .testTarget(
            name: "MoltbotKitTests",  // 测试模块
            dependencies: ["MoltbotKit", "MoltbotChatUI"],
            path: "Tests/MoltbotKitTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"), // 启用严格并发特性
                .enableExperimentalFeature("SwiftTesting"),  // 启用 SwiftTesting 实验特性
            ]),
    ])

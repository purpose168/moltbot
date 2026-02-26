// swift-tools-version: 6.2
// Moltbot macOS 配套应用的包清单文件（菜单栏应用 + IPC 库）。

import PackageDescription

let package = Package(
    name: "Moltbot",
    platforms: [
        .macOS(.v15),  // 最低支持 macOS 15 版本
    ],
    products: [
        // IPC（进程间通信）库
        .library(name: "MoltbotIPC", targets: ["MoltbotIPC"]),
        // 设备发现库
        .library(name: "MoltbotDiscovery", targets: ["MoltbotDiscovery"]),
        // 主应用可执行文件（菜单栏应用）
        .executable(name: "Moltbot", targets: ["Moltbot"]),
        // 命令行工具可执行文件
        .executable(name: "moltbot-mac", targets: ["MoltbotMacCLI"]),
    ],
    dependencies: [
        // 菜单栏额外访问功能库
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", exact: "1.2.2"),
        // Swift 子进程库
        .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "0.1.0"),
        // Apple 日志库
        .package(url: "https://github.com/apple/swift-log.git", from: "1.8.0"),
        // 应用自动更新库
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.1"),
        // 自动化测试库
        .package(url: "https://github.com/steipete/Peekaboo.git", branch: "main"),
        // 本地共享库
        .package(path: "../shared/MoltbotKit"),
        // 本地 Swabble 库
        .package(path: "../../Swabble"),
    ],
    targets: [
        // IPC 库目标
        .target(
            name: "MoltbotIPC",
            dependencies: [],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),  // 启用严格并发特性
            ]),
        // 设备发现库目标
        .target(
            name: "MoltbotDiscovery",
            dependencies: [
                .product(name: "MoltbotKit", package: "MoltbotKit"),
            ],
            path: "Sources/MoltbotDiscovery",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),  // 启用严格并发特性
            ]),
        // 主应用可执行目标
        .executableTarget(
            name: "Moltbot",
            dependencies: [
                "MoltbotIPC",
                "MoltbotDiscovery",
                .product(name: "MoltbotKit", package: "MoltbotKit"),
                .product(name: "MoltbotChatUI", package: "MoltbotKit"),
                .product(name: "MoltbotProtocol", package: "MoltbotKit"),
                .product(name: "SwabbleKit", package: "swabble"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
                .product(name: "Subprocess", package: "swift-subprocess"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "PeekabooBridge", package: "Peekaboo"),
                .product(name: "PeekabooAutomationKit", package: "Peekaboo"),
            ],
            exclude: [
                "Resources/Info.plist",  // 排除 Info.plist 文件
            ],
            resources: [
                .copy("Resources/Moltbot.icns"),  // 复制应用图标
                .copy("Resources/DeviceModels"),  // 复制设备模型资源
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),  // 启用严格并发特性
            ]),
        // 命令行工具可执行目标
        .executableTarget(
            name: "MoltbotMacCLI",
            dependencies: [
                "MoltbotDiscovery",
                .product(name: "MoltbotKit", package: "MoltbotKit"),
                .product(name: "MoltbotProtocol", package: "MoltbotKit"),
            ],
            path: "Sources/MoltbotMacCLI",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),  // 启用严格并发特性
            ]),
        // IPC 测试目标
        .testTarget(
            name: "MoltbotIPCTests",
            dependencies: [
                "MoltbotIPC",
                "Moltbot",
                "MoltbotDiscovery",
                .product(name: "MoltbotProtocol", package: "MoltbotKit"),
                .product(name: "SwabbleKit", package: "swabble"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),  // 启用严格并发特性
                .enableExperimentalFeature("SwiftTesting"),  // 启用 Swift 测试实验性特性
            ]),
    ])

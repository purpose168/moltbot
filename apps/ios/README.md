# Clawdbot (iOS)

仅供内部使用的 SwiftUI 应用脚手架。

## 代码检查/格式化（必需）
```bash
brew install swiftformat swiftlint
```

## 生成 Xcode 项目
```bash
cd apps/ios
xcodegen generate
open Clawdbot.xcodeproj
```

## 共享包
- `../shared/MoltbotKit` — iOS（以及后续的 macOS 桥接 + 网关路由）使用的共享类型/常量。

## fastlane
```bash
brew install fastlane

cd apps/ios
fastlane lanes
```

有关 App Store Connect 认证和上传通道的信息，请参阅 `apps/ios/fastlane/SETUP.md`。

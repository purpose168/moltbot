import Foundation
import Testing
@testable import MoltbotChatUI

#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// 计算颜色的亮度值
/// - 参数 color: 要计算亮度的 NSColor 对象
/// - 返回值: 颜色的亮度值，范围为 0.0 到 1.0
private func luminance(_ color: NSColor) throws -> CGFloat {
    let rgb = try #require(color.usingColorSpace(.deviceRGB))
    // 使用标准的相对 luminance 计算公式
    return 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
}
#endif

/// 聊天主题测试套件
@Suite struct ChatThemeTests {
    /// 测试助手气泡颜色在浅色和深色模式下的解析
    @Test func assistantBubbleResolvesForLightAndDark() throws {
        #if os(macOS)
        // 获取浅色外观 (Aqua)
        let lightAppearance = try #require(NSAppearance(named: .aqua))
        // 获取深色外观 (Dark Aqua)
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))

        // 解析浅色模式下的助手气泡颜色
        let lightResolved = MoltbotChatTheme.resolvedAssistantBubbleColor(for: lightAppearance)
        // 解析深色模式下的助手气泡颜色
        let darkResolved = MoltbotChatTheme.resolvedAssistantBubbleColor(for: darkAppearance)
        // 验证浅色模式下的颜色亮度大于深色模式下的颜色亮度
        #expect(try luminance(lightResolved) > luminance(darkResolved))
        #else
        // 在非 macOS 平台上，测试总是通过
        #expect(Bool(true))
        #endif
    }
}

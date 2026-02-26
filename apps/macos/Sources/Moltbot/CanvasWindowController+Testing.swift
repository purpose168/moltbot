#if DEBUG
import AppKit
import Foundation

/// CanvasWindowController 的测试扩展
/// 仅在 DEBUG 模式下可用，提供对私有方法的测试访问
extension CanvasWindowController {
    /// 测试会话密钥清理功能
    /// - Parameter key: 原始会话密钥
    /// - Returns: 清理后的会话密钥
    static func _testSanitizeSessionKey(_ key: String) -> String {
        self.sanitizeSessionKey(key)
    }

    /// 测试 JavaScript 字符串字面量处理
    /// - Parameter value: 原始字符串值
    /// - Returns: 适合在 JavaScript 中使用的字符串字面量
    static func _testJSStringLiteral(_ value: String) -> String {
        self.jsStringLiteral(value)
    }

    /// 测试可选 JavaScript 字符串字面量处理
    /// - Parameter value: 可选的原始字符串值
    /// - Returns: 适合在 JavaScript 中使用的可选字符串字面量
    static func _testJSOptionalStringLiteral(_ value: String?) -> String {
        self.jsOptionalStringLiteral(value)
    }

    /// 测试存储框架的默认键生成
    /// - Parameter sessionKey: 会话密钥
    /// - Returns: 用于存储框架的默认键
    static func _testStoredFrameKey(sessionKey: String) -> String {
        self.storedFrameDefaultsKey(sessionKey: sessionKey)
    }

    /// 测试存储和加载框架
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - frame: 要存储的框架矩形
    /// - Returns: 加载的框架矩形，如果没有找到则为 nil
    static func _testStoreAndLoadFrame(sessionKey: String, frame: NSRect) -> NSRect? {
        self.storeRestoredFrame(frame, sessionKey: sessionKey)
        return self.loadRestoredFrame(sessionKey: sessionKey)
    }

    /// 测试 IPv4 地址解析
    /// - Parameter host: 主机字符串
    /// - Returns: 解析后的 IPv4 地址元组 (a, b, c, d)，如果解析失败则为 nil
    static func _testParseIPv4(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        CanvasA2UIActionMessageHandler.parseIPv4(host)
    }

    /// 测试是否为本地网络 IPv4 地址
    /// - Parameter ip: IPv4 地址元组 (a, b, c, d)
    /// - Returns: 如果是本地网络地址则为 true，否则为 false
    static func _testIsLocalNetworkIPv4(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        CanvasA2UIActionMessageHandler.isLocalNetworkIPv4(ip)
    }

    /// 测试是否为本地网络 Canvas URL
    /// - Parameter url: 要测试的 URL
    /// - Returns: 如果是本地网络 Canvas URL 则为 true，否则为 false
    static func _testIsLocalNetworkCanvasURL(_ url: URL) -> Bool {
        CanvasA2UIActionMessageHandler.isLocalNetworkCanvasURL(url)
    }
}
#endif

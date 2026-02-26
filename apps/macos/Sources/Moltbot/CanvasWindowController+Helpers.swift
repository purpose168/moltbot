import AppKit
import Foundation

extension CanvasWindowController {
    // MARK: - 辅助方法

    /// 清理会话密钥，确保其只包含合法字符
    /// - Parameter key: 原始会话密钥
    /// - Returns: 清理后的会话密钥，如果原始密钥为空则返回 "main"
    static func sanitizeSessionKey(_ key: String) -> String {
        // 去除首尾空白字符和换行符
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果清理后为空，返回默认值 "main"
        if trimmed.isEmpty { return "main" }
        // 定义允许的字符集合
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-+")
        // 映射每个字符，将不允许的字符替换为下划线
        let scalars = trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        // 将字符数组转换为字符串并返回
        return String(scalars)
    }

    /// 将字符串转换为 JavaScript 字符串字面量
    /// - Parameter value: 要转换的字符串
    /// - Returns: 符合 JavaScript 语法的字符串字面量
    static func jsStringLiteral(_ value: String) -> String {
        // 使用 JSONEncoder 编码字符串，这样会自动处理转义
        let data = try? JSONEncoder().encode(value)
        // 将编码后的数据转换回字符串，如果失败则返回空字符串字面量
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    /// 将可选字符串转换为 JavaScript 字符串字面量
    /// - Parameter value: 可选的字符串值
    /// - Returns: 如果值为 nil 则返回 "null"，否则返回符合 JavaScript 语法的字符串字面量
    static func jsOptionalStringLiteral(_ value: String?) -> String {
        // 检查值是否为 nil
        guard let value else { return "null" }
        // 调用 jsStringLiteral 方法处理非 nil 值
        return Self.jsStringLiteral(value)
    }

    /// 生成用于存储窗口框架信息的 UserDefaults 键
    /// - Parameter sessionKey: 会话密钥
    /// - Returns: 格式化的 UserDefaults 键
    static func storedFrameDefaultsKey(sessionKey: String) -> String {
        // 清理会话密钥并与前缀组合
        "moltbot.canvas.frame.\(self.sanitizeSessionKey(sessionKey))"
    }

    /// 从 UserDefaults 加载存储的窗口框架信息
    /// - Parameter sessionKey: 会话密钥
    /// - Returns: 存储的窗口框架信息，如果不存在或无效则返回 nil
    static func loadRestoredFrame(sessionKey: String) -> NSRect? {
        // 生成存储键
        let key = self.storedFrameDefaultsKey(sessionKey: sessionKey)
        // 从 UserDefaults 获取值并验证格式
        guard let arr = UserDefaults.standard.array(forKey: key) as? [Double], arr.count == 4 else { return nil }
        // 从数组创建 NSRect
        let rect = NSRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
        // 验证窗口大小是否符合最小要求
        if rect.width < CanvasLayout.minPanelSize.width || rect.height < CanvasLayout.minPanelSize.height { return nil }
        // 返回有效的窗口框架
        return rect
    }

    /// 将窗口框架信息存储到 UserDefaults
    /// - Parameters:
    ///   - frame: 要存储的窗口框架
    ///   - sessionKey: 会话密钥
    static func storeRestoredFrame(_ frame: NSRect, sessionKey: String) {
        // 生成存储键
        let key = self.storedFrameDefaultsKey(sessionKey: sessionKey)
        // 将窗口框架的各个组件转换为 Double 数组并存储
        UserDefaults.standard.set(
            [Double(frame.origin.x), Double(frame.origin.y), Double(frame.size.width), Double(frame.size.height)],
            forKey: key)
    }
}

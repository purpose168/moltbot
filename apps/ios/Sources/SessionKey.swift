import Foundation

/// 会话键管理枚举
/// 用于处理和规范化会话键值
enum SessionKey {
    /// 规范化主会话键
    /// - Parameter raw: 原始字符串值
    /// - Returns: 规范化后的主会话键，如果输入为空则返回"main"
    static func normalizeMainKey(_ raw: String?) -> String {
        // 移除字符串两端的空白字符和换行符
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果修剪后为空，则返回默认值"main"，否则返回修剪后的值
        return trimmed.isEmpty ? "main" : trimmed
    }

    /// 检查是否为规范的主会话键
    /// - Parameter value: 要检查的字符串值
    /// - Returns: 如果是规范的主会话键则返回true，否则返回false
    static func isCanonicalMainSessionKey(_ value: String?) -> Bool {
        // 移除字符串两端的空白字符和换行符
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果修剪后为空，则返回false
        if trimmed.isEmpty { return false }
        // 如果值为"global"，则返回true
        if trimmed == "global" { return true }
        // 如果值以"agent:"开头，则返回true
        return trimmed.hasPrefix("agent:")
    }
}

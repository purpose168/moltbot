import Foundation

/// 表示主机和端口信息的结构体
/// 用于存储网络连接所需的主机地址和端口号
struct SettingsHostPort: Equatable {
    /// 主机地址
    var host: String
    /// 端口号
    var port: Int
}

/// 网络设置相关的辅助方法枚举
/// 提供主机端口解析和HTTP URL构建等功能
enum SettingsNetworkingHelpers {
    /// 从地址字符串解析主机和端口信息
    /// - Parameter address: 包含主机和端口的地址字符串，格式可以是 "host:port" 或 "[host]:port"
    /// - Returns: 解析成功返回包含主机和端口的 SettingsHostPort 对象，解析失败返回 nil
    static func parseHostPort(from address: String) -> SettingsHostPort? {
        // 移除首尾空白字符
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        // 检查字符串是否为空
        guard !trimmed.isEmpty else { return nil }

        // 处理 IPv6 格式的地址，如 "[host]:port"
        if trimmed.hasPrefix("["),
           let close = trimmed.firstIndex(of: "]"),
           close < trimmed.endIndex
        {
            // 提取括号内的主机地址
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            // 检查括号后是否有端口号
            let portStart = trimmed.index(after: close)
            guard portStart < trimmed.endIndex, trimmed[portStart] == ":" else { return nil }
            // 提取端口号字符串
            let portString = String(trimmed[trimmed.index(after: portStart)...])
            // 将端口号字符串转换为整数
            guard let port = Int(portString) else { return nil }
            return SettingsHostPort(host: host, port: port)
        }

        // 处理常规格式的地址，如 "host:port"
        guard let colon = trimmed.lastIndex(of: ":") else { return nil }
        // 提取冒号前的主机地址
        let host = String(trimmed[..<colon])
        // 提取冒号后的端口号字符串
        let portString = String(trimmed[trimmed.index(after: colon)...])
        // 检查主机地址是否为空，以及端口号是否能转换为整数
        guard !host.isEmpty, let port = Int(portString) else { return nil }
        return SettingsHostPort(host: host, port: port)
    }

    /// 构建HTTP URL字符串
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口号
    ///   - fallback: 当主机或端口为空时使用的默认值
    /// - Returns: 构建好的HTTP URL字符串
    static func httpURLString(host: String?, port: Int?, fallback: String) -> String {
        // 如果主机和端口都不为空
        if let host, let port {
            // 检查主机地址是否包含冒号（可能是IPv6地址），如果需要则添加括号
            let needsBrackets = host.contains(":") && !host.hasPrefix("[") && !host.hasSuffix("]")
            let hostPart = needsBrackets ? "[\(host)]" : host
            // 构建并返回HTTP URL字符串
            return "http://\(hostPart):\(port)"
        }
        // 如果主机或端口为空，使用默认值
        return "http://\(fallback)"
    }
}

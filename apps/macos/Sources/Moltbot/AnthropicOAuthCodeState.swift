import Foundation

/// Anthropic OAuth 认证代码状态解析器
/// 用于从各种格式的输入中提取和解析 `code#state` 格式的认证数据
enum AnthropicOAuthCodeState {
    /// 解析后的认证代码和状态
    struct Parsed: Equatable {
        /// OAuth 认证代码
        let code: String
        /// OAuth 状态参数
        let state: String
    }

    /// 从任意文本中提取 `code#state` 格式的认证数据
    /// 
    /// 支持以下格式：
    /// - 原始的 `code#state` 格式
    /// - 包含 `code=` 和 `state=` 查询参数的 OAuth 回调 URL
    /// - 带有前后文本或反引号的指令页面内容
    /// 
    /// - Parameter raw: 原始输入文本
    /// - Returns: 提取的 `code#state` 格式字符串，提取失败返回 nil
    static func extract(from raw: String) -> String? {
        // 清理输入文本：去除首尾空白字符和反引号
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        if text.isEmpty { return nil }

        // 尝试从 URL 中提取
        if let fromURL = self.extractFromURL(text) { return fromURL }
        // 尝试从原始令牌中提取
        if let fromToken = self.extractFromToken(text) { return fromToken }
        return nil
    }

    /// 从输入文本中解析认证代码和状态
    /// 
    /// - Parameter raw: 原始输入文本
    /// - Returns: 解析后的认证代码和状态，解析失败返回 nil
    static func parse(from raw: String) -> Parsed? {
        // 首先提取 `code#state` 格式的字符串
        guard let extracted = self.extract(from: raw) else { return nil }
        // 分割代码和状态
        let parts = extracted.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts.first ?? ""
        let state = parts.count > 1 ? parts[1] : ""
        // 验证代码和状态是否非空
        guard !code.isEmpty, !state.isEmpty else { return nil }
        return Parsed(code: code, state: state)
    }

    /// 从 URL 中提取认证代码和状态
    /// 
    /// 用户可能会从浏览器地址栏复制回调 URL
    /// 
    /// - Parameter text: 包含 URL 的文本
    /// - Returns: 提取的 `code#state` 格式字符串，提取失败返回 nil
    private static func extractFromURL(_ text: String) -> String? {
        guard let components = URLComponents(string: text),
              let items = components.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value,
              !code.isEmpty, !state.isEmpty
        else { return nil }

        return "\(code)#\(state)"
    }

    /// 从原始令牌中提取认证代码和状态
    /// 
    /// 基于 Base64url 格式的令牌；保持相当严格的匹配以避免误报
    /// 
    /// - Parameter text: 包含令牌的文本
    /// - Returns: 提取的 `code#state` 格式字符串，提取失败返回 nil
    private static func extractFromToken(_ text: String) -> String? {
        // 正则表达式模式：匹配 Base64url 格式的令牌
        let pattern = #"([A-Za-z0-9._~-]{8,})#([A-Za-z0-9._~-]{8,})"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, range: range),
              match.numberOfRanges == 3,
              let full = Range(match.range(at: 0), in: text)
        else { return nil }

        return String(text[full])
    }
}

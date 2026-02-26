import Foundation

/// 语音唤醒偏好设置
enum VoiceWakePreferences {
    /// 启用状态的存储键
    static let enabledKey = "voiceWake.enabled"
    /// 触发词的存储键
    static let triggerWordsKey = "voiceWake.triggerWords"

    /// 保持与Mac应用的默认值一致
    static let defaultTriggerWords: [String] = ["clawd", "claude"]
    /// 最大触发词数量
    static let maxWords = 32
    /// 单个触发词的最大长度
    static let maxWordLength = 64

    /// 从JSON字符串解码网关触发词
    /// - Parameter payloadJSON: JSON格式的字符串
    /// - Returns: 解码后的触发词数组，解码失败返回nil
    static func decodeGatewayTriggers(from payloadJSON: String) -> [String]? {
        guard let data = payloadJSON.data(using: .utf8) else { return nil }
        return self.decodeGatewayTriggers(from: data)
    }

    /// 从数据解码网关触发词
    /// - Parameter data: 包含触发词的Data
    /// - Returns: 解码后的触发词数组，解码失败返回nil
    static func decodeGatewayTriggers(from data: Data) -> [String]? {
        struct Payload: Decodable { var triggers: [String] }
        guard let decoded = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        return self.sanitizeTriggerWords(decoded.triggers)
    }

    /// 加载触发词
    /// - Parameter defaults: 用户默认存储，默认为标准存储
    /// - Returns: 存储的触发词数组，若不存在则返回默认值
    static func loadTriggerWords(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: self.triggerWordsKey) ?? self.defaultTriggerWords
    }

    /// 保存触发词
    /// - Parameters:
    ///   - words: 要保存的触发词数组
    ///   - defaults: 用户默认存储，默认为标准存储
    static func saveTriggerWords(_ words: [String], defaults: UserDefaults = .standard) {
        defaults.set(words, forKey: self.triggerWordsKey)
    }

    /// 清理触发词
    /// - Parameter words: 原始触发词数组
    /// - Returns: 清理后的触发词数组，移除空字符串并限制数量和长度
    static func sanitizeTriggerWords(_ words: [String]) -> [String] {
        let cleaned = words
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } // 去除首尾空白
            .filter { !$0.isEmpty } // 过滤空字符串
            .prefix(Self.maxWords) // 限制数量
            .map { String($0.prefix(Self.maxWordLength)) } // 限制长度
        return cleaned.isEmpty ? Self.defaultTriggerWords : cleaned // 若结果为空则返回默认值
    }

    /// 生成触发词的显示字符串
    /// - Parameter words: 触发词数组
    /// - Returns: 用逗号分隔的触发词字符串
    static func displayString(for words: [String]) -> String {
        let sanitized = self.sanitizeTriggerWords(words)
        return sanitized.joined(separator: ", ")
    }
}

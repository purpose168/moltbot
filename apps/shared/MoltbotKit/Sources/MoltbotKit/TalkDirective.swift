import Foundation

/// 语音指令结构体，用于配置语音合成的各种参数
public struct TalkDirective: Equatable, Sendable {
    /// 语音ID
    public var voiceId: String?
    /// 模型ID
    public var modelId: String?
    /// 语速
    public var speed: Double?
    /// 每分钟单词数
    public var rateWPM: Int?
    /// 稳定性
    public var stability: Double?
    /// 相似度
    public var similarity: Double?
    /// 风格强度
    public var style: Double?
    /// 说话人增强
    public var speakerBoost: Bool?
    /// 随机种子
    public var seed: Int?
    /// 文本标准化选项
    public var normalize: String?
    /// 语言
    public var language: String?
    /// 输出格式
    public var outputFormat: String?
    /// 延迟等级
    public var latencyTier: Int?
    /// 是否只执行一次
    public var once: Bool?

    /// 初始化语音指令
    /// - Parameters:
    ///   - voiceId: 语音ID
    ///   - modelId: 模型ID
    ///   - speed: 语速
    ///   - rateWPM: 每分钟单词数
    ///   - stability: 稳定性
    ///   - similarity: 相似度
    ///   - style: 风格强度
    ///   - speakerBoost: 说话人增强
    ///   - seed: 随机种子
    ///   - normalize: 文本标准化选项
    ///   - language: 语言
    ///   - outputFormat: 输出格式
    ///   - latencyTier: 延迟等级
    ///   - once: 是否只执行一次
    public init(
        voiceId: String? = nil,
        modelId: String? = nil,
        speed: Double? = nil,
        rateWPM: Int? = nil,
        stability: Double? = nil,
        similarity: Double? = nil,
        style: Double? = nil,
        speakerBoost: Bool? = nil,
        seed: Int? = nil,
        normalize: String? = nil,
        language: String? = nil,
        outputFormat: String? = nil,
        latencyTier: Int? = nil,
        once: Bool? = nil)
    {
        self.voiceId = voiceId
        self.modelId = modelId
        self.speed = speed
        self.rateWPM = rateWPM
        self.stability = stability
        self.similarity = similarity
        self.style = style
        self.speakerBoost = speakerBoost
        self.seed = seed
        self.normalize = normalize
        self.language = language
        self.outputFormat = outputFormat
        self.latencyTier = latencyTier
        self.once = once
    }
}

/// 语音指令解析结果结构体
public struct TalkDirectiveParseResult: Equatable, Sendable {
    /// 解析出的语音指令
    public let directive: TalkDirective?
    /// 去除指令后的文本
    public let stripped: String
    /// 未知的键值对
    public let unknownKeys: [String]

    /// 初始化解析结果
    /// - Parameters:
    ///   - directive: 解析出的语音指令
    ///   - stripped: 去除指令后的文本
    ///   - unknownKeys: 未知的键值对
    public init(directive: TalkDirective?, stripped: String, unknownKeys: [String]) {
        self.directive = directive
        self.stripped = stripped
        self.unknownKeys = unknownKeys
    }
}

/// 语音指令解析器
public enum TalkDirectiveParser {
    /// 解析文本中的语音指令
    /// - Parameter text: 包含语音指令的文本
    /// - Returns: 解析结果
    public static func parse(_ text: String) -> TalkDirectiveParseResult {
        // 标准化换行符
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        // 按换行符分割文本
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        // 如果文本为空，返回空结果
        guard !lines.isEmpty else { return TalkDirectiveParseResult(directive: nil, stripped: text, unknownKeys: []) }

        // 找到第一个非空行
        guard let firstNonEmptyIndex =
            lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else {
            return TalkDirectiveParseResult(directive: nil, stripped: text, unknownKeys: [])
        }

        var firstNonEmpty = firstNonEmptyIndex
        // 如果第一个非空行不是第一行，移除前面的空行
        if firstNonEmpty > 0 {
            lines.removeSubrange(0..<firstNonEmpty)
            firstNonEmpty = 0
        }

        // 获取第一行文本并去除首尾空白
        let head = lines[firstNonEmpty].trimmingCharacters(in: .whitespacesAndNewlines)
        // 检查是否是JSON格式（以{开头，以}结尾）
        guard head.hasPrefix("{"), head.hasSuffix("}") else {
            return TalkDirectiveParseResult(directive: nil, stripped: text, unknownKeys: [])
        }

        // 尝试将文本解析为JSON
        guard let data = head.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return TalkDirectiveParseResult(directive: nil, stripped: text, unknownKeys: [])
        }

        // 解析speakerBoost参数，支持多种键名格式
        let speakerBoost = self.boolValue(json, keys: ["speaker_boost", "speakerBoost"])
            ?? self.boolValue(json, keys: ["no_speaker_boost", "noSpeakerBoost"]).map { !$0 }

        // 构建语音指令
        let directive = TalkDirective(
            voiceId: stringValue(json, keys: ["voice", "voice_id", "voiceId"]),
            modelId: stringValue(json, keys: ["model", "model_id", "modelId"]),
            speed: doubleValue(json, keys: ["speed"]),
            rateWPM: intValue(json, keys: ["rate", "wpm"]),
            stability: doubleValue(json, keys: ["stability"]),
            similarity: doubleValue(json, keys: ["similarity", "similarity_boost", "similarityBoost"]),
            style: doubleValue(json, keys: ["style"]),
            speakerBoost: speakerBoost,
            seed: intValue(json, keys: ["seed"]),
            normalize: stringValue(json, keys: ["normalize", "apply_text_normalization"]),
            language: stringValue(json, keys: ["lang", "language_code", "language"]),
            outputFormat: stringValue(json, keys: ["output_format", "format"]),
            latencyTier: intValue(json, keys: ["latency", "latency_tier", "latencyTier"]),
            once: boolValue(json, keys: ["once"]))

        // 检查是否包含有效的指令参数
        let hasDirective = [
            directive.voiceId,
            directive.modelId,
            directive.speed.map { "\($0)" },
            directive.rateWPM.map { "\($0)" },
            directive.stability.map { "\($0)" },
            directive.similarity.map { "\($0)" },
            directive.style.map { "\($0)" },
            directive.speakerBoost.map { "\($0)" },
            directive.seed.map { "\($0)" },
            directive.normalize,
            directive.language,
            directive.outputFormat,
            directive.latencyTier.map { "\($0)" },
            directive.once.map { "\($0)" },
        ].contains { $0 != nil }

        // 如果没有有效的指令参数，返回空结果
        guard hasDirective else {
            return TalkDirectiveParseResult(directive: nil, stripped: text, unknownKeys: [])
        }

        // 定义已知的键名
        let knownKeys = Set([
            "voice", "voice_id", "voiceid",
            "model", "model_id", "modelid",
            "speed", "rate", "wpm",
            "stability", "similarity", "similarity_boost", "similarityboost",
            "style",
            "speaker_boost", "speakerboost",
            "no_speaker_boost", "nospeakerboost",
            "seed",
            "normalize", "apply_text_normalization",
            "lang", "language_code", "language",
            "output_format", "format",
            "latency", "latency_tier", "latencytier",
            "once",
        ])
        // 找出未知的键名
        let unknownKeys = json.keys.filter { !knownKeys.contains($0.lowercased()) }.sorted()

        // 移除指令行
        lines.remove(at: firstNonEmpty)
        // 如果移除后还有行，检查下一行是否为空，如果为空也移除
        if firstNonEmpty < lines.count {
            let next = lines[firstNonEmpty].trimmingCharacters(in: .whitespacesAndNewlines)
            if next.isEmpty {
                lines.remove(at: firstNonEmpty)
            }
        }

        // 重新组合剩余的文本
        let stripped = lines.joined(separator: "\n")
        // 返回解析结果
        return TalkDirectiveParseResult(directive: directive, stripped: stripped, unknownKeys: unknownKeys)
    }

    /// 从字典中获取字符串值
    /// - Parameters:
    ///   - dict: 字典
    ///   - keys: 可能的键名数组
    /// - Returns: 字符串值，如果不存在返回nil
    private static func stringValue(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// 从字典中获取双精度浮点数值
    /// - Parameters:
    ///   - dict: 字典
    ///   - keys: 可能的键名数组
    /// - Returns: 双精度浮点数值，如果不存在返回nil
    private static func doubleValue(_ dict: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = dict[key] as? Double { return value }
            if let value = dict[key] as? Int { return Double(value) }
            if let value = dict[key] as? String, let parsed = Double(value) { return parsed }
        }
        return nil
    }

    /// 从字典中获取整数值
    /// - Parameters:
    ///   - dict: 字典
    ///   - keys: 可能的键名数组
    /// - Returns: 整数值，如果不存在返回nil
    private static func intValue(_ dict: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            if let value = dict[key] as? Int { return value }
            if let value = dict[key] as? Double { return Int(value) }
            if let value = dict[key] as? String, let parsed = Int(value) { return parsed }
        }
        return nil
    }

    /// 从字典中获取布尔值
    /// - Parameters:
    ///   - dict: 字典
    ///   - keys: 可能的键名数组
    /// - Returns: 布尔值，如果不存在返回nil
    private static func boolValue(_ dict: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = dict[key] as? Bool { return value }
            if let value = dict[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "yes", "1"].contains(trimmed) { return true }
                if ["false", "no", "0"].contains(trimmed) { return false }
            }
        }
        return nil
    }
}

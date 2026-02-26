public enum TalkPromptBuilder: Sendable {
    /// 构建对话提示字符串
    /// - Parameters:
    ///   - transcript: 对话转录文本
    ///   - interruptedAtSeconds: 中断时间（秒），可选
    /// - Returns: 构建好的对话提示字符串
    public static func build(transcript: String, interruptedAtSeconds: Double?) -> String {
        var lines: [String] = [
            "对话模式已激活。请用简洁、口语化的语气回复。",
            "您可以选择在回复开头添加 JSON（第一行）来设置 ElevenLabs 语音（id 或别名），例如：{\"voice\":\"<id>\",\"once\":true}。",
        ]

        if let interruptedAtSeconds {
            let formatted = String(format: "%.1f", interruptedAtSeconds)
            lines.append("助手语音在 \(formatted)s 处被中断。")
        }

        lines.append("")
        lines.append(transcript)
        return lines.joined(separator: "\n")
    }
}

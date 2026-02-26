import Foundation

/// Moltbot Canvas A2UI JSONL 解析器
/// 用于处理 A2UI 协议的 JSONL 格式数据
public enum MoltbotCanvasA2UIJSONL: Sendable {
    /// 解析后的 JSONL 项目
    /// 包含行号和解析后的消息
    public struct ParsedItem: Sendable {
        /// 行号
        public var lineNumber: Int
        /// 解析后的消息内容
        public var message: AnyCodable

        /// 初始化解析项目
        /// - Parameters:
        ///   - lineNumber: 行号
        ///   - message: 解析后的消息
        public init(lineNumber: Int, message: AnyCodable) {
            self.lineNumber = lineNumber
            self.message = message
        }
    }

    /// 解析 JSONL 格式的文本
    /// - Parameter text: JSONL 格式的文本
    /// - Returns: 解析后的项目数组
    /// - Throws: 解析错误
    public static func parse(_ text: String) throws -> [ParsedItem] {
        var out: [ParsedItem] = []
        var lineNumber = 0
        // 按行分割文本
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            lineNumber += 1
            // 去除首尾空白字符
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            // 跳过空行
            if line.isEmpty { continue }
            // 将行转换为数据
            let data = Data(line.utf8)

            // 解码 JSON 数据
            let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
            // 添加到结果数组
            out.append(ParsedItem(lineNumber: lineNumber, message: decoded))
        }
        return out
    }

    /// 验证 A2UI v0.8 格式的消息
    /// - Parameter items: 解析后的项目数组
    /// - Throws: 验证错误
    public static func validateV0_8(_ items: [ParsedItem]) throws {
        // 允许的消息类型
        let allowed = Set([
            "beginRendering",    // 开始渲染
            "surfaceUpdate",     // 表面更新
            "dataModelUpdate",   // 数据模型更新
            "deleteSurface",     // 删除表面
        ])
        
        // 遍历每个项目进行验证
        for item in items {
            // 确保消息是 JSON 对象
            guard let dict = item.message.value as? [String: AnyCodable] else {
                throw NSError(domain: "A2UI", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "A2UI JSONL 行 \(item.lineNumber): 期望一个 JSON 对象",
                ])
            }

            // 检查是否包含 v0.9 版本的消息类型
            if dict.keys.contains("createSurface") {
                throw NSError(domain: "A2UI", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: """
                    A2UI JSONL 行 \(item.lineNumber): 看起来像 A2UI v0.9 版本 (`createSurface`)。
                    Canvas 当前支持 A2UI v0.8 服务器→客户端消息
                    (`beginRendering`, `surfaceUpdate`, `dataModelUpdate`, `deleteSurface`)。
                    """,
                ])
            }

            // 检查是否只包含一个允许的消息类型
            let matched = dict.keys.filter { allowed.contains($0) }
            if matched.count != 1 {
                let found = dict.keys.sorted().joined(separator: ", ")
                throw NSError(domain: "A2UI", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: """
                    A2UI JSONL 行 \(item.lineNumber): 期望恰好包含以下之一：\(allowed.sorted()
                        .joined(separator: ", "))；实际找到：\(found)
                    """,
                ])
            }
        }
    }

    /// 从 JSONL 文本解码消息
    /// - Parameter text: JSONL 格式的文本
    /// - Returns: 解码后的消息数组
    /// - Throws: 解析或验证错误
    public static func decodeMessagesFromJSONL(_ text: String) throws -> [AnyCodable] {
        // 解析文本
        let items = try self.parse(text)
        // 验证格式
        try self.validateV0_8(items)
        // 提取消息内容
        return items.map(\.message)
    }

    /// 将消息数组编码为 JSON 字符串
    /// - Parameter messages: 消息数组
    /// - Returns: 编码后的 JSON 字符串
    /// - Throws: 编码错误
    public static func encodeMessagesJSONArray(_ messages: [AnyCodable]) throws -> String {
        // 编码消息数组
        let data = try JSONEncoder().encode(messages)
        // 转换为 UTF-8 字符串
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "A2UI", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "无法将消息负载编码为 UTF-8",
            ])
        }
        return json
    }
}

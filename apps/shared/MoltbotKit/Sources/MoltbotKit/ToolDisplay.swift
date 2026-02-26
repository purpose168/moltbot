import Foundation

/// 工具显示摘要结构，用于展示工具的相关信息
public struct ToolDisplaySummary: Sendable, Equatable {
    /// 工具名称
    public let name: String
    /// 工具表情符号
    public let emoji: String
    /// 工具标题
    public let title: String
    /// 工具标签
    public let label: String
    /// 工具动词（可选）
    public let verb: String?
    /// 工具详情（可选）
    public let detail: String?

    /// 详情行，组合动词和详情
    public var detailLine: String? {
        var parts: [String] = []
        if let verb, !verb.isEmpty { parts.append(verb) }  // 添加动词（如果有）
        if let detail, !detail.isEmpty { parts.append(detail) }  // 添加详情（如果有）
        return parts.isEmpty ? nil : parts.joined(separator: " · ")  // 用" · "连接各部分
    }

    /// 摘要行，包含表情符号、标签和详情行
    public var summaryLine: String {
        if let detailLine {
            return "\(self.emoji) \(self.label): \(detailLine)"
        }
        return "\(self.emoji) \(self.label)"
    }
}

/// 工具显示注册表，用于解析和配置工具的显示信息
public enum ToolDisplayRegistry {
    /// 工具显示动作规范结构，用于从JSON解码
    private struct ToolDisplayActionSpec: Decodable {
        let label: String?
        let detailKeys: [String]?
    }

    /// 工具显示规范结构，用于从JSON解码
    private struct ToolDisplaySpec: Decodable {
        let emoji: String?
        let title: String?
        let label: String?
        let detailKeys: [String]?
        let actions: [String: ToolDisplayActionSpec]?
    }

    /// 工具显示配置结构，用于从JSON解码
    private struct ToolDisplayConfig: Decodable {
        let version: Int?
        let fallback: ToolDisplaySpec?
        let tools: [String: ToolDisplaySpec]?
    }

    /// 静态配置，加载自JSON文件或使用默认配置
    private static let config: ToolDisplayConfig = loadConfig()

    /// 解析工具显示信息
    /// - Parameters:
    ///   - name: 工具名称
    ///   - args: 工具参数
    ///   - meta: 元数据
    /// - Returns: 工具显示摘要
    public static func resolve(name: String?, args: AnyCodable?, meta: String? = nil) -> ToolDisplaySummary {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "tool"
        let key = trimmedName.lowercased()
        let spec = self.config.tools?[key]
        let fallback = self.config.fallback

        // 解析基本信息
        let emoji = spec?.emoji ?? fallback?.emoji ?? "🧩"
        let title = spec?.title ?? self.titleFromName(trimmedName)
        let label = spec?.label ?? trimmedName

        // 解析动作信息
        let actionRaw = self.valueForKeyPath(args, path: "action") as? String
        let action = actionRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        let actionSpec = action.flatMap { spec?.actions?[$0] }
        let verb = self.normalizeVerb(actionSpec?.label ?? action)

        // 解析详情信息
        var detail: String?
        if key == "read" {
            detail = self.readDetail(args)
        } else if key == "write" || key == "edit" || key == "attach" {
            detail = self.pathDetail(args)
        }

        // 尝试从detailKeys中获取详情
        let detailKeys = actionSpec?.detailKeys ?? spec?.detailKeys ?? fallback?.detailKeys ?? []
        if detail == nil {
            detail = self.firstValue(args, keys: detailKeys)
        }

        // 尝试使用元数据作为详情
        if detail == nil {
            detail = meta
        }

        // 缩短路径中的家目录为~
        if let detailValue = detail {
            detail = self.shortenHomeInString(detailValue)
        }

        // 返回工具显示摘要
        return ToolDisplaySummary(
            name: trimmedName,
            emoji: emoji,
            title: title,
            label: label,
            verb: verb,
            detail: detail)
    }

    /// 加载配置
    /// - Returns: 工具显示配置
    private static func loadConfig() -> ToolDisplayConfig {
        guard let url = MoltbotKitResources.bundle.url(forResource: "tool-display", withExtension: "json") else {
            return self.defaultConfig()
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ToolDisplayConfig.self, from: data)
        } catch {
            return self.defaultConfig()
        }
    }

    /// 默认配置
    /// - Returns: 默认工具显示配置
    private static func defaultConfig() -> ToolDisplayConfig {
        ToolDisplayConfig(
            version: 1,
            fallback: ToolDisplaySpec(
                emoji: "🧩",
                title: nil,
                label: nil,
                detailKeys: [
                    "command",
                    "path",
                    "url",
                    "targetUrl",
                    "targetId",
                    "ref",
                    "element",
                    "node",
                    "nodeId",
                    "id",
                    "requestId",
                    "to",
                    "channelId",
                    "guildId",
                    "userId",
                    "name",
                    "query",
                    "pattern",
                    "messageId",
                ],
                actions: nil),
            tools: [
                "bash": ToolDisplaySpec(
                    emoji: "🛠️",
                    title: "Bash",
                    label: nil,
                    detailKeys: ["command"],
                    actions: nil),
                "read": ToolDisplaySpec(
                    emoji: "📖",
                    title: "Read",
                    label: nil,
                    detailKeys: ["path"],
                    actions: nil),
                "write": ToolDisplaySpec(
                    emoji: "✍️",
                    title: "Write",
                    label: nil,
                    detailKeys: ["path"],
                    actions: nil),
                "edit": ToolDisplaySpec(
                    emoji: "📝",
                    title: "Edit",
                    label: nil,
                    detailKeys: ["path"],
                    actions: nil),
                "attach": ToolDisplaySpec(
                    emoji: "📎",
                    title: "Attach",
                    label: nil,
                    detailKeys: ["path", "url", "fileName"],
                    actions: nil),
                "process": ToolDisplaySpec(
                    emoji: "🧰",
                    title: "Process",
                    label: nil,
                    detailKeys: ["sessionId"],
                    actions: nil),
            ])
    }

    /// 从工具名称生成标题
    /// - Parameter name: 工具名称
    /// - Returns: 格式化后的标题
    private static func titleFromName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return "Tool" }
        return cleaned
            .split(separator: " ")
            .map { part in
                let upper = part.uppercased()
                if part.count <= 2, part == upper { return String(part) }
                return String(upper.prefix(1)) + String(part.lowercased().dropFirst())
            }
            .joined(separator: " ")
    }

    /// 规范化动词
    /// - Parameter value: 动词字符串
    /// - Returns: 规范化后的动词
    private static func normalizeVerb(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.replacingOccurrences(of: "_", with: " ")
    }

    /// 生成读取工具的详情
    /// - Parameter args: 工具参数
    /// - Returns: 读取工具的详情字符串
    private static func readDetail(_ args: AnyCodable?) -> String? {
        guard let path = valueForKeyPath(args, path: "path") as? String else { return nil }
        let offsetAny = self.valueForKeyPath(args, path: "offset")
        let limitAny = self.valueForKeyPath(args, path: "limit")
        let offset = (offsetAny as? Double) ?? (offsetAny as? Int).map(Double.init)
        let limit = (limitAny as? Double) ?? (limitAny as? Int).map(Double.init)
        if let offset, let limit {
            let end = offset + limit
            return "\(path):\(Int(offset))-\(Int(end))"
        }
        return path
    }

    /// 生成路径相关工具的详情
    /// - Parameter args: 工具参数
    /// - Returns: 路径相关工具的详情字符串
    private static func pathDetail(_ args: AnyCodable?) -> String? {
        self.valueForKeyPath(args, path: "path") as? String
    }

    /// 从键数组中获取第一个非空值
    /// - Parameters:
    ///   - args: 工具参数
    ///   - keys: 键数组
    /// - Returns: 第一个非空值
    private static func firstValue(_ args: AnyCodable?, keys: [String]) -> String? {
        for key in keys {
            if let value = valueForKeyPath(args, path: key),
               let rendered = renderValue(value)
            {
                return rendered
            }
        }
        return nil
    }

    /// 渲染值为字符串
    /// - Parameter value: 任意值
    /// - Returns: 渲染后的字符串
    private static func renderValue(_ value: Any) -> String? {
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let first = trimmed.split(whereSeparator: \.isNewline).first.map(String.init) ?? trimmed
            if first.count > 160 { return String(first.prefix(157)) + "…" }  // 过长时截断
            return first
        }
        if let num = value as? Int { return String(num) }
        if let num = value as? Double { return String(num) }
        if let bool = value as? Bool { return bool ? "true" : "false" }
        if let array = value as? [Any] {
            let items = array.compactMap { self.renderValue($0) }
            guard !items.isEmpty else { return nil }
            let preview = items.prefix(3).joined(separator: ", ")
            return items.count > 3 ? "\(preview)…" : preview  // 超过3个时截断
        }
        if let dict = value as? [String: Any] {
            if let label = dict["name"].flatMap({ renderValue($0) }) { return label }
            if let label = dict["id"].flatMap({ renderValue($0) }) { return label }
        }
        return nil
    }

    /// 根据键路径获取值
    /// - Parameters:
    ///   - args: 工具参数
    ///   - path: 键路径
    /// - Returns: 获取到的值
    private static func valueForKeyPath(_ args: AnyCodable?, path: String) -> Any? {
        guard let args else { return nil }
        let parts = path.split(separator: ".").map(String.init)  // 分割键路径
        var current: Any? = args.value
        for part in parts {
            if let dict = current as? [String: AnyCodable] {
                current = dict[part]?.value
            } else if let dict = current as? [String: Any] {
                current = dict[part]
            } else {
                return nil
            }
        }
        return current
    }

    /// 缩短字符串中的家目录为~
    /// - Parameter value: 原始字符串
    /// - Returns: 缩短后的字符串
    private static func shortenHomeInString(_ value: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return value }
        return value.replacingOccurrences(of: home, with: "~")
    }
}


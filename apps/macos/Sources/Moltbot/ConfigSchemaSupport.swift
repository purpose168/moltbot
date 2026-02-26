import Foundation

/// 配置路径段枚举
/// 
/// 用于表示配置路径中的不同类型的段
enum ConfigPathSegment: Hashable {
    /// 键值
    case key(String)
    /// 索引值
    case index(Int)
}

/// 配置路径类型，由配置路径段组成的数组
typealias ConfigPath = [ConfigPathSegment]

/// 配置UI提示
/// 
/// 包含配置项的UI相关提示信息
struct ConfigUiHint {
    /// 标签
    let label: String?
    /// 帮助文本
    let help: String?
    /// 排序顺序
    let order: Double?
    /// 是否高级选项
    let advanced: Bool?
    /// 是否敏感信息
    let sensitive: Bool?
    /// 占位符
    let placeholder: String?

    /// 初始化配置UI提示
    /// - Parameter raw: 原始字典数据
    init(raw: [String: Any]) {
        self.label = raw["label"] as? String
        self.help = raw["help"] as? String
        if let order = raw["order"] as? Double {
            self.order = order
        } else if let orderInt = raw["order"] as? Int {
            self.order = Double(orderInt)
        } else {
            self.order = nil
        }
        self.advanced = raw["advanced"] as? Bool
        self.sensitive = raw["sensitive"] as? Bool
        self.placeholder = raw["placeholder"] as? String
    }
}

/// 配置模式节点
/// 
/// 表示配置模式中的一个节点，包含配置的元数据和结构信息
struct ConfigSchemaNode {
    let raw: [String: Any]

    /// 初始化配置模式节点
    /// - Parameter raw: 原始数据
    init?(raw: Any) {
        guard let dict = raw as? [String: Any] else { return nil }
        self.raw = dict
    }

    /// 标题
    var title: String? { self.raw["title"] as? String }
    /// 描述
    var description: String? { self.raw["description"] as? String }
    /// 枚举值
    var enumValues: [Any]? { self.raw["enum"] as? [Any] }
    /// 常量值
    var constValue: Any? { self.raw["const"] }
    /// 显式默认值
    var explicitDefault: Any? { self.raw["default"] }
    /// 必填键
    var requiredKeys: Set<String> {
        Set((self.raw["required"] as? [String]) ?? [])
    }

    /// 类型列表
    var typeList: [String] {
        if let type = self.raw["type"] as? String { return [type] }
        if let types = self.raw["type"] as? [String] { return types }
        return []
    }

    /// 模式类型
    var schemaType: String? {
        let filtered = self.typeList.filter { $0 != "null" }
        if let first = filtered.first { return first }
        return self.typeList.first
    }

    /// 是否为空模式
    var isNullSchema: Bool {
        let types = self.typeList
        return types.count == 1 && types.first == "null"
    }

    /// 属性
    var properties: [String: ConfigSchemaNode] {
        guard let props = self.raw["properties"] as? [String: Any] else { return [:] }
        return props.compactMapValues { ConfigSchemaNode(raw: $0) }
    }

    /// 任意类型
    var anyOf: [ConfigSchemaNode] {
        guard let raw = self.raw["anyOf"] as? [Any] else { return [] }
        return raw.compactMap { ConfigSchemaNode(raw: $0) }
    }

    /// 一种类型
    var oneOf: [ConfigSchemaNode] {
        guard let raw = self.raw["oneOf"] as? [Any] else { return [] }
        return raw.compactMap { ConfigSchemaNode(raw: $0) }
    }

    /// 字面量值
    var literalValue: Any? {
        if let constValue { return constValue }
        if let enumValues, enumValues.count == 1 { return enumValues[0] }
        return nil
    }

    /// 数组项
    var items: ConfigSchemaNode? {
        if let items = self.raw["items"] as? [Any], let first = items.first {
            return ConfigSchemaNode(raw: first)
        }
        if let items = self.raw["items"] {
            return ConfigSchemaNode(raw: items)
        }
        return nil
    }

    /// 附加属性
    var additionalProperties: ConfigSchemaNode? {
        if let additional = self.raw["additionalProperties"] as? [String: Any] {
            return ConfigSchemaNode(raw: additional)
        }
        return nil
    }

    /// 是否允许附加属性
    var allowsAdditionalProperties: Bool {
        if let allow = self.raw["additionalProperties"] as? Bool { return allow }
        return self.additionalProperties != nil
    }

    /// 默认值
    var defaultValue: Any {
        if let value = self.raw["default"] { return value }
        switch self.schemaType {
        case "object":
            return [String: Any]()
        case "array":
            return [Any]()
        case "boolean":
            return false
        case "integer":
            return 0
        case "number":
            return 0.0
        case "string":
            return ""
        default:
            return ""
        }
    }

    /// 获取指定路径的节点
    /// - Parameter path: 配置路径
    /// - Returns: 配置模式节点
    func node(at path: ConfigPath) -> ConfigSchemaNode? {
        var current: ConfigSchemaNode? = self
        for segment in path {
            guard let node = current else { return nil }
            switch segment {
            case let .key(key):
                if node.schemaType == "object" {
                    if let next = node.properties[key] {
                        current = next
                        continue
                    }
                    if let additional = node.additionalProperties {
                        current = additional
                        continue
                    }
                    return nil
                }
                return nil
            case .index:
                guard node.schemaType == "array" else { return nil }
                current = node.items
            }
        }
        return current
    }
}

/// 解码UI提示
/// - Parameter raw: 原始字典数据
/// - Returns: 解码后的UI提示字典
func decodeUiHints(_ raw: [String: Any]) -> [String: ConfigUiHint] {
    raw.reduce(into: [:]) { result, entry in
        if let hint = entry.value as? [String: Any] {
            result[entry.key] = ConfigUiHint(raw: hint)
        }
    }
}

/// 获取路径对应的提示
/// - Parameters:
///   - path: 配置路径
///   - hints: UI提示字典
/// - Returns: 配置UI提示
func hintForPath(_ path: ConfigPath, hints: [String: ConfigUiHint]) -> ConfigUiHint? {
    let key = pathKey(path)
    if let direct = hints[key] { return direct }
    let segments = key.split(separator: ".").map(String.init)
    for (hintKey, hint) in hints {
        guard hintKey.contains("*") else { continue }
        let hintSegments = hintKey.split(separator: ".").map(String.init)
        guard hintSegments.count == segments.count else { continue }
        var match = true
        for (index, seg) in segments.enumerated() {
            let hintSegment = hintSegments[index]
            if hintSegment != "*", hintSegment != seg {
                match = false
                break
            }
        }
        if match { return hint }
    }
    return nil
}

/// 检查是否为敏感路径
/// - Parameter path: 配置路径
/// - Returns: 是否为敏感路径
func isSensitivePath(_ path: ConfigPath) -> Bool {
    let key = pathKey(path).lowercased()
    return key.contains("token")
        || key.contains("password")
        || key.contains("secret")
        || key.contains("apikey")
        || key.hasSuffix("key")
}

/// 获取路径键
/// - Parameter path: 配置路径
/// - Returns: 路径键字符串
func pathKey(_ path: ConfigPath) -> String {
    path.compactMap { segment -> String? in
        switch segment {
        case let .key(key): return key
        case .index: return nil
        }
    }
    .joined(separator: ".")
}

import MoltbotKit
import MoltbotProtocol
import Foundation

/// 使用 MoltbotKit 包装器来保持网关请求负载的一致性
typealias AnyCodable = MoltbotKit.AnyCodable
typealias InstanceIdentity = MoltbotKit.InstanceIdentity

/// AnyCodable 扩展
/// 提供便捷的属性来获取不同类型的值
extension AnyCodable {
    /// 获取字符串值
    var stringValue: String? { self.value as? String }
    /// 获取布尔值
    var boolValue: Bool? { self.value as? Bool }
    /// 获取整数值
    var intValue: Int? { self.value as? Int }
    /// 获取双精度浮点数值
    var doubleValue: Double? { self.value as? Double }
    /// 获取字典值
    var dictionaryValue: [String: AnyCodable]? { self.value as? [String: AnyCodable] }
    /// 获取数组值
    var arrayValue: [AnyCodable]? { self.value as? [AnyCodable] }

    /// 获取基础值（递归转换嵌套的 AnyCodable 结构为基础类型）
    var foundationValue: Any {
        switch self.value {
        case let dict as [String: AnyCodable]:
            // 递归转换字典中的每个值
            dict.mapValues { $0.foundationValue }
        case let array as [AnyCodable]:
            // 递归转换数组中的每个值
            array.map(\.foundationValue)
        default:
            // 对于其他类型，直接返回原始值
            self.value
        }
    }
}

/// MoltbotProtocol.AnyCodable 扩展
/// 为协议中的 AnyCodable 类型提供便捷的属性
extension MoltbotProtocol.AnyCodable {
    /// 获取字符串值
    var stringValue: String? { self.value as? String }
    /// 获取布尔值
    var boolValue: Bool? { self.value as? Bool }
    /// 获取整数值
    var intValue: Int? { self.value as? Int }
    /// 获取双精度浮点数值
    var doubleValue: Double? { self.value as? Double }
    /// 获取字典值
    var dictionaryValue: [String: MoltbotProtocol.AnyCodable]? { self.value as? [String: MoltbotProtocol.AnyCodable] }
    /// 获取数组值
    var arrayValue: [MoltbotProtocol.AnyCodable]? { self.value as? [MoltbotProtocol.AnyCodable] }

    /// 获取基础值（递归转换嵌套的 AnyCodable 结构为基础类型）
    var foundationValue: Any {
        switch self.value {
        case let dict as [String: MoltbotProtocol.AnyCodable]:
            // 递归转换字典中的每个值
            dict.mapValues { $0.foundationValue }
        case let array as [MoltbotProtocol.AnyCodable]:
            // 递归转换数组中的每个值
            array.map(\.foundationValue)
        default:
            // 对于其他类型，直接返回原始值
            self.value
        }
    }
}

import Foundation

/// 轻量级 `Codable` 包装器，用于处理异构 JSON 数据的双向转换。
/// 标记为 `@unchecked Sendable` 因为它可以持有引用类型。
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    /// 初始化方法，接受任意类型的值
    /// - Parameter value: 要包装的任意类型值
    public init(_ value: Any) { self.value = value }

    /// 从解码器初始化，处理各种类型的解码
    /// - Parameter decoder: 解码器实例
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { self.value = intVal; return }  // 解码整数类型
        if let doubleVal = try? container.decode(Double.self) { self.value = doubleVal; return }  // 解码浮点数类型
        if let boolVal = try? container.decode(Bool.self) { self.value = boolVal; return }  // 解码布尔类型
        if let stringVal = try? container.decode(String.self) { self.value = stringVal; return }  // 解码字符串类型
        if container.decodeNil() { self.value = NSNull(); return }  // 解码空值
        if let dict = try? container.decode([String: AnyCodable].self) { self.value = dict; return }  // 解码字典类型
        if let array = try? container.decode([AnyCodable].self) { self.value = array; return }  // 解码数组类型
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "不支持的类型")  // 抛出不支持类型的错误
    }

    /// 编码到编码器，处理各种类型的编码
    /// - Parameter encoder: 编码器实例
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self.value {
        case let intVal as Int: try container.encode(intVal)  // 编码整数类型
        case let doubleVal as Double: try container.encode(doubleVal)  // 编码浮点数类型
        case let boolVal as Bool: try container.encode(boolVal)  // 编码布尔类型
        case let stringVal as String: try container.encode(stringVal)  // 编码字符串类型
        case is NSNull: try container.encodeNil()  // 编码空值
        case let dict as [String: AnyCodable]: try container.encode(dict)  // 编码字典类型
        case let array as [AnyCodable]: try container.encode(array)  // 编码数组类型
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })  // 编码[String: Any]类型
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })  // 编码[Any]类型
        case let dict as NSDictionary:
            var converted: [String: AnyCodable] = [:]
            for (k, v) in dict {
                guard let key = k as? String else { continue }
                converted[key] = AnyCodable(v)
            }
            try container.encode(converted)  // 编码NSDictionary类型
        case let array as NSArray:
            try container.encode(array.map { AnyCodable($0) })  // 编码NSArray类型
        default:
            let context = EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "不支持的类型")  // 抛出不支持类型的错误
            throw EncodingError.invalidValue(self.value, context)
        }
    }
}

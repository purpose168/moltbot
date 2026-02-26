import MoltbotProtocol
import Foundation

/// 网关负载解码工具枚举
/// 
/// 提供了将 AnyCodable 类型解码为指定 Decodable 类型的静态方法
public enum GatewayPayloadDecoding {
    /// 将 MoltbotProtocol.AnyCodable 解码为指定类型
    /// 
    /// - Parameters:
    ///   - payload: 要解码的 AnyCodable 实例
    ///   - type: 目标解码类型（默认为 T.self）
    /// - Returns: 解码后的 T 类型实例
    /// - Throws: 解码过程中可能抛出的错误
    public static func decode<T: Decodable>(
        _ payload: MoltbotProtocol.AnyCodable,
        as _: T.Type = T.self) throws -> T
    {
        // 首先将 AnyCodable 编码为 JSON 数据
        let data = try JSONEncoder().encode(payload)
        // 然后将 JSON 数据解码为指定类型
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 将 AnyCodable 解码为指定类型
    /// 
    /// - Parameters:
    ///   - payload: 要解码的 AnyCodable 实例
    ///   - type: 目标解码类型（默认为 T.self）
    /// - Returns: 解码后的 T 类型实例
    /// - Throws: 解码过程中可能抛出的错误
    public static func decode<T: Decodable>(
        _ payload: AnyCodable,
        as _: T.Type = T.self) throws -> T
    {
        // 首先将 AnyCodable 编码为 JSON 数据
        let data = try JSONEncoder().encode(payload)
        // 然后将 JSON 数据解码为指定类型
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 将可选的 MoltbotProtocol.AnyCodable 解码为指定类型
    /// 
    /// - Parameters:
    ///   - payload: 可选的 AnyCodable 实例
    ///   - type: 目标解码类型（默认为 T.self）
    /// - Returns: 解码后的 T 类型实例，若 payload 为 nil 则返回 nil
    /// - Throws: 解码过程中可能抛出的错误
    public static func decodeIfPresent<T: Decodable>(
        _ payload: MoltbotProtocol.AnyCodable?,
        as _: T.Type = T.self) throws -> T?
    {
        // 若 payload 为 nil，直接返回 nil
        guard let payload else { return nil }
        // 否则调用 decode 方法进行解码
        return try self.decode(payload, as: T.self)
    }

    /// 将可选的 AnyCodable 解码为指定类型
    /// 
    /// - Parameters:
    ///   - payload: 可选的 AnyCodable 实例
    ///   - type: 目标解码类型（默认为 T.self）
    /// - Returns: 解码后的 T 类型实例，若 payload 为 nil 则返回 nil
    /// - Throws: 解码过程中可能抛出的错误
    public static func decodeIfPresent<T: Decodable>(
        _ payload: AnyCodable?,
        as _: T.Type = T.self) throws -> T?
    {
        // 若 payload 为 nil，直接返回 nil
        guard let payload else { return nil }
        // 否则调用 decode 方法进行解码
        return try self.decode(payload, as: T.self)
    }
}

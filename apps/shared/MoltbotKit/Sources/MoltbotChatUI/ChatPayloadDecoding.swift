import MoltbotKit
import Foundation

/// 聊天负载解码
enum 聊天负载解码 {
    /// 解码指定类型的负载数据
    /// - Parameters:
    ///   - payload: 要解码的负载数据
    ///   - type: 目标解码类型（默认使用泛型类型）
    /// - Returns: 解码后的指定类型对象
    /// - Throws: 解码过程中的错误
    static func 解码<T: Decodable>(_ payload: AnyCodable, as _: T.Type = T.self) throws -> T {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

import MoltbotProtocol
import Foundation

/// 当网关响应 `{ ok: false }` 时出现的结构化错误。
public struct GatewayResponseError: LocalizedError, @unchecked Sendable {
    /// 请求方法
    public let method: String
    /// 错误代码
    public let code: String
    /// 错误信息
    public let message: String
    /// 错误详情
    public let details: [String: AnyCodable]

    /// 初始化网关响应错误
    /// - Parameters:
    ///   - method: 请求方法
    ///   - code: 错误代码（可选）
    ///   - message: 错误信息（可选）
    ///   - details: 错误详情（可选）
    public init(method: String, code: String?, message: String?, details: [String: AnyCodable]?) {
        self.method = method
        // 如果提供了非空的错误代码，则使用该代码；否则使用默认的 "GATEWAY_ERROR"
        self.code = (code?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? code!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "GATEWAY_ERROR"
        // 如果提供了非空的错误信息，则使用该信息；否则使用默认的 "gateway error"
        self.message = (message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? message!.trimmingCharacters(in: .whitespacesAndNewlines)
            : "gateway error"
        // 如果提供了错误详情，则使用该详情；否则使用空字典
        self.details = details ?? [:]
    }

    /// 错误描述
    public var errorDescription: String? {
        // 如果错误代码是默认的 "GATEWAY_ERROR"，则只返回方法和错误信息
        if self.code == "GATEWAY_ERROR" { return "\(self.method): \(self.message)" }
        // 否则返回方法、错误代码和错误信息
        return "\(self.method): [\(self.code)] \(self.message)"
    }
}

/// 网关解码错误，当无法解析网关响应时出现
public struct GatewayDecodingError: LocalizedError, Sendable {
    /// 请求方法
    public let method: String
    /// 错误信息
    public let message: String

    /// 初始化网关解码错误
    /// - Parameters:
    ///   - method: 请求方法
    ///   - message: 错误信息
    public init(method: String, message: String) {
        self.method = method
        self.message = message
    }

    /// 错误描述
    public var errorDescription: String? { "\(self.method): \(self.message)" }
}

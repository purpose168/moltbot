import Foundation

/// Moltbot节点错误代码枚举
/// 定义了与节点通信相关的各种错误类型
public enum MoltbotNodeErrorCode: String, Codable, Sendable {
    case notPaired = "NOT_PAIRED"              // 未配对
    case unauthorized = "UNAUTHORIZED"          // 未授权
    case backgroundUnavailable = "NODE_BACKGROUND_UNAVAILABLE"  // 后台不可用
    case invalidRequest = "INVALID_REQUEST"      // 请求无效
    case unavailable = "UNAVAILABLE"            // 服务不可用
}

/// Moltbot节点错误结构体
/// 实现了Error、Codable、Sendable和Equatable协议，用于表示与节点通信时的错误信息
public struct MoltbotNodeError: Error, Codable, Sendable, Equatable {
    public var code: MoltbotNodeErrorCode  // 错误代码
    public var message: String             // 错误消息
    public var retryable: Bool?            // 是否可重试
    public var retryAfterMs: Int?          // 重试等待时间（毫秒）

    /// 初始化方法
    /// - Parameters:
    ///   - code: 错误代码
    ///   - message: 错误消息
    ///   - retryable: 是否可重试
    ///   - retryAfterMs: 重试等待时间（毫秒）
    public init(
        code: MoltbotNodeErrorCode,
        message: String,
        retryable: Bool? = nil,
        retryAfterMs: Int? = nil)
    {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.retryAfterMs = retryAfterMs
    }
}

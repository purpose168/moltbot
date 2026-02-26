import Foundation

/// 聊天传输事件枚举
/// 定义了与聊天传输相关的各种事件类型
public enum MoltbotChatTransportEvent: Sendable {
    case health(ok: Bool)               /// 健康状态事件，指示连接是否正常
    case tick                           /// 心跳事件
    case chat(MoltbotChatEventPayload)  /// 聊天消息事件
    case agent(MoltbotAgentEventPayload) /// 代理事件
    case seqGap                         /// 序列间隙事件，指示消息序列中存在间隙
}

/// 聊天传输协议
/// 定义了与聊天服务进行通信的接口
public protocol MoltbotChatTransport: Sendable {
    /// 请求聊天历史记录
    /// - Parameter sessionKey: 会话密钥
    /// - Returns: 聊天历史记录 payload
    func requestHistory(sessionKey: String) async throws -> MoltbotChatHistoryPayload
    
    /// 发送消息
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - message: 消息内容
    ///   - thinking: 思考内容
    ///   - idempotencyKey: 幂等键，用于确保消息只被处理一次
    ///   - attachments: 附件列表
    /// - Returns: 发送消息的响应
    func sendMessage(
        sessionKey: String,
        message: String,
        thinking: String,
        idempotencyKey: String,
        attachments: [MoltbotChatAttachmentPayload]) async throws -> MoltbotChatSendResponse

    /// 中止运行
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - runId: 运行 ID
    func abortRun(sessionKey: String, runId: String) async throws
    
    /// 列出会话
    /// - Parameter limit: 限制返回的会话数量
    /// - Returns: 会话列表响应
    func listSessions(limit: Int?) async throws -> MoltbotChatSessionsListResponse

    /// 请求健康状态
    /// - Parameter timeoutMs: 超时时间（毫秒）
    /// - Returns: 健康状态，true 表示正常
    func requestHealth(timeoutMs: Int) async throws -> Bool
    
    /// 获取事件流
    /// - Returns: 事件异步流
    func events() -> AsyncStream<MoltbotChatTransportEvent>

    /// 设置活动会话密钥
    /// - Parameter sessionKey: 会话密钥
    func setActiveSessionKey(_ sessionKey: String) async throws
}

/// 聊天传输协议扩展
/// 提供了默认实现
 extension MoltbotChatTransport {
    /// 设置活动会话密钥的默认实现（空实现）
    public func setActiveSessionKey(_: String) async throws {}

    /// 中止运行的默认实现（抛出不支持的错误）
    public func abortRun(sessionKey _: String, runId _: String) async throws {
        throw NSError(
            domain: "MoltbotChatTransport",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "chat.abort not supported by this transport"])
    }

    /// 列出会话的默认实现（抛出不支持的错误）
    public func listSessions(limit _: Int?) async throws -> MoltbotChatSessionsListResponse {
        throw NSError(
            domain: "MoltbotChatTransport",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "sessions.list not supported by this transport"])
    }
}

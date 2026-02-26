import MoltbotChatUI
import MoltbotKit
import MoltbotProtocol
import Foundation

/// iOS 网关聊天传输实现
/// 
/// 该结构体实现了 MoltbotChatTransport 协议，用于处理与网关的通信，包括发送消息、获取会话历史、订阅事件等功能。
struct IOSGatewayChatTransport: MoltbotChatTransport, Sendable {
    /// 网关节点会话，用于与网关进行通信
    private let gateway: GatewayNodeSession

    /// 初始化方法
    /// - Parameter gateway: 网关节点会话实例
    init(gateway: GatewayNodeSession) {
        self.gateway = gateway
    }

    /// 中止运行中的会话
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - runId: 运行 ID
    func abortRun(sessionKey: String, runId: String) async throws {
        /// 请求参数结构体
        struct Params: Codable {
            var sessionKey: String  // 会话密钥
            var runId: String       // 运行 ID
        }
        
        // 编码参数为 JSON 数据
        let data = try JSONEncoder().encode(Params(sessionKey: sessionKey, runId: runId))
        let json = String(data: data, encoding: .utf8)
        // 发送中止请求到网关
        _ = try await self.gateway.request(method: "chat.abort", paramsJSON: json, timeoutSeconds: 10)
    }

    /// 获取会话列表
    /// - Parameter limit: 限制返回的会话数量
    /// - Returns: 会话列表响应
    func listSessions(limit: Int?) async throws -> MoltbotChatSessionsListResponse {
        /// 请求参数结构体
        struct Params: Codable {
            var includeGlobal: Bool  // 是否包含全局会话
            var includeUnknown: Bool // 是否包含未知会话
            var limit: Int?          // 限制返回数量
        }
        
        // 编码参数为 JSON 数据
        let data = try JSONEncoder().encode(Params(includeGlobal: true, includeUnknown: false, limit: limit))
        let json = String(data: data, encoding: .utf8)
        // 发送会话列表请求到网关
        let res = try await self.gateway.request(method: "sessions.list", paramsJSON: json, timeoutSeconds: 15)
        // 解码响应数据
        return try JSONDecoder().decode(MoltbotChatSessionsListResponse.self, from: res)
    }

    /// 设置活动会话密钥
    /// - Parameter sessionKey: 要设置为活动状态的会话密钥
    func setActiveSessionKey(_ sessionKey: String) async throws {
        /// 订阅参数结构体
        struct Subscribe: Codable { var sessionKey: String }
        
        // 编码参数为 JSON 数据
        let data = try JSONEncoder().encode(Subscribe(sessionKey: sessionKey))
        let json = String(data: data, encoding: .utf8)
        // 发送订阅事件到网关
        await self.gateway.sendEvent(event: "chat.subscribe", payloadJSON: json)
    }

    /// 请求会话历史
    /// - Parameter sessionKey: 会话密钥
    /// - Returns: 会话历史 payload
    func requestHistory(sessionKey: String) async throws -> MoltbotChatHistoryPayload {
        /// 请求参数结构体
        struct Params: Codable { var sessionKey: String }
        
        // 编码参数为 JSON 数据
        let data = try JSONEncoder().encode(Params(sessionKey: sessionKey))
        let json = String(data: data, encoding: .utf8)
        // 发送历史请求到网关
        let res = try await self.gateway.request(method: "chat.history", paramsJSON: json, timeoutSeconds: 15)
        // 解码响应数据
        return try JSONDecoder().decode(MoltbotChatHistoryPayload.self, from: res)
    }

    /// 发送消息
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - message: 消息内容
    ///   - thinking: 思考内容
    ///   - idempotencyKey: 幂等性密钥
    ///   - attachments: 附件列表
    /// - Returns: 发送响应
    func sendMessage(
        sessionKey: String,
        message: String,
        thinking: String,
        idempotencyKey: String,
        attachments: [MoltbotChatAttachmentPayload]) async throws -> MoltbotChatSendResponse
    {
        /// 请求参数结构体
        struct Params: Codable {
            var sessionKey: String                      // 会话密钥
            var message: String                         // 消息内容
            var thinking: String                        // 思考内容
            var attachments: [MoltbotChatAttachmentPayload]? // 附件列表
            var timeoutMs: Int                          // 超时时间（毫秒）
            var idempotencyKey: String                  // 幂等性密钥
        }

        // 创建参数实例
        let params = Params(
            sessionKey: sessionKey,
            message: message,
            thinking: thinking,
            attachments: attachments.isEmpty ? nil : attachments,
            timeoutMs: 30000,  // 30秒超时
            idempotencyKey: idempotencyKey)
        
        // 编码参数为 JSON 数据
        let data = try JSONEncoder().encode(params)
        let json = String(data: data, encoding: .utf8)
        // 发送消息请求到网关
        let res = try await self.gateway.request(method: "chat.send", paramsJSON: json, timeoutSeconds: 35)
        // 解码响应数据
        return try JSONDecoder().decode(MoltbotChatSendResponse.self, from: res)
    }

    /// 请求健康状态
    /// - Parameter timeoutMs: 超时时间（毫秒）
    /// - Returns: 健康状态（true 表示健康）
    func requestHealth(timeoutMs: Int) async throws -> Bool {
        // 将毫秒转换为秒
        let seconds = max(1, Int(ceil(Double(timeoutMs) / 1000.0)))
        // 发送健康检查请求到网关
        let res = try await self.gateway.request(method: "health", paramsJSON: nil, timeoutSeconds: seconds)
        // 解码响应数据，默认为健康
        return (try? JSONDecoder().decode(MoltbotGatewayHealthOK.self, from: res))?.ok ?? true
    }

    /// 获取事件流
    /// - Returns: 聊天传输事件的异步流
    func events() -> AsyncStream<MoltbotChatTransportEvent> {
        AsyncStream { continuation in
            let task = Task {
                // 订阅服务器事件
                let stream = await self.gateway.subscribeServerEvents()
                // 处理接收到的事件
                for await evt in stream {
                    if Task.isCancelled { return }
                    
                    switch evt.event {
                    case "tick":
                        // 发送 tick 事件
                        continuation.yield(.tick)
                    case "seqGap":
                        // 发送序列间隙事件
                        continuation.yield(.seqGap)
                    case "health":
                        // 处理健康状态事件
                        guard let payload = evt.payload else { break }
                        let ok = (try? GatewayPayloadDecoding.decode(
                            payload,
                            as: MoltbotGatewayHealthOK.self))?.ok ?? true
                        continuation.yield(.health(ok: ok))
                    case "chat":
                        // 处理聊天事件
                        guard let payload = evt.payload else { break }
                        if let chatPayload = try? GatewayPayloadDecoding.decode(
                            payload,
                            as: MoltbotChatEventPayload.self)
                        {
                            continuation.yield(.chat(chatPayload))
                        }
                    case "agent":
                        // 处理代理事件
                        guard let payload = evt.payload else { break }
                        if let agentPayload = try? GatewayPayloadDecoding.decode(
                            payload,
                            as: MoltbotAgentEventPayload.self)
                        {
                            continuation.yield(.agent(agentPayload))
                        }
                    default:
                        // 忽略其他事件
                        break
                    }
                }
            }

            // 处理终止事件
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
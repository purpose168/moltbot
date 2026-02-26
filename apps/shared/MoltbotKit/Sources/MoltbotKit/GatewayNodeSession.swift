import MoltbotProtocol
import Foundation
import OSLog

/// 节点调用请求负载结构
/// 用于编码和解码节点调用请求的数据
private struct NodeInvokeRequestPayload: Codable, Sendable {
    var id: String              // 请求唯一标识符
    var nodeId: String          // 节点标识符
    var command: String         // 要执行的命令
    var paramsJSON: String?     // 命令参数的 JSON 字符串
    var timeoutMs: Int?         // 超时时间（毫秒）
    var idempotencyKey: String? // 幂等键，用于确保操作的幂等性
}

/// 网关节点会话类
/// 负责管理与网关的连接，处理事件和调用请求
public actor GatewayNodeSession {
    private let logger = Logger(subsystem: "bot.molt", category: "node.gateway")
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var channel: GatewayChannelActor?         // 网关通道实例
    private var activeURL: URL?                       // 当前活跃的连接 URL
    private var activeToken: String?                  // 当前活跃的令牌
    private var activePassword: String?               // 当前活跃的密码
    private var connectOptions: GatewayConnectOptions? // 连接选项
    private var onConnected: (@Sendable () async -> Void)? // 连接成功回调
    private var onDisconnected: (@Sendable (String) async -> Void)? // 断开连接回调
    private var onInvoke: (@Sendable (BridgeInvokeRequest) async -> BridgeInvokeResponse)? // 调用请求回调

    /// 带超时的调用方法
    /// - Parameters:
    ///   - request: 桥接调用请求
    ///   - timeoutMs: 超时时间（毫秒）
    ///   - onInvoke: 调用处理闭包
    /// - Returns: 桥接调用响应
    static func invokeWithTimeout(
        request: BridgeInvokeRequest,
        timeoutMs: Int?,
        onInvoke: @escaping @Sendable (BridgeInvokeRequest) async -> BridgeInvokeResponse
    ) async -> BridgeInvokeResponse {
        let timeout = max(0, timeoutMs ?? 0)
        guard timeout > 0 else {
            return await onInvoke(request)
        }

        return await withTaskGroup(of: BridgeInvokeResponse.self) { group in
            // 添加执行调用的任务
            group.addTask { await onInvoke(request) }
            // 添加超时任务
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout) * 1_000_000)
                return BridgeInvokeResponse(
                    id: request.id,
                    ok: false,
                    error: MoltbotNodeError(
                        code: .unavailable,
                        message: "节点调用超时")
                )
            }

            // 获取第一个完成的任务结果
            let first = await group.next()!
            // 取消所有其他任务
            group.cancelAll()
            return first
        }
    }
    
    private var serverEventSubscribers: [UUID: AsyncStream<EventFrame>.Continuation] = [:] // 服务器事件订阅者
    private var canvasHostUrl: String? // Canvas 主机 URL

    /// 初始化方法
    public init() {}

    /// 连接到网关
    /// - Parameters:
    ///   - url: 网关 URL
    ///   - token: 认证令牌
    ///   - password: 认证密码
    ///   - connectOptions: 连接选项
    ///   - sessionBox: WebSocket 会话盒
    ///   - onConnected: 连接成功回调
    ///   - onDisconnected: 断开连接回调
    ///   - onInvoke: 调用请求回调
    /// - Throws: 连接失败时抛出错误
    public func connect(
        url: URL,
        token: String?,
        password: String?,
        connectOptions: GatewayConnectOptions,
        sessionBox: WebSocketSessionBox?,
        onConnected: @escaping @Sendable () async -> Void,
        onDisconnected: @escaping @Sendable (String) async -> Void,
        onInvoke: @escaping @Sendable (BridgeInvokeRequest) async -> BridgeInvokeResponse
    ) async throws {
        // 检查是否需要重新连接
        let shouldReconnect = self.activeURL != url ||
            self.activeToken != token ||
            self.activePassword != password ||
            self.channel == nil

        // 保存连接参数和回调
        self.connectOptions = connectOptions
        self.onConnected = onConnected
        self.onDisconnected = onDisconnected
        self.onInvoke = onInvoke

        // 如果需要重新连接
        if shouldReconnect {
            // 关闭现有通道
            if let existing = self.channel {
                await existing.shutdown()
            }
            // 创建新的通道实例
            let channel = GatewayChannelActor(
                url: url,
                token: token,
                password: password,
                session: sessionBox,
                pushHandler: { [weak self] push in
                    await self?.handlePush(push)
                },
                connectOptions: connectOptions,
                disconnectHandler: { [weak self] reason in
                    await self?.onDisconnected?(reason)
                })
            // 保存新通道和连接信息
            self.channel = channel
            self.activeURL = url
            self.activeToken = token
            self.activePassword = password
        }

        // 确保通道存在
        guard let channel = self.channel else {
            throw NSError(domain: "Gateway", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "网关通道不可用",
            ])
        }

        // 尝试连接
        do {
            try await channel.connect()
            await onConnected()
        } catch {
            await onDisconnected(error.localizedDescription)
            throw error
        }
    }

    /// 断开连接
    public func disconnect() async {
        await self.channel?.shutdown()
        self.channel = nil
        self.activeURL = nil
        self.activeToken = nil
        self.activePassword = nil
    }

    /// 获取当前 Canvas 主机 URL
    /// - Returns: Canvas 主机 URL，如果不存在则返回 nil
    public func currentCanvasHostUrl() -> String? {
        self.canvasHostUrl
    }

    /// 获取当前远程地址
    /// - Returns: 格式化的远程地址字符串，如果未连接则返回 nil
    public func currentRemoteAddress() -> String? {
        guard let url = self.activeURL else { return nil }
        guard let host = url.host else { return url.absoluteString }
        let port = url.port ?? (url.scheme == "wss" ? 443 : 80)
        if host.contains(":") {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }

    /// 发送事件
    /// - Parameters:
    ///   - event: 事件名称
    ///   - payloadJSON: 事件负载的 JSON 字符串
    public func sendEvent(event: String, payloadJSON: String?) async {
        guard let channel = self.channel else { return }
        let params: [String: AnyCodable] = [
            "event": AnyCodable(event),
            "payloadJSON": AnyCodable(payloadJSON ?? NSNull()),
        ]
        do {
            try await channel.send(method: "node.event", params: params)
        } catch {
            self.logger.error("节点事件发送失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 发送请求
    /// - Parameters:
    ///   - method: 请求方法
    ///   - paramsJSON: 请求参数的 JSON 字符串
    ///   - timeoutSeconds: 超时时间（秒），默认 15 秒
    /// - Returns: 请求响应数据
    /// - Throws: 请求失败时抛出错误
    public func request(method: String, paramsJSON: String?, timeoutSeconds: Int = 15) async throws -> Data {
        guard let channel = self.channel else {
            throw NSError(domain: "Gateway", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "未连接",
            ])
        }

        let params = try self.decodeParamsJSON(paramsJSON)
        return try await channel.request(
            method: method,
            params: params,
            timeoutMs: Double(timeoutSeconds * 1000))
    }

    /// 订阅服务器事件
    /// - Parameter bufferingNewest: 缓冲区大小，默认 200
    /// - Returns: 事件帧的异步流
    public func subscribeServerEvents(bufferingNewest: Int = 200) -> AsyncStream<EventFrame> {
        let id = UUID()
        let session = self
        return AsyncStream(bufferingPolicy: .bufferingNewest(bufferingNewest)) { continuation in
            self.serverEventSubscribers[id] = continuation
            continuation.onTermination = { @Sendable _ in
                Task { await session.removeServerEventSubscriber(id) }
            }
        }
    }

    /// 处理推送消息
    /// - Parameter push: 网关推送消息
    private func handlePush(_ push: GatewayPush) async {
        switch push {
        case let .snapshot(ok):
            // 处理快照消息，更新 Canvas 主机 URL
            let raw = ok.canvashosturl?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.canvasHostUrl = (raw?.isEmpty == false) ? raw : nil
            await self.onConnected?()
        case let .event(evt):
            // 处理事件消息
            await self.handleEvent(evt)
        default:
            break
        }
    }

    /// 处理事件
    /// - Parameter evt: 事件帧
    private func handleEvent(_ evt: EventFrame) async {
        // 广播服务器事件
        self.broadcastServerEvent(evt)
        
        // 处理节点调用请求
        guard evt.event == "node.invoke.request" else { return }
        guard let payload = evt.payload else { return }
        do {
            let data = try self.encoder.encode(payload)
            let request = try self.decoder.decode(NodeInvokeRequestPayload.self, from: data)
            guard let onInvoke else { return }
            let req = BridgeInvokeRequest(id: request.id, command: request.command, paramsJSON: request.paramsJSON)
            
            // 带超时处理的调用
            let response = await Self.invokeWithTimeout(
                request: req,
                timeoutMs: request.timeoutMs,
                onInvoke: onInvoke
            )
            
            // 发送调用结果
            await self.sendInvokeResult(request: request, response: response)
        } catch {
            self.logger.error("节点调用解码失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 发送调用结果
    /// - Parameters:
    ///   - request: 原始调用请求
    ///   - response: 调用响应
    private func sendInvokeResult(request: NodeInvokeRequestPayload, response: BridgeInvokeResponse) async {
        guard let channel = self.channel else { return }
        var params: [String: AnyCodable] = [
            "id": AnyCodable(request.id),
            "nodeId": AnyCodable(request.nodeId),
            "ok": AnyCodable(response.ok),
        ]
        
        // 添加响应负载（如果有）
        if let payloadJSON = response.payloadJSON {
            params["payloadJSON"] = AnyCodable(payloadJSON)
        }
        
        // 添加错误信息（如果有）
        if let error = response.error {
            params["error"] = AnyCodable([
                "code": error.code.rawValue,
                "message": error.message,
            ])
        }
        
        do {
            try await channel.send(method: "node.invoke.result", params: params)
        } catch {
            self.logger.error("节点调用结果发送失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 解码参数 JSON 字符串
    /// - Parameter paramsJSON: 参数 JSON 字符串
    /// - Returns: 解码后的参数字典
    /// - Throws: 解码失败时抛出错误
    private func decodeParamsJSON(
        _ paramsJSON: String?) throws -> [String: AnyCodable]?
    {
        guard let paramsJSON, !paramsJSON.isEmpty else { return nil }
        guard let data = paramsJSON.data(using: .utf8) else {
            throw NSError(domain: "Gateway", code: 12, userInfo: [
                NSLocalizedDescriptionKey: "paramsJSON 不是 UTF-8 编码",
            ])
        }
        let raw = try JSONSerialization.jsonObject(with: data)
        guard let dict = raw as? [String: Any] else { 
            return nil
        }
        return dict.reduce(into: [:]) { acc, entry in
            acc[entry.key] = AnyCodable(entry.value)
        }
    }

    /// 广播服务器事件给所有订阅者
    /// - Parameter evt: 事件帧
    private func broadcastServerEvent(_ evt: EventFrame) {
        for (id, continuation) in self.serverEventSubscribers {
            if case .terminated = continuation.yield(evt) {
                self.serverEventSubscribers.removeValue(forKey: id)
            }
        }
    }

    /// 移除服务器事件订阅者
    /// - Parameter id: 订阅者 ID
    private func removeServerEventSubscriber(_ id: UUID) {
        self.serverEventSubscribers.removeValue(forKey: id)
    }
}

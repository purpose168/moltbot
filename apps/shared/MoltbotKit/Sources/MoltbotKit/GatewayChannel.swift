import MoltbotProtocol
import Foundation
import OSLog

/// WebSocket 任务协议，定义了 WebSocket 操作的基本方法
public protocol WebSocketTasking: AnyObject {
    /// 获取任务状态
    var state: URLSessionTask.State { get }
    /// 恢复任务
    func resume()
    /// 取消任务
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?)
    /// 发送消息
    func send(_ message: URLSessionWebSocketTask.Message) async throws
    /// 接收消息
    func receive() async throws -> URLSessionWebSocketTask.Message
    /// 接收消息（带回调）
    func receive(completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
}

/// 扩展 URLSessionWebSocketTask 以遵循 WebSocketTasking 协议
extension URLSessionWebSocketTask: WebSocketTasking {}

/// WebSocket 任务包装器，提供 Sendable 一致性
public struct WebSocketTaskBox: @unchecked Sendable {
    /// 内部 WebSocket 任务
    public let task: any WebSocketTasking
    
    /// 初始化方法
    public init(task: any WebSocketTasking) {
        self.task = task
    }

    /// 获取任务状态
    public var state: URLSessionTask.State { self.task.state }

    /// 恢复任务
    public func resume() { self.task.resume() }

    /// 取消任务
    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        self.task.cancel(with: closeCode, reason: reason)
    }

    /// 发送消息
    public func send(_ message: URLSessionWebSocketTask.Message) async throws {
        try await self.task.send(message)
    }

    /// 接收消息
    public func receive() async throws -> URLSessionWebSocketTask.Message {
        try await self.task.receive()
    }

    /// 接收消息（带回调）
    public func receive(
        completionHandler: @escaping @Sendable (Result<URLSessionWebSocketTask.Message, Error>) -> Void)
    {
        self.task.receive(completionHandler: completionHandler)
    }
}

/// WebSocket 会话协议，用于创建 WebSocket 任务
public protocol WebSocketSessioning: AnyObject {
    /// 创建 WebSocket 任务
    func makeWebSocketTask(url: URL) -> WebSocketTaskBox
}

/// 扩展 URLSession 以遵循 WebSocketSessioning 协议
extension URLSession: WebSocketSessioning {
    /// 创建 WebSocket 任务
    public func makeWebSocketTask(url: URL) -> WebSocketTaskBox {
        let task = self.webSocketTask(with: url)
        // 避免大型快照/历史记录负载导致的"消息过长"接收错误
        task.maximumMessageSize = 16 * 1024 * 1024 // 16 MB
        return WebSocketTaskBox(task: task)
    }
}

/// WebSocket 会话包装器，提供 Sendable 一致性
public struct WebSocketSessionBox: @unchecked Sendable {
    /// 内部 WebSocket 会话
    public let session: any WebSocketSessioning

    /// 初始化方法
    public init(session: any WebSocketSessioning) {
        self.session = session
    }
}

/// 网关连接选项
public struct GatewayConnectOptions: Sendable {
    /// 角色
    public var role: String
    /// 作用域
    public var scopes: [String]
    /// 能力
    public var caps: [String]
    /// 命令
    public var commands: [String]
    /// 权限
    public var permissions: [String: Bool]
    /// 客户端 ID
    public var clientId: String
    /// 客户端模式
    public var clientMode: String
    /// 客户端显示名称
    public var clientDisplayName: String?

    /// 初始化方法
    public init(
        role: String,
        scopes: [String],
        caps: [String],
        commands: [String],
        permissions: [String: Bool],
        clientId: String,
        clientMode: String,
        clientDisplayName: String?)
    {
        self.role = role
        self.scopes = scopes
        self.caps = caps
        self.commands = commands
        self.permissions = permissions
        self.clientId = clientId
        self.clientMode = clientMode
        self.clientDisplayName = clientDisplayName
    }
}

/// 网关认证源
public enum GatewayAuthSource: String, Sendable {
    /// 设备令牌
    case deviceToken = "device-token"
    /// 共享令牌
    case sharedToken = "shared-token"
    /// 密码
    case password = "password"
    /// 无认证
    case none = "none"
}

// 避免与应用程序自己的 AnyCodable 类型混淆
private typealias ProtoAnyCodable = MoltbotProtocol.AnyCodable

/// 连接挑战错误
private enum ConnectChallengeError: Error {
    /// 超时
    case timeout
}

/// 网关通道参与者，处理 WebSocket 连接和消息
public actor GatewayChannelActor {
    /// 日志记录器
    private let logger = Logger(subsystem: "bot.molt", category: "gateway")
    /// WebSocket 任务
    private var task: WebSocketTaskBox?
    /// 待处理的请求
    private var pending: [String: CheckedContinuation<GatewayFrame, Error>] = [:]
    /// 连接状态
    private var connected = false
    /// 连接中状态
    private var isConnecting = false
    /// 连接等待者
    private var connectWaiters: [CheckedContinuation<Void, Error>] = []
    /// 网关 URL
    private var url: URL
    /// 认证令牌
    private var token: String?
    /// 密码
    private var password: String?
    /// WebSocket 会话
    private let session: WebSocketSessioning
    /// 重连退避时间（毫秒）
    private var backoffMs: Double = 500
    /// 是否应该重连
    private var shouldReconnect = true
    /// 最后一个序列号
    private var lastSeq: Int?
    /// 最后一个心跳时间
    private var lastTick: Date?
    /// 心跳间隔（毫秒）
    private var tickIntervalMs: Double = 30000
    /// 最后一个认证源
    private var lastAuthSource: GatewayAuthSource = .none
    /// JSON 解码器
    private let decoder = JSONDecoder()
    /// JSON 编码器
    private let encoder = JSONEncoder()
    /// 连接超时时间（秒）
    private let connectTimeoutSeconds: Double = 6
    /// 连接挑战超时时间（秒）
    private let connectChallengeTimeoutSeconds: Double = 0.75
    /// 看门狗任务
    private var watchdogTask: Task<Void, Never>?
    /// 心跳任务
    private var tickTask: Task<Void, Never>?
    /// 默认请求超时时间（毫秒）
    private let defaultRequestTimeoutMs: Double = 15000
    /// 推送处理器
    private let pushHandler: (@Sendable (GatewayPush) async -> Void)?
    /// 连接选项
    private let connectOptions: GatewayConnectOptions?
    /// 断开连接处理器
    private let disconnectHandler: (@Sendable (String) async -> Void)?

    /// 初始化方法
    public init(
        url: URL,
        token: String?,
        password: String? = nil,
        session: WebSocketSessionBox? = nil,
        pushHandler: (@Sendable (GatewayPush) async -> Void)? = nil,
        connectOptions: GatewayConnectOptions? = nil,
        disconnectHandler: (@Sendable (String) async -> Void)? = nil)
    {
        self.url = url
        self.token = token
        self.password = password
        self.session = session?.session ?? URLSession(configuration: .default)
        self.pushHandler = pushHandler
        self.connectOptions = connectOptions
        self.disconnectHandler = disconnectHandler
        // 启动看门狗
        Task { [weak self] in
            await self?.startWatchdog()
        }
    }

    /// 获取认证源
    public func authSource() -> GatewayAuthSource { self.lastAuthSource }

    /// 关闭网关通道
    public func shutdown() async {
        // 停止重连
        self.shouldReconnect = false
        self.connected = false

        // 取消任务
        self.watchdogTask?.cancel()
        self.watchdogTask = nil

        self.tickTask?.cancel()
        self.tickTask = nil

        // 关闭 WebSocket 连接
        self.task?.cancel(with: .goingAway, reason: nil)
        self.task = nil

        // 失败所有待处理请求
        await self.failPending(NSError(
            domain: "Gateway",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "gateway channel shutdown"]))

        // 通知所有连接等待者
        let waiters = self.connectWaiters
        self.connectWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: NSError(
                domain: "Gateway",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "gateway channel shutdown"]))
        }
    }

    /// 启动看门狗
    private func startWatchdog() {
        // 取消现有看门狗任务
        self.watchdogTask?.cancel()
        // 创建新的看门狗任务
        self.watchdogTask = Task { [weak self] in
            guard let self else { return }
            await self.watchdogLoop()
        }
    }

    /// 看门狗循环
    private func watchdogLoop() async {
        // 定期尝试重连，以防指数退避停滞
        while self.shouldReconnect {
            // 每30秒检查一次
            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000) // 30s cadence
            guard self.shouldReconnect else { return }
            // 如果已连接，跳过
            if self.connected { continue }
            do {
                // 尝试连接
                try await self.connect()
            } catch {
                let wrapped = self.wrap(error, context: "gateway watchdog reconnect")
                self.logger.error("gateway watchdog reconnect failed \(wrapped.localizedDescription, privacy: .public)")
            }
        }
    }

    /// 连接到网关
    public func connect() async throws {
        // 如果已连接且任务正在运行，直接返回
        if self.connected, self.task?.state == .running { return }
        // 如果正在连接，等待连接完成
        if self.isConnecting {
            try await withCheckedThrowingContinuation { cont in
                self.connectWaiters.append(cont)
            }
            return
        }
        // 设置连接中状态
        self.isConnecting = true
        defer { self.isConnecting = false }

        // 取消现有任务
        self.task?.cancel(with: .goingAway, reason: nil)
        // 创建新的 WebSocket 任务
        self.task = self.session.makeWebSocketTask(url: self.url)
        // 恢复任务
        self.task?.resume()
        do {
            // 带超时的连接操作
            try await AsyncTimeout.withTimeout(
                seconds: self.connectTimeoutSeconds,
                onTimeout: {
                    NSError(
                        domain: "Gateway",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "connect timed out"])
                },
                operation: { try await self.sendConnect() })
        } catch {
            // 处理连接错误
            let wrapped = self.wrap(error, context: "connect to gateway @ \(self.url.absoluteString)")
            self.connected = false
            self.task?.cancel(with: .goingAway, reason: nil)
            await self.disconnectHandler?("connect failed: \(wrapped.localizedDescription)")
            // 通知所有连接等待者
            let waiters = self.connectWaiters
            self.connectWaiters.removeAll()
            for waiter in waiters {
                waiter.resume(throwing: wrapped)
            }
            self.logger.error("gateway ws connect failed \(wrapped.localizedDescription, privacy: .public)")
            throw wrapped
        }
        // 开始监听消息
        self.listen()
        // 更新连接状态
        self.connected = true
        // 重置退避时间
        self.backoffMs = 500
        // 重置序列号
        self.lastSeq = nil

        // 通知所有连接等待者
        let waiters = self.connectWaiters
        self.connectWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: ())
        }
    }

    /// 发送连接请求
    private func sendConnect() async throws {
        // 获取平台信息
        let platform = InstanceIdentity.platformString
        // 获取首选语言
        let primaryLocale = Locale.preferredLanguages.first ?? Locale.current.identifier
        // 使用默认或提供的连接选项
        let options = self.connectOptions ?? GatewayConnectOptions(
            role: "operator",
            scopes: ["operator.admin", "operator.approvals", "operator.pairing"],
            caps: [],
            commands: [],
            permissions: [:],
            clientId: "moltbot-macos",
            clientMode: "ui",
            clientDisplayName: InstanceIdentity.displayName)
        let clientDisplayName = options.clientDisplayName ?? InstanceIdentity.displayName
        let clientId = options.clientId
        let clientMode = options.clientMode
        let role = options.role
        let scopes = options.scopes

        // 生成请求 ID
        let reqId = UUID().uuidString
        // 构建客户端信息
        var client: [String: ProtoAnyCodable] = [
            "id": ProtoAnyCodable(clientId),
            "displayName": ProtoAnyCodable(clientDisplayName),
            "version": ProtoAnyCodable(
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"),
            "platform": ProtoAnyCodable(platform),
            "mode": ProtoAnyCodable(clientMode),
            "instanceId": ProtoAnyCodable(InstanceIdentity.instanceId),
        ]
        // 添加设备系列
        client["deviceFamily"] = ProtoAnyCodable(InstanceIdentity.deviceFamily)
        // 添加模型标识符（如果有）
        if let model = InstanceIdentity.modelIdentifier {
            client["modelIdentifier"] = ProtoAnyCodable(model)
        }
        // 构建参数
        var params: [String: ProtoAnyCodable] = [
            "minProtocol": ProtoAnyCodable(GATEWAY_PROTOCOL_VERSION),
            "maxProtocol": ProtoAnyCodable(GATEWAY_PROTOCOL_VERSION),
            "client": ProtoAnyCodable(client),
            "caps": ProtoAnyCodable(options.caps),
            "locale": ProtoAnyCodable(primaryLocale),
            "userAgent": ProtoAnyCodable(ProcessInfo.processInfo.operatingSystemVersionString),
            "role": ProtoAnyCodable(role),
            "scopes": ProtoAnyCodable(scopes),
        ]
        // 添加命令（如果有）
        if !options.commands.isEmpty {
            params["commands"] = ProtoAnyCodable(options.commands)
        }
        // 添加权限（如果有）
        if !options.permissions.isEmpty {
            params["permissions"] = ProtoAnyCodable(options.permissions)
        }
        // 加载或创建设备标识
        let identity = DeviceIdentityStore.loadOrCreate()
        // 加载设备令牌
        let storedToken = DeviceAuthStore.loadToken(deviceId: identity.deviceId, role: role)?.token
        // 使用存储的令牌或提供的令牌
        let authToken = storedToken ?? self.token
        // 确定认证源
        let authSource: GatewayAuthSource
        if storedToken != nil {
            authSource = .deviceToken
        } else if authToken != nil {
            authSource = .sharedToken
        } else if self.password != nil {
            authSource = .password
        } else {
            authSource = .none
        }
        self.lastAuthSource = authSource
        self.logger.info("gateway connect auth=\(authSource.rawValue, privacy: .public)")
        // 检查是否可以回退到共享令牌
        let canFallbackToShared = storedToken != nil && self.token != nil
        // 添加认证信息
        if let authToken {
            params["auth"] = ProtoAnyCodable(["token": ProtoAnyCodable(authToken)])
        } else if let password = self.password {
            params["auth"] = ProtoAnyCodable(["password": ProtoAnyCodable(password)])
        }
        // 计算签名时间
        let signedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        // 等待连接挑战
        let connectNonce = try await self.waitForConnectChallenge()
        // 构建作用域值
        let scopesValue = scopes.joined(separator: ",")
        // 构建签名 payload 部分
        var payloadParts = [
            connectNonce == nil ? "v1" : "v2",
            identity.deviceId,
            clientId,
            clientMode,
            role,
            scopesValue,
            String(signedAtMs),
            authToken ?? "",
        ]
        // 添加连接挑战（如果有）
        if let connectNonce {
            payloadParts.append(connectNonce)
        }
        // 构建完整 payload
        let payload = payloadParts.joined(separator: "|")
        // 签名 payload 并添加设备信息
        if let signature = DeviceIdentityStore.signPayload(payload, identity: identity),
           let publicKey = DeviceIdentityStore.publicKeyBase64Url(identity) {
            var device: [String: ProtoAnyCodable] = [
                "id": ProtoAnyCodable(identity.deviceId),
                "publicKey": ProtoAnyCodable(publicKey),
                "signature": ProtoAnyCodable(signature),
                "signedAt": ProtoAnyCodable(signedAtMs),
            ]
            // 添加挑战 nonce（如果有）
            if let connectNonce {
                device["nonce"] = ProtoAnyCodable(connectNonce)
            }
            params["device"] = ProtoAnyCodable(device)
        }

        // 构建连接请求帧
        let frame = RequestFrame(
            type: "req",
            id: reqId,
            method: "connect",
            params: ProtoAnyCodable(params))
        // 编码请求
        let data = try self.encoder.encode(frame)
        // 发送请求
        try await self.task?.send(.data(data))
        do {
            // 等待连接响应
            let response = try await self.waitForConnectResponse(reqId: reqId)
            // 处理连接响应
            try await self.handleConnectResponse(response, identity: identity, role: role)
        } catch {
            // 如果可以回退到共享令牌，清除设备令牌
            if canFallbackToShared {
                DeviceAuthStore.clearToken(deviceId: identity.deviceId, role: role)
            }
            throw error
        }
    }

    /// 处理连接响应
    private func handleConnectResponse(
        _ res: ResponseFrame,
        identity: DeviceIdentity,
        role: String
    ) async throws {
        // 检查响应是否成功
        if res.ok == false {
            let msg = (res.error?["message"]?.value as? String) ?? "gateway connect failed"
            throw NSError(domain: "Gateway", code: 1008, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        // 检查是否有 payload
        guard let payload = res.payload else {
            throw NSError(
                domain: "Gateway",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "connect failed (missing payload)"])
        }
        // 解码 payload
        let payloadData = try self.encoder.encode(payload)
        let ok = try decoder.decode(HelloOk.self, from: payloadData)
        // 更新心跳间隔
        if let tick = ok.policy["tickIntervalMs"]?.value as? Double {
            self.tickIntervalMs = tick
        } else if let tick = ok.policy["tickIntervalMs"]?.value as? Int {
            self.tickIntervalMs = Double(tick)
        }
        // 存储设备令牌（如果有）
        if let auth = ok.auth,
           let deviceToken = auth["deviceToken"]?.value as? String {
            let authRole = auth["role"]?.value as? String ?? role
            let scopes = (auth["scopes"]?.value as? [ProtoAnyCodable])?
                .compactMap { $0.value as? String } ?? []
            _ = DeviceAuthStore.storeToken(
                deviceId: identity.deviceId,
                role: authRole,
                token: deviceToken,
                scopes: scopes)
        }
        // 更新最后心跳时间
        self.lastTick = Date()
        // 取消现有心跳任务
        self.tickTask?.cancel()
        // 创建新的心跳任务
        self.tickTask = Task { [weak self] in
            guard let self else { return }
            await self.watchTicks()
        }
        // 推送快照
        await self.pushHandler?(.snapshot(ok))
    }

    /// 开始监听消息
    private func listen() {
        self.task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(err):
                // 处理接收失败
                Task { await self.handleReceiveFailure(err) }
            case let .success(msg):
                // 处理消息并继续监听
                Task {
                    await self.handle(msg)
                    await self.listen()
                }
            }
        }
    }

    /// 处理接收失败
    private func handleReceiveFailure(_ err: Error) async {
        // 包装错误
        let wrapped = self.wrap(err, context: "gateway receive")
        self.logger.error("gateway ws receive failed \(wrapped.localizedDescription, privacy: .public)")
        // 更新连接状态
        self.connected = false
        // 通知断开连接
        await self.disconnectHandler?("receive failed: \(wrapped.localizedDescription)")
        // 失败所有待处理请求
        await self.failPending(wrapped)
        // 安排重连
        await self.scheduleReconnect()
    }

    /// 处理消息
    private func handle(_ msg: URLSessionWebSocketTask.Message) async {
        // 提取数据
        let data: Data? = switch msg {
        case let .data(d): d
        case let .string(s): s.data(using: .utf8)
        @unknown default: nil
        }
        guard let data else { return }
        // 解码消息
        guard let frame = try? self.decoder.decode(GatewayFrame.self, from: data) else {
            self.logger.error("gateway decode failed")
            return
        }
        // 处理不同类型的帧
        switch frame {
        case let .res(res):
            // 处理响应
            let id = res.id
            if let waiter = pending.removeValue(forKey: id) {
                waiter.resume(returning: .res(res))
            }
        case let .event(evt):
            // 忽略连接挑战事件
            if evt.event == "connect.challenge" { return }
            // 处理序列号
            if let seq = evt.seq {
                if let last = lastSeq, seq > last + 1 {
                    await self.pushHandler?(.seqGap(expected: last + 1, received: seq))
                }
                self.lastSeq = seq
            }
            // 更新心跳时间
            if evt.event == "tick" { self.lastTick = Date() }
            // 推送事件
            await self.pushHandler?(.event(evt))
        default:
            break
        }
    }

    /// 等待连接挑战
    private func waitForConnectChallenge() async throws -> String? {
        guard let task = self.task else { return nil }
        do {
            return try await AsyncTimeout.withTimeout(
                seconds: self.connectChallengeTimeoutSeconds,
                onTimeout: { ConnectChallengeError.timeout },
                operation: { [weak self] in
                    guard let self else { return nil }
                    while true {
                        // 接收消息
                        let msg = try await task.receive()
                        // 解码消息数据
                        guard let data = self.decodeMessageData(msg) else { continue }
                        // 解码帧
                        guard let frame = try? self.decoder.decode(GatewayFrame.self, from: data) else { continue }
                        // 检查是否是连接挑战事件
                        if case let .event(evt) = frame, evt.event == "connect.challenge" {
                            // 提取 nonce
                            if let payload = evt.payload?.value as? [String: ProtoAnyCodable],
                               let nonce = payload["nonce"]?.value as? String {
                                return nonce
                            }
                        }
                    }
                })
        } catch {
            // 如果是超时错误，返回 nil
            if error is ConnectChallengeError { return nil }
            throw error
        }
    }

    /// 等待连接响应
    private func waitForConnectResponse(reqId: String) async throws -> ResponseFrame {
        guard let task = self.task else {
            throw NSError(
                domain: "Gateway",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "connect failed (no response)"])
        }
        while true {
            // 接收消息
            let msg = try await task.receive()
            // 解码消息数据
            guard let data = self.decodeMessageData(msg) else { continue }
            // 解码帧
            guard let frame = try? self.decoder.decode(GatewayFrame.self, from: data) else {
                throw NSError(
                    domain: "Gateway",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "connect failed (invalid response)"])
            }
            // 检查是否是目标响应
            if case let .res(res) = frame, res.id == reqId {
                return res
            }
        }
    }

    /// 解码消息数据
    private nonisolated func decodeMessageData(_ msg: URLSessionWebSocketTask.Message) -> Data? {
        let data: Data? = switch msg {
        case let .data(data): data
        case let .string(text): text.data(using: .utf8)
        @unknown default: nil
        }
        return data
    }

    /// 监视心跳
    private func watchTicks() async {
        // 心跳容忍时间
        let tolerance = self.tickIntervalMs * 2
        while self.connected {
            // 等待容忍时间
            try? await Task.sleep(nanoseconds: UInt64(tolerance * 1_000_000))
            guard self.connected else { return }
            // 检查最后心跳时间
            if let last = self.lastTick {
                let delta = Date().timeIntervalSince(last) * 1000
                // 如果超过容忍时间，认为心跳丢失
                if delta > tolerance {
                    self.logger.error("gateway tick missed; reconnecting")
                    self.connected = false
                    // 失败所有待处理请求
                    await self.failPending(
                        NSError(
                            domain: "Gateway",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: "gateway tick missed; reconnecting"]))
                    // 安排重连
                    await self.scheduleReconnect()
                    return
                }
            }
        }
    }

    /// 安排重连
    private func scheduleReconnect() async {
        // 检查是否应该重连
        guard self.shouldReconnect else { return }
        // 计算延迟时间
        let delay = self.backoffMs / 1000
        // 增加退避时间（最大30秒）
        self.backoffMs = min(self.backoffMs * 2, 30000)
        // 等待延迟
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        // 再次检查是否应该重连
        guard self.shouldReconnect else { return }
        do {
            // 尝试连接
            try await self.connect()
        } catch {
            let wrapped = self.wrap(error, context: "gateway reconnect")
            self.logger.error("gateway reconnect failed \(wrapped.localizedDescription, privacy: .public)")
            // 递归安排重连
            await self.scheduleReconnect()
        }
    }

    /// 发送请求
    public func request(
        method: String,
        params: [String: AnyCodable]?,
        timeoutMs: Double? = nil) async throws -> Data
    {
        // 确保连接
        try await self.connectOrThrow(context: "gateway connect")
        // 计算超时时间
        let effectiveTimeout = timeoutMs ?? self.defaultRequestTimeoutMs
        // 编码请求
        let payload = try self.encodeRequest(method: method, params: params, kind: "request")
        // 等待响应
        let response = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<GatewayFrame, Error>) in
            // 存储等待者
            self.pending[payload.id] = cont
            // 设置超时任务
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000))
                await self.timeoutRequest(id: payload.id, timeoutMs: effectiveTimeout)
            }
            // 发送请求
            Task {
                do {
                    try await self.task?.send(.data(payload.data))
                } catch {
                    // 处理发送错误
                    let wrapped = self.wrap(error, context: "gateway send \(method)")
                    let waiter = self.pending.removeValue(forKey: payload.id)
                    // 将发送失败视为断开连接
                    self.connected = false
                    self.task?.cancel(with: .goingAway, reason: nil)
                    // 安排重连
                    Task { [weak self] in
                        guard let self else { return }
                        await self.scheduleReconnect()
                    }
                    // 通知等待者
                    if let waiter { waiter.resume(throwing: wrapped) }
                }
            }
        }
        // 检查响应类型
        guard case let .res(res) = response else {
            throw NSError(domain: "Gateway", code: 2, userInfo: [NSLocalizedDescriptionKey: "unexpected frame"])
        }
        // 检查响应是否成功
        if res.ok == false {
            let code = res.error?["code"]?.value as? String
            let msg = res.error?["message"]?.value as? String
            let details: [String: AnyCodable] = (res.error ?? [:]).reduce(into: [:]) { acc, pair in
                acc[pair.key] = AnyCodable(pair.value.value)
            }
            throw GatewayResponseError(method: method, code: code, message: msg, details: details)
        }
        // 处理响应 payload
        if let payload = res.payload {
            // 使用 Swift 编码器编码回 JSON，以保留类型并避免 ObjC 桥接异常
            return try self.encoder.encode(payload)
        }
        // 空 payload
        return Data() // Should not happen, but tolerate empty payloads.
    }

    /// 发送消息（无响应）
    public func send(method: String, params: [String: AnyCodable]?) async throws {
        // 确保连接
        try await self.connectOrThrow(context: "gateway connect")
        // 编码请求
        let payload = try self.encodeRequest(method: method, params: params, kind: "send")
        // 检查任务是否存在
        guard let task = self.task else {
            throw NSError(
                domain: "Gateway",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "gateway socket unavailable"])
        }
        do {
            // 发送消息
            try await task.send(.data(payload.data))
        } catch {
            // 处理发送错误
            let wrapped = self.wrap(error, context: "gateway send \(method)")
            self.connected = false
            self.task?.cancel(with: .goingAway, reason: nil)
            // 安排重连
            Task { [weak self] in
                guard let self else { return }
                await self.scheduleReconnect()
            }
            throw wrapped
        }
    }

    /// 包装错误，添加上下文
    private func wrap(_ error: Error, context: String) -> Error {
        if let urlError = error as? URLError {
            let desc = urlError.localizedDescription.isEmpty ? "cancelled" : urlError.localizedDescription
            return NSError(
                domain: URLError.errorDomain,
                code: urlError.errorCode,
                userInfo: [NSLocalizedDescriptionKey: "\(context): \(desc)"])
        }
        let ns = error as NSError
        let desc = ns.localizedDescription.isEmpty ? "unknown" : ns.localizedDescription
        return NSError(domain: ns.domain, code: ns.code, userInfo: [NSLocalizedDescriptionKey: "\(context): \(desc)"])
    }

    /// 连接并抛出错误
    private func connectOrThrow(context: String) async throws {
        do {
            try await self.connect()
        } catch {
            throw self.wrap(error, context: context)
        }
    }

    /// 编码请求
    private func encodeRequest(
        method: String,
        params: [String: AnyCodable]?,
        kind: String) throws -> (id: String, data: Data)
    {
        // 生成请求 ID
        let id = UUID().uuidString
        // 使用生成的模型编码请求，以避免 JSONSerialization/ObjC 桥接陷阱
        let paramsObject: ProtoAnyCodable? = params.map { entries in
            let dict = entries.reduce(into: [String: ProtoAnyCodable]()) { dict, entry in
                dict[entry.key] = ProtoAnyCodable(entry.value.value)
            }
            return ProtoAnyCodable(dict)
        }
        // 构建请求帧
        let frame = RequestFrame(
            type: "req",
            id: id,
            method: method,
            params: paramsObject)
        do {
            // 编码请求
            let data = try self.encoder.encode(frame)
            return (id: id, data: data)
        } catch {
            self.logger.error(
                "gateway \(kind) encode failed \(method, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// 失败所有待处理请求
    private func failPending(_ error: Error) async {
        let waiters = self.pending
        self.pending.removeAll()
        for (_, waiter) in waiters {
            waiter.resume(throwing: error)
        }
    }

    /// 超时请求
    private func timeoutRequest(id: String, timeoutMs: Double) async {
        // 移除等待者
        guard let waiter = self.pending.removeValue(forKey: id) else { return }
        // 创建超时错误
        let err = NSError(
            domain: "Gateway",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "gateway request timed out after \(Int(timeoutMs))ms"])
        // 通知等待者
        waiter.resume(throwing: err)
    }
}

// 有意不提供 `GatewayChannel` 包装器：应用程序应使用单个共享的 `GatewayConnection`。

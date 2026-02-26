import MoltbotKit
import MoltbotProtocol
import Foundation
import Observation
import SwiftUI

/// 控制心跳事件
/// 
/// 表示控制通道的心跳事件
struct ControlHeartbeatEvent: Codable {
    /// 时间戳
    let ts: Double
    /// 状态
    let status: String
    /// 目标
    let to: String?
    /// 预览
    let preview: String?
    /// 持续时间（毫秒）
    let durationMs: Double?
    /// 是否有媒体
    let hasMedia: Bool?
    /// 原因
    let reason: String?
}

/// 控制代理事件
/// 
/// 表示控制通道的代理事件
struct ControlAgentEvent: Codable, Sendable, Identifiable {
    /// 标识符
    var id: String { "\(self.runId)-\(self.seq)" }
    /// 运行ID
    let runId: String
    /// 序列
    let seq: Int
    /// 流
    let stream: String
    /// 时间戳
    let ts: Double
    /// 数据
    let data: [String: MoltbotProtocol.AnyCodable]
    /// 摘要
    let summary: String?
}

/// 控制通道错误
/// 
/// 表示控制通道的错误
enum ControlChannelError: Error, LocalizedError {
    /// 断开连接
    case disconnected
    /// 错误响应
    case badResponse(String)

    /// 错误描述
    var errorDescription: String? {
        switch self {
        case .disconnected: "Control channel disconnected"
        case let .badResponse(msg): msg
        }
    }
}

/// 控制通道
/// 
/// 用于管理与网关的控制通道连接
@MainActor
@Observable
final class ControlChannel {
    /// 共享实例
    static let shared = ControlChannel()

    /// 控制通道模式
    enum Mode {
        /// 本地模式
        case local
        /// 远程模式
        case remote(target: String, identity: String)
    }

    /// 连接状态
    enum ConnectionState: Equatable {
        /// 断开连接
        case disconnected
        /// 正在连接
        case connecting
        /// 已连接
        case connected
        /// 降级状态
        case degraded(String)
    }

    /// 连接状态
    private(set) var state: ConnectionState = .disconnected {
        didSet {
            CanvasManager.shared.refreshDebugStatus()
            guard oldValue != self.state else { return }
            switch self.state {
            case .connected:
                self.logger.info("control channel state -> connected")
            case .connecting:
                self.logger.info("control channel state -> connecting")
            case .disconnected:
                self.logger.info("control channel state -> disconnected")
                self.scheduleRecovery(reason: "disconnected")
            case let .degraded(message):
                let detail = message.isEmpty ? "degraded" : "degraded: \(message)"
                self.logger.info("control channel state -> \(detail, privacy: .public)")
                self.scheduleRecovery(reason: message)
            }
        }
    }

    /// 上次ping的时间（毫秒）
    private(set) var lastPingMs: Double?
    /// 认证源标签
    private(set) var authSourceLabel: String?

    /// 日志记录器
    private let logger = Logger(subsystem: "bot.molt", category: "control")

    /// 事件任务
    private var eventTask: Task<Void, Never>?
    /// 恢复任务
    private var recoveryTask: Task<Void, Never>?
    /// 上次恢复时间
    private var lastRecoveryAt: Date?

    /// 初始化控制通道
    private init() {
        self.startEventStream()
    }

    /// 配置控制通道
    func configure() async {
        self.logger.info("control channel configure mode=local")
        await self.refreshEndpoint(reason: "configure")
    }

    /// 配置控制通道
    /// - Parameter mode: 控制通道模式，默认为本地模式
    func configure(mode: Mode = .local) async throws {
        switch mode {
        case .local:
            await self.configure()
        case let .remote(target, identity):
            do {
                _ = (target, identity)
                let idSet = !identity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                self.logger.info(
                    "control channel configure mode=remote " +
                        "target=\(target, privacy: .public) identitySet=\(idSet, privacy: .public)")
                self.state = .connecting
                _ = try await GatewayEndpointStore.shared.ensureRemoteControlTunnel()
                await self.refreshEndpoint(reason: "configure")
            } catch {
                self.state = .degraded(error.localizedDescription)
                throw error
            }
        }
    }

    /// 刷新端点
    /// - Parameter reason: 刷新原因
    func refreshEndpoint(reason: String) async {
        self.logger.info("control channel refresh endpoint reason=\(reason, privacy: .public)")
        self.state = .connecting
        do {
            try await self.establishGatewayConnection()
            self.state = .connected
            PresenceReporter.shared.sendImmediate(reason: "connect")
        } catch {
            let message = self.friendlyGatewayMessage(error)
            self.state = .degraded(message)
        }
    }

    /// 断开连接
    func disconnect() async {
        await GatewayConnection.shared.shutdown()
        self.state = .disconnected
        self.lastPingMs = nil
        self.authSourceLabel = nil
    }

    /// 检查健康状态
    /// - Parameter timeout: 超时时间，可选
    /// - Returns: 健康状态数据
    func health(timeout: TimeInterval? = nil) async throws -> Data {
        do {
            let start = Date()
            var params: [String: AnyHashable]?
            if let timeout {
                params = ["timeout": AnyHashable(Int(timeout * 1000))]
            }
            let timeoutMs = (timeout ?? 15) * 1000
            let payload = try await self.request(method: "health", params: params, timeoutMs: timeoutMs)
            let ms = Date().timeIntervalSince(start) * 1000
            self.lastPingMs = ms
            self.state = .connected
            return payload
        } catch {
            let message = self.friendlyGatewayMessage(error)
            self.state = .degraded(message)
            throw ControlChannelError.badResponse(message)
        }
    }

    /// 获取上次心跳
    /// - Returns: 控制心跳事件，可选
    func lastHeartbeat() async throws -> ControlHeartbeatEvent? {
        let data = try await self.request(method: "last-heartbeat")
        return try JSONDecoder().decode(ControlHeartbeatEvent?.self, from: data)
    }

    /// 发送请求
    /// - Parameters:
    ///   - method: 请求方法
    ///   - params: 请求参数，可选
    ///   - timeoutMs: 超时时间（毫秒），可选
    /// - Returns: 请求响应数据
    func request(
        method: String,
        params: [String: AnyHashable]? = nil,
        timeoutMs: Double? = nil) async throws -> Data
    {
        do {
            let rawParams = params?.reduce(into: [String: MoltbotKit.AnyCodable]()) {
                $0[$1.key] = MoltbotKit.AnyCodable($1.value.base)
            }
            let data = try await GatewayConnection.shared.request(
                method: method,
                params: rawParams,
                timeoutMs: timeoutMs)
            self.state = .connected
            return data
        } catch {
            let message = self.friendlyGatewayMessage(error)
            self.state = .degraded(message)
            throw ControlChannelError.badResponse(message)
        }
    }

    /// 获取友好的网关错误消息
    /// - Parameter error: 错误
    /// - Returns: 友好的错误消息
    private func friendlyGatewayMessage(_ error: Error) -> String {
        // 将URLSession/WS错误映射为用户友好的可操作文本
        if let ctrlErr = error as? ControlChannelError, let desc = ctrlErr.errorDescription {
            return desc
        }

        // 如果网关明确拒绝hello（例如，认证/令牌不匹配），显示它
        if let urlErr = error as? URLError,
           urlErr.code == .dataNotAllowed // 用于WS关闭1008认证失败
        {
            let reason = urlErr.failureURLString ?? urlErr.localizedDescription
            let tokenKey = CommandResolver.connectionModeIsRemote()
                ? "gateway.remote.token"
                : "gateway.auth.token"
            return
                "Gateway rejected token; set \(tokenKey) (or CLAWDBOT_GATEWAY_TOKEN) " +
                "or clear it on the gateway. " +
                "Reason: \(reason)"
        }

        // 常见错误：我们连接到配置的本地端口，但它被其他进程占用
        // （例如，本地开发网关或卡住的SSH转发）
        // 网关握手返回我们无法解析的内容，目前显示为"hello failed (unexpected response)"
        // 给用户一个指针来释放端口，而不是一个模糊的消息
        let nsError = error as NSError
        if nsError.domain == "Gateway",
           nsError.localizedDescription.contains("hello failed (unexpected response)")
        {
            let port = GatewayEnvironment.gatewayPort()
            return """
            Gateway handshake got non-gateway data on localhost:\(port).
            Another process is using that port or the SSH forward failed.
            Stop the local gateway/port-forward on \(port) and retry Remote mode.
            """
        }

        if let urlError = error as? URLError {
            let port = GatewayEnvironment.gatewayPort()
            switch urlError.code {
            case .cancelled:
                return "Gateway connection was closed; start the gateway (localhost:\(port)) and retry."
            case .cannotFindHost, .cannotConnectToHost:
                let isRemote = CommandResolver.connectionModeIsRemote()
                if isRemote {
                    return """
                    Cannot reach gateway at localhost:\(port).
                    Remote mode uses an SSH tunnel—check the SSH target and that the tunnel is running.
                    """
                }
                return "Cannot reach gateway at localhost:\(port); ensure the gateway is running."
            case .networkConnectionLost:
                return "Gateway connection dropped; gateway likely restarted—retry."
            case .timedOut:
                return "Gateway request timed out; check gateway on localhost:\(port)."
            case .notConnectedToInternet:
                return "No network connectivity; cannot reach gateway."
            default:
                break
            }
        }

        if nsError.domain == "Gateway", nsError.code == 5 {
            let port = GatewayEnvironment.gatewayPort()
            return "Gateway request timed out; check the gateway process on localhost:\(port)."
        }

        let detail = nsError.localizedDescription.isEmpty ? "unknown gateway error" : nsError.localizedDescription
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("gateway error:") { return trimmed }
        return "Gateway error: \(trimmed)"
    }

    /// 安排恢复
    /// - Parameter reason: 恢复原因
    private func scheduleRecovery(reason: String) {
        let now = Date()
        if let last = self.lastRecoveryAt, now.timeIntervalSince(last) < 10 { return }
        guard self.recoveryTask == nil else { return }
        self.lastRecoveryAt = now

        self.recoveryTask = Task { [weak self] in
            guard let self else { return }
            let mode = await MainActor.run { AppStateStore.shared.connectionMode }
            guard mode != .unconfigured else {
                self.recoveryTask = nil
                return
            }

            let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let reasonText = trimmedReason.isEmpty ? "unknown" : trimmedReason
            self.logger.info(
                "control channel recovery starting " +
                    "mode=\(String(describing: mode), privacy: .public) " +
                    "reason=\(reasonText, privacy: .public)")
            if mode == .local {
                GatewayProcessManager.shared.setActive(true)
            }
            if mode == .remote {
                do {
                    let port = try await GatewayEndpointStore.shared.ensureRemoteControlTunnel()
                    self.logger.info("control channel recovery ensured SSH tunnel port=\(port, privacy: .public)")
                } catch {
                    self.logger.error(
                        "control channel recovery tunnel failed \(error.localizedDescription, privacy: .public)")
                }
            }

            await self.refreshEndpoint(reason: "recovery:\(reasonText)")
            if case .connected = self.state {
                self.logger.info("control channel recovery finished")
            } else if case let .degraded(message) = self.state {
                self.logger.error("control channel recovery failed \(message, privacy: .public)")
            }

            self.recoveryTask = nil
        }
    }

    /// 建立网关连接
    /// - Parameter timeoutMs: 超时时间（毫秒），默认为5000
    private func establishGatewayConnection(timeoutMs: Int = 5000) async throws {
        try await GatewayConnection.shared.refresh()
        let ok = try await GatewayConnection.shared.healthOK(timeoutMs: timeoutMs)
        if ok == false {
            throw NSError(
                domain: "Gateway",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "gateway health not ok"])
        }
        await self.refreshAuthSourceLabel()
    }

    /// 刷新认证源标签
    private func refreshAuthSourceLabel() async {
        let isRemote = CommandResolver.connectionModeIsRemote()
        let authSource = await GatewayConnection.shared.authSource()
        self.authSourceLabel = Self.formatAuthSource(authSource, isRemote: isRemote)
    }

    /// 格式化认证源
    /// - Parameters:
    ///   - source: 网关认证源
    ///   - isRemote: 是否为远程模式
    /// - Returns: 格式化的认证源标签
    private static func formatAuthSource(_ source: GatewayAuthSource?, isRemote: Bool) -> String? {
        guard let source else { return nil }
        switch source {
        case .deviceToken:
            return "Auth: device token (paired device)"
        case .sharedToken:
            return "Auth: shared token (\(isRemote ? "gateway.remote.token" : "gateway.auth.token"))"
        case .password:
            return "Auth: password (\(isRemote ? "gateway.remote.password" : "gateway.auth.password"))"
        case .none:
            return "Auth: none"
        }
    }

    /// 发送系统事件
    /// - Parameters:
    ///   - text: 事件文本
    ///   - params: 事件参数，默认为空
    func sendSystemEvent(_ text: String, params: [String: AnyHashable] = [:]) async throws {
        var merged = params
        merged["text"] = AnyHashable(text)
        _ = try await self.request(method: "system-event", params: merged)
    }

    /// 启动事件流
    private func startEventStream() {
        self.eventTask?.cancel()
        self.eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await GatewayConnection.shared.subscribe()
            for await push in stream {
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    self?.handle(push: push)
                }
            }
        }
    }

    /// 处理推送事件
    /// - Parameter push: 网关推送事件
    private func handle(push: GatewayPush) {
        switch push {
        case let .event(evt) where evt.event == "agent":
            if let payload = evt.payload,
               let agent = try? GatewayPayloadDecoding.decode(payload, as: ControlAgentEvent.self)
            {
                AgentEventStore.shared.append(agent)
                self.routeWorkActivity(from: agent)
            }
        case let .event(evt) where evt.event == "heartbeat":
            if let payload = evt.payload,
               let heartbeat = try? GatewayPayloadDecoding.decode(payload, as: ControlHeartbeatEvent.self),
               let data = try? JSONEncoder().encode(heartbeat)
            {
                NotificationCenter.default.post(name: .controlHeartbeat, object: data)
            }
        case let .event(evt) where evt.event == "shutdown":
            self.state = .degraded("gateway shutdown")
        case .snapshot:
            self.state = .connected
        default:
            break
        }
    }

    /// 路由工作活动
    /// - Parameter event: 控制代理事件
    private func routeWorkActivity(from event: ControlAgentEvent) {
        // 我们目前将VoiceWake视为UI目的的"主"会话
        // 将来，网关可以包含sessionKey来区分运行
        let sessionKey = (event.data["sessionKey"]?.value as? String) ?? "main"

        switch event.stream.lowercased() {
        case "job":
            if let state = event.data["state"]?.value as? String {
                WorkActivityStore.shared.handleJob(sessionKey: sessionKey, state: state)
            }
        case "tool":
            let phase = event.data["phase"]?.value as? String ?? ""
            let name = event.data["name"]?.value as? String
            let meta = event.data["meta"]?.value as? String
            let args = Self.bridgeToProtocolArgs(event.data["args"])
            WorkActivityStore.shared.handleTool(
                sessionKey: sessionKey,
                phase: phase,
                name: name,
                meta: meta,
                args: args)
        default:
            break
        }
    }

    /// 桥接到协议参数
    /// - Parameter value: MoltbotProtocol.AnyCodable值
    /// - Returns: 协议参数字典
    private static func bridgeToProtocolArgs(
        _ value: MoltbotProtocol.AnyCodable?) -> [String: MoltbotProtocol.AnyCodable]?
    {
        guard let value else { return nil }
        if let dict = value.value as? [String: MoltbotProtocol.AnyCodable] {
            return dict
        }
        if let dict = value.value as? [String: MoltbotKit.AnyCodable],
           let data = try? JSONEncoder().encode(dict),
           let decoded = try? JSONDecoder().decode([String: MoltbotProtocol.AnyCodable].self, from: data)
        {
            return decoded
        }
        if let data = try? JSONEncoder().encode(value),
           let decoded = try? JSONDecoder().decode([String: MoltbotProtocol.AnyCodable].self, from: data)
        {
            return decoded
        }
        return nil
    }
}

/// 通知名称扩展
extension Notification.Name {
    /// 控制心跳通知
    static let controlHeartbeat = Notification.Name("moltbot.control.heartbeat")
    /// 控制代理事件通知
    static let controlAgentEvent = Notification.Name("moltbot.control.agent")
}

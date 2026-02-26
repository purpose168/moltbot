import MoltbotKit
import Network
import Observation
import SwiftUI
import UIKit

/// NodeAppModel 是应用的核心模型类，管理应用的状态和功能
@MainActor
@Observable
final class NodeAppModel {
    /// 相机HUD的类型
    enum CameraHUDKind {
        case photo        // 拍照
        case recording    // 录制
        case success      // 成功
        case error        // 错误
    }

    /// 应用是否在后台运行
    var isBackgrounded: Bool = false
    /// 屏幕控制器
    let screen = ScreenController()
    /// 相机控制器
    let camera = CameraController()
    /// 屏幕录制服务
    private let screenRecorder = ScreenRecordService()
    /// 网关状态文本
    var gatewayStatusText: String = "离线"
    /// 网关服务器名称
    var gatewayServerName: String?
    /// 网关远程地址
    var gatewayRemoteAddress: String?
    /// 已连接的网关ID
    var connectedGatewayID: String?
    /// 边框颜色的十六进制值
    var seamColorHex: String?
    /// 主会话密钥
    var mainSessionKey: String = "main"

    /// 网关会话
    private let gateway = GatewayNodeSession()
    /// 网关任务
    private var gatewayTask: Task<Void, Never>?
    /// 语音唤醒同步任务
    private var voiceWakeSyncTask: Task<Void, Never>?
    /// 相机HUD dismiss任务
    @ObservationIgnored private var cameraHUDDismissTask: Task<Void, Never>?
    /// 语音唤醒管理器
    let voiceWake = VoiceWakeManager()
    /// 对话模式管理器
    let talkMode = TalkModeManager()
    /// 位置服务
    private let locationService = LocationService()
    /// 上次自动A2UI URL
    private var lastAutoA2uiURL: String?

    /// 网关是否已连接
    private var gatewayConnected = false
    /// 网关会话的只读访问
    var gatewaySession: GatewayNodeSession { self.gateway }

    /// 相机HUD文本
    var cameraHUDText: String?
    /// 相机HUD类型
    var cameraHUDKind: CameraHUDKind?
    /// 相机闪光灯随机数
    var cameraFlashNonce: Int = 0
    /// 屏幕录制是否活跃
    var screenRecordActive: Bool = false

    /// 初始化方法
    init() {
        // 配置语音唤醒
        self.voiceWake.configure { [weak self] cmd in
            guard let self else { return }
            let sessionKey = await MainActor.run { self.mainSessionKey }
            do {
                try await self.sendVoiceTranscript(text: cmd, sessionKey: sessionKey)
            } catch {
                // 仅尽力而为
            }
        }

        // 从用户默认设置中获取语音唤醒和对话模式的启用状态
        let enabled = UserDefaults.standard.bool(forKey: "voiceWake.enabled")
        self.voiceWake.setEnabled(enabled)
        self.talkMode.attachGateway(self.gateway)
        let talkEnabled = UserDefaults.standard.bool(forKey: "talk.enabled")
        self.talkMode.setEnabled(talkEnabled)

        // 连接来自canvas点击的深度链接
        self.screen.onDeepLink = { [weak self] url in
            guard let self else { return }
            Task { @MainActor in
                await self.handleDeepLink(url: url)
            }
        }

        // 连接A2UI操作点击（按钮等）
        self.screen.onA2UIAction = { [weak self] body in
            guard let self else { return }
            Task { @MainActor in
                await self.handleCanvasA2UIAction(body: body)
            }
        }
    }

    /// 处理Canvas A2UI操作
    private func handleCanvasA2UIAction(body: [String: Any]) async {
        let userActionAny = body["userAction"] ?? body
        let userAction: [String: Any] = {
            if let dict = userActionAny as? [String: Any] { return dict }
            if let dict = userActionAny as? [AnyHashable: Any] {
                return dict.reduce(into: [String: Any]()) { acc, pair in
                    guard let key = pair.key as? String else { return }
                    acc[key] = pair.value
                }
            }
            return [:]
        }()
        guard !userAction.isEmpty else { return }

        guard let name = MoltbotCanvasA2UIAction.extractActionName(userAction) else { return }
        let actionId: String = {
            let id = (userAction["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty ? UUID().uuidString : id
        }()

        let surfaceId: String = {
            let raw = (userAction["surfaceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "main" : raw
        }()
        let sourceComponentId: String = {
            let raw = (userAction[
                "sourceComponentId",
            ] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return raw.isEmpty ? "-" : raw
        }()

        let host = UserDefaults.standard.string(forKey: "node.displayName") ?? UIDevice.current.name
        let instanceId = (UserDefaults.standard.string(forKey: "node.instanceId") ?? "ios-node").lowercased()
        let contextJSON = MoltbotCanvasA2UIAction.compactJSON(userAction["context"])
        let sessionKey = self.mainSessionKey

        let messageContext = MoltbotCanvasA2UIAction.AgentMessageContext(
            actionName: name,
            session: .init(key: sessionKey, surfaceId: surfaceId),
            component: .init(id: sourceComponentId, host: host, instanceId: instanceId),
            contextJSON: contextJSON)
        let message = MoltbotCanvasA2UIAction.formatAgentMessage(messageContext)

        let ok: Bool
        var errorText: String?
        if await !self.isGatewayConnected() {
            ok = false
            errorText = "网关未连接"
        } else {
            do {
                try await self.sendAgentRequest(link: AgentDeepLink(
                    message: message,
                    sessionKey: sessionKey,
                    thinking: "low",
                    deliver: false,
                    to: nil,
                    channel: nil,
                    timeoutSeconds: nil,
                    key: actionId))
                ok = true
            } catch {
                ok = false
                errorText = error.localizedDescription
            }
        }

        let js = MoltbotCanvasA2UIAction.jsDispatchA2UIActionStatus(actionId: actionId, ok: ok, error: errorText)
        do {
            _ = try await self.screen.eval(javaScript: js)
        } catch {
            // 忽略错误
        }
    }

    /// 解析A2UI主机URL
    private func resolveA2UIHostURL() async -> String? {
        guard let raw = await self.gateway.currentCanvasHostUrl() else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = URL(string: trimmed) else { return nil }
        return base.appendingPathComponent("__moltbot__/a2ui/").absoluteString + "?platform=ios"
    }

    /// 在连接时如果需要显示A2UI
    private func showA2UIOnConnectIfNeeded() async {
        guard let a2uiUrl = await self.resolveA2UIHostURL() else { return }
        let current = self.screen.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty || current == self.lastAutoA2uiURL {
            self.screen.navigate(to: a2uiUrl)
            self.lastAutoA2uiURL = a2uiUrl
        }
    }

    /// 在断开连接时显示本地画布
    private func showLocalCanvasOnDisconnect() {
        self.lastAutoA2uiURL = nil
        self.screen.showDefaultCanvas()
    }

    /// 设置场景阶段
    func setScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            self.isBackgrounded = true
        case .active, .inactive:
            self.isBackgrounded = false
        @unknown default:
            self.isBackgrounded = false
        }
    }

    /// 设置语音唤醒是否启用
    func setVoiceWakeEnabled(_ enabled: Bool) {
        self.voiceWake.setEnabled(enabled)
    }

    /// 设置对话模式是否启用
    func setTalkEnabled(_ enabled: Bool) {
        self.talkMode.setEnabled(enabled)
    }

    /// 请求位置权限
    func requestLocationPermissions(mode: MoltbotLocationMode) async -> Bool {
        guard mode != .off else { return true }
        let status = await self.locationService.ensureAuthorization(mode: mode)
        switch status {
        case .authorizedAlways:
            return true
        case .authorizedWhenInUse:
            return mode != .always
        default:
            return false
        }
    }

    /// 连接到网关
    func connectToGateway(
        url: URL,
        gatewayStableID: String,
        tls: GatewayTLSParams?,
        token: String?,
        password: String?,
        connectOptions: GatewayConnectOptions)
    {
        self.gatewayTask?.cancel()
        self.gatewayServerName = nil
        self.gatewayRemoteAddress = nil
        let id = gatewayStableID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.connectedGatewayID = id.isEmpty ? url.absoluteString : id
        self.gatewayConnected = false
        self.voiceWakeSyncTask?.cancel()
        self.voiceWakeSyncTask = nil
        let sessionBox = tls.map { WebSocketSessionBox(session: GatewayTLSPinningSession(params: $0)) }

        self.gatewayTask = Task {
            var attempt = 0
            while !Task.isCancelled {
                await MainActor.run {
                    if attempt == 0 {
                        self.gatewayStatusText = "连接中..."
                    } else {
                        self.gatewayStatusText = "重新连接中..."
                    }
                    self.gatewayServerName = nil
                    self.gatewayRemoteAddress = nil
                }

                do {
                    try await self.gateway.connect(
                        url: url,
                        token: token,
                        password: password,
                        connectOptions: connectOptions,
                        sessionBox: sessionBox,
                        onConnected: { [weak self] in
                            guard let self else { return }
                            await MainActor.run {
                                self.gatewayStatusText = "已连接"
                                self.gatewayServerName = url.host ?? "网关"
                                self.gatewayConnected = true
                            }
                            if let addr = await self.gateway.currentRemoteAddress() {
                                await MainActor.run {
                                    self.gatewayRemoteAddress = addr
                                }
                            }
                            await self.refreshBrandingFromGateway()
                            await self.startVoiceWakeSync()
                            await self.showA2UIOnConnectIfNeeded()
                        },
                        onDisconnected: { [weak self] reason in
                            guard let self else { return }
                            await MainActor.run {
                                self.gatewayStatusText = "已断开"
                                self.gatewayRemoteAddress = nil
                                self.gatewayConnected = false
                                self.showLocalCanvasOnDisconnect()
                                self.gatewayStatusText = "已断开: \(reason)"
                            }
                        },
                        onInvoke: { [weak self] req in
                            guard let self else {
                                return BridgeInvokeResponse(
                                    id: req.id,
                                    ok: false,
                                    error: MoltbotNodeError(
                                        code: .unavailable,
                                        message: "UNAVAILABLE: 节点未就绪"))
                            }
                            return await self.handleInvoke(req)
                        })

                    if Task.isCancelled { break }
                    attempt = 0
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    if Task.isCancelled { break }
                    attempt += 1
                    await MainActor.run {
                        self.gatewayStatusText = "网关错误: \(error.localizedDescription)"
                        self.gatewayServerName = nil
                        self.gatewayRemoteAddress = nil
                        self.gatewayConnected = false
                        self.showLocalCanvasOnDisconnect()
                    }
                    let sleepSeconds = min(8.0, 0.5 * pow(1.7, Double(attempt)))
                    try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                }
            }

            await MainActor.run {
                self.gatewayStatusText = "离线"
                self.gatewayServerName = nil
                self.gatewayRemoteAddress = nil
                self.connectedGatewayID = nil
                self.gatewayConnected = false
                self.seamColorHex = nil
                if !SessionKey.isCanonicalMainSessionKey(self.mainSessionKey) {
                    self.mainSessionKey = "main"
                    self.talkMode.updateMainSessionKey(self.mainSessionKey)
                }
                self.showLocalCanvasOnDisconnect()
            }
        }
    }

    /// 断开网关连接
    func disconnectGateway() {
        self.gatewayTask?.cancel()
        self.gatewayTask = nil
        self.voiceWakeSyncTask?.cancel()
        self.voiceWakeSyncTask = nil
        Task { await self.gateway.disconnect() }
        self.gatewayStatusText = "离线"
        self.gatewayServerName = nil
        self.gatewayRemoteAddress = nil
        self.connectedGatewayID = nil
        self.gatewayConnected = false
        self.seamColorHex = nil
        if !SessionKey.isCanonicalMainSessionKey(self.mainSessionKey) {
            self.mainSessionKey = "main"
            self.talkMode.updateMainSessionKey(self.mainSessionKey)
        }
        self.showLocalCanvasOnDisconnect()
    }

    /// 应用主会话密钥
    private func applyMainSessionKey(_ key: String?) {
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = self.mainSessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if SessionKey.isCanonicalMainSessionKey(current) { return }
        if trimmed == current { return }
        self.mainSessionKey = trimmed
        self.talkMode.updateMainSessionKey(trimmed)
    }

    /// 边框颜色
    var seamColor: Color {
        Self.color(fromHex: self.seamColorHex) ?? Self.defaultSeamColor
    }

    /// 默认边框颜色
    private static let defaultSeamColor = Color(red: 79 / 255.0, green: 122 / 255.0, blue: 154 / 255.0)

    /// 从十六进制字符串创建颜色
    private static func color(fromHex raw: String?) -> Color? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard hex.count == 6, let value = Int(hex, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// 从网关刷新品牌设置
    private func refreshBrandingFromGateway() async {
        do {
            let res = try await self.gateway.request(method: "config.get", paramsJSON: "{}", timeoutSeconds: 8)
            guard let json = try JSONSerialization.jsonObject(with: res) as? [String: Any] else { return }
            guard let config = json["config"] as? [String: Any] else { return }
            let ui = config["ui"] as? [String: Any]
            let raw = (ui?["seamColor"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let session = config["session"] as? [String: Any]
            let mainKey = SessionKey.normalizeMainKey(session?["mainKey"] as? String)
            await MainActor.run {
                self.seamColorHex = raw.isEmpty ? nil : raw
                if !SessionKey.isCanonicalMainSessionKey(self.mainSessionKey) {
                    self.mainSessionKey = mainKey
                    self.talkMode.updateMainSessionKey(mainKey)
                }
            }
        } catch {
            // 忽略错误
        }
    }

    /// 设置全局唤醒词
    func setGlobalWakeWords(_ words: [String]) async {
        let sanitized = VoiceWakePreferences.sanitizeTriggerWords(words)

        struct Payload: Codable {
            var triggers: [String]
        }
        let payload = Payload(triggers: sanitized)
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8)
        else { return }

        do {
            _ = try await self.gateway.request(method: "voicewake.set", paramsJSON: json, timeoutSeconds: 12)
        } catch {
            // 仅尽力而为
        }
    }

    /// 开始语音唤醒同步
    private func startVoiceWakeSync() async {
        self.voiceWakeSyncTask?.cancel()
        self.voiceWakeSyncTask = Task { [weak self] in
            guard let self else { return }

            await self.refreshWakeWordsFromGateway()

            let stream = await self.gateway.subscribeServerEvents(bufferingNewest: 200)
            for await evt in stream {
                if Task.isCancelled { return }
                guard evt.event == "voicewake.changed" else { continue }
                guard let payload = evt.payload else { continue }
                struct Payload: Decodable { var triggers: [String] }
                guard let decoded = try? GatewayPayloadDecoding.decode(payload, as: Payload.self) else { continue }
                let triggers = VoiceWakePreferences.sanitizeTriggerWords(decoded.triggers)
                VoiceWakePreferences.saveTriggerWords(triggers)
            }
        }
    }

    /// 从网关刷新唤醒词
    private func refreshWakeWordsFromGateway() async {
        do {
            let data = try await self.gateway.request(method: "voicewake.get", paramsJSON: "{}", timeoutSeconds: 8)
            guard let triggers = VoiceWakePreferences.decodeGatewayTriggers(from: data) else { return }
            VoiceWakePreferences.saveTriggerWords(triggers)
        } catch {
            // 仅尽力而为
        }
    }

    /// 发送语音转录
    func sendVoiceTranscript(text: String, sessionKey: String?) async throws {
        if await !self.isGatewayConnected() {
            throw NSError(domain: "Gateway", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "网关未连接",
            ])
        }
        struct Payload: Codable {
            var text: String
            var sessionKey: String?
        }
        let payload = Payload(text: text, sessionKey: sessionKey)
        let data = try JSONEncoder().encode(payload)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "NodeAppModel", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法将语音转录 payload 编码为 UTF-8",
            ])
        }
        await self.gateway.sendEvent(event: "voice.transcript", payloadJSON: json)
    }

    /// 处理深度链接
    func handleDeepLink(url: URL) async {
        guard let route = DeepLinkParser.parse(url) else { return }

        switch route {
        case let .agent(link):
            await self.handleAgentDeepLink(link, originalURL: url)
        }
    }

    /// 处理代理深度链接
    private func handleAgentDeepLink(_ link: AgentDeepLink, originalURL: URL) async {
        let message = link.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        if message.count > 20000 {
            self.screen.errorText = "深度链接过大（消息超过 20,000 个字符）。"
            return
        }

        guard await self.isGatewayConnected() else {
            self.screen.errorText = "网关未连接（无法转发深度链接）。"
            return
        }

        do {
            try await self.sendAgentRequest(link: link)
            self.screen.errorText = nil
        } catch {
            self.screen.errorText = "代理请求失败: \(error.localizedDescription)"
        }
    }

    /// 发送代理请求
    private func sendAgentRequest(link: AgentDeepLink) async throws {
        if link.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(domain: "DeepLink", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无效的代理消息",
            ])
        }

        // iOS 网关转发到网关；此处无本地身份验证提示。
        // （基于密钥的无人值守身份验证在 macOS 上处理 moltbot:// 链接。）
        let data = try JSONEncoder().encode(link)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "NodeAppModel", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "无法将代理请求 payload 编码为 UTF-8",
            ])
        }
        await self.gateway.sendEvent(event: "agent.request", payloadJSON: json)
    }

    /// 检查网关是否已连接
    private func isGatewayConnected() async -> Bool {
        self.gatewayConnected
    }

    /// 处理调用请求
    private func handleInvoke(_ req: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        let command = req.command

        if self.isBackgrounded, self.isBackgroundRestricted(command) {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(
                    code: .backgroundUnavailable,
                    message: "NODE_BACKGROUND_UNAVAILABLE: canvas/camera/screen 命令需要前台运行"))
        }

        if command.hasPrefix("camera."), !self.isCameraEnabled() {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(
                    code: .unavailable,
                    message: "CAMERA_DISABLED: 在 iOS 设置 → 相机 → 允许相机中启用相机"))
        }

        do {
            switch command {
            case MoltbotLocationCommand.get.rawValue:
                return try await self.handleLocationInvoke(req)
            case MoltbotCanvasCommand.present.rawValue,
                 MoltbotCanvasCommand.hide.rawValue,
                 MoltbotCanvasCommand.navigate.rawValue,
                 MoltbotCanvasCommand.evalJS.rawValue,
                 MoltbotCanvasCommand.snapshot.rawValue:
                return try await self.handleCanvasInvoke(req)
            case MoltbotCanvasA2UICommand.reset.rawValue,
                 MoltbotCanvasA2UICommand.push.rawValue,
                 MoltbotCanvasA2UICommand.pushJSONL.rawValue:
                return try await self.handleCanvasA2UIInvoke(req)
            case MoltbotCameraCommand.list.rawValue,
                 MoltbotCameraCommand.snap.rawValue,
                 MoltbotCameraCommand.clip.rawValue:
                return try await self.handleCameraInvoke(req)
            case MoltbotScreenCommand.record.rawValue:
                return try await self.handleScreenRecordInvoke(req)
            default:
                return BridgeInvokeResponse(
                    id: req.id,
                    ok: false,
                    error: MoltbotNodeError(code: .invalidRequest, message: "INVALID_REQUEST: 未知命令"))
            }
        } catch {
            if command.hasPrefix("camera.") {
                let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.showCameraHUD(text: text, kind: .error, autoHideSeconds: 2.2)
            }
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(code: .unavailable, message: error.localizedDescription))
        }
    }

    /// 检查命令是否在后台受限
    private func isBackgroundRestricted(_ command: String) -> Bool {
        command.hasPrefix("canvas.") || command.hasPrefix("camera.") || command.hasPrefix("screen.")
    }

    /// 处理位置调用请求
    private func handleLocationInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let mode = self.locationMode()
        guard mode != .off else {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(
                    code: .unavailable,
                    message: "LOCATION_DISABLED: 在设置中启用位置"))
        }
        if self.isBackgrounded, mode != .always {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(
                    code: .backgroundUnavailable,
                    message: "LOCATION_BACKGROUND_UNAVAILABLE: 后台位置需要始终允许"))
        }
        let params = (try? Self.decodeParams(MoltbotLocationGetParams.self, from: req.paramsJSON)) ??
            MoltbotLocationGetParams()
        let desired = params.desiredAccuracy ??
            (self.isLocationPreciseEnabled() ? .precise : .balanced)
        let status = self.locationService.authorizationStatus()
        if status != .authorizedAlways, status != .authorizedWhenInUse {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(
                    code: .unavailable,
                    message: "LOCATION_PERMISSION_REQUIRED: 授予位置权限"))
        }
        if self.isBackgrounded, status != .authorizedAlways {
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(
                    code: .unavailable,
                    message: "LOCATION_PERMISSION_REQUIRED: 为后台访问启用始终允许"))
        }
        let location = try await self.locationService.currentLocation(
            params: params,
            desiredAccuracy: desired,
            maxAgeMs: params.maxAgeMs,
            timeoutMs: params.timeoutMs)
        let isPrecise = self.locationService.accuracyAuthorization() == .fullAccuracy
        let payload = MoltbotLocationPayload(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            accuracyMeters: location.horizontalAccuracy,
            altitudeMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speedMps: location.speed >= 0 ? location.speed : nil,
            headingDeg: location.course >= 0 ? location.course : nil,
            timestamp: ISO8601DateFormatter().string(from: location.timestamp),
            isPrecise: isPrecise,
            source: nil)
        let json = try Self.encodePayload(payload)
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: json)
    }

    /// 处理画布调用请求
    private func handleCanvasInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        switch req.command {
        case MoltbotCanvasCommand.present.rawValue:
            let params = (try? Self.decodeParams(MoltbotCanvasPresentParams.self, from: req.paramsJSON)) ??
                MoltbotCanvasPresentParams()
            let url = params.url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if url.isEmpty {
                self.screen.showDefaultCanvas()
            } else {
                self.screen.navigate(to: url)
            }
            return BridgeInvokeResponse(id: req.id, ok: true)
        case MoltbotCanvasCommand.hide.rawValue:
            return BridgeInvokeResponse(id: req.id, ok: true)
        case MoltbotCanvasCommand.navigate.rawValue:
            let params = try Self.decodeParams(MoltbotCanvasNavigateParams.self, from: req.paramsJSON)
            self.screen.navigate(to: params.url)
            return BridgeInvokeResponse(id: req.id, ok: true)
        case MoltbotCanvasCommand.evalJS.rawValue:
            let params = try Self.decodeParams(MoltbotCanvasEvalParams.self, from: req.paramsJSON)
            let result = try await self.screen.eval(javaScript: params.javaScript)
            let payload = try Self.encodePayload(["result": result])
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        case MoltbotCanvasCommand.snapshot.rawValue:
            let params = try? Self.decodeParams(MoltbotCanvasSnapshotParams.self, from: req.paramsJSON)
            let format = params?.format ?? .jpeg
            let maxWidth: CGFloat? = {
                if let raw = params?.maxWidth, raw > 0 { return CGFloat(raw) }
                // 保持默认快照大小舒适地低于网关客户端的最大有效负载。
                // 对于全分辨率，客户端应明确请求更大的 maxWidth。
                return switch format {
                case .png: 900
                case .jpeg: 1600
                }
            }()
            let base64 = try await self.screen.snapshotBase64(
                maxWidth: maxWidth,
                format: format,
                quality: params?.quality)
            let payload = try Self.encodePayload([
                "format": format == .jpeg ? "jpeg" : "png",
                "base64": base64,
            ])
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        default:
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(code: .invalidRequest, message: "INVALID_REQUEST: 未知命令"))
        }
    }

    /// 处理画布A2UI调用请求
    private func handleCanvasA2UIInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let command = req.command
        switch command {
        case MoltbotCanvasA2UICommand.reset.rawValue:
            guard let a2uiUrl = await self.resolveA2UIHostURL() else {
                return BridgeInvokeResponse(
                    id: req.id,
                    ok: false,
                    error: MoltbotNodeError(
                        code: .unavailable,
                        message: "A2UI_HOST_NOT_CONFIGURED: 网关未广告画布主机"))
            }
            self.screen.navigate(to: a2uiUrl)
            if await !self.screen.waitForA2UIReady(timeoutMs: 5000) {
                return BridgeInvokeResponse(
                    id: req.id,
                    ok: false,
                    error: MoltbotNodeError(
                        code: .unavailable,
                        message: "A2UI_HOST_UNAVAILABLE: A2UI 主机无法访问"))
            }

            let json = try await self.screen.eval(javaScript: """
            (() => {
              if (!globalThis.clawdbotA2UI) return JSON.stringify({ ok: false, error: "missing moltbotA2UI" });
              return JSON.stringify(globalThis.clawdbotA2UI.reset());
            })()
            """)
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: json)
        case MoltbotCanvasA2UICommand.push.rawValue, MoltbotCanvasA2UICommand.pushJSONL.rawValue:
            let messages: [AnyCodable]
            if command == MoltbotCanvasA2UICommand.pushJSONL.rawValue {
                let params = try Self.decodeParams(MoltbotCanvasA2UIPushJSONLParams.self, from: req.paramsJSON)
                messages = try MoltbotCanvasA2UIJSONL.decodeMessagesFromJSONL(params.jsonl)
            } else {
                do {
                    let params = try Self.decodeParams(MoltbotCanvasA2UIPushParams.self, from: req.paramsJSON)
                    messages = params.messages
                } catch {
                    // 宽容处理：一些客户端仍然向 `canvas.a2ui.push` 发送 JSONL 负载。
                    let params = try Self.decodeParams(MoltbotCanvasA2UIPushJSONLParams.self, from: req.paramsJSON)
                    messages = try MoltbotCanvasA2UIJSONL.decodeMessagesFromJSONL(params.jsonl)
                }
            }

            guard let a2uiUrl = await self.resolveA2UIHostURL() else {
                return BridgeInvokeResponse(
                    id: req.id,
                    ok: false,
                    error: MoltbotNodeError(
                        code: .unavailable,
                        message: "A2UI_HOST_NOT_CONFIGURED: 网关未广告画布主机"))
            }
            self.screen.navigate(to: a2uiUrl)
            if await !self.screen.waitForA2UIReady(timeoutMs: 5000) {
                return BridgeInvokeResponse(
                    id: req.id,
                    ok: false,
                    error: MoltbotNodeError(
                        code: .unavailable,
                        message: "A2UI_HOST_UNAVAILABLE: A2UI 主机无法访问"))
            }

            let messagesJSON = try MoltbotCanvasA2UIJSONL.encodeMessagesJSONArray(messages)
            let js = """
            (() => {
              try {
                if (!globalThis.clawdbotA2UI) return JSON.stringify({ ok: false, error: "missing moltbotA2UI" });
                const messages = \(messagesJSON);
                return JSON.stringify(globalThis.clawdbotA2UI.applyMessages(messages));
              } catch (e) {
                return JSON.stringify({ ok: false, error: String(e?.message ?? e) });
              }
            })()
            """
            let resultJSON = try await self.screen.eval(javaScript: js)
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: resultJSON)
        default:
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(code: .invalidRequest, message: "INVALID_REQUEST: 未知命令"))
        }
    }

    /// 处理相机调用请求
    private func handleCameraInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        switch req.command {
        case MoltbotCameraCommand.list.rawValue:
            let devices = await self.camera.listDevices()
            struct Payload: Codable {
                var devices: [CameraController.CameraDeviceInfo]
            }
            let payload = try Self.encodePayload(Payload(devices: devices))
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        case MoltbotCameraCommand.snap.rawValue:
            self.showCameraHUD(text: "拍照中...", kind: .photo)
            self.triggerCameraFlash()
            let params = (try? Self.decodeParams(MoltbotCameraSnapParams.self, from: req.paramsJSON)) ??
                MoltbotCameraSnapParams()
            let res = try await self.camera.snap(params: params)

            struct Payload: Codable {
                var format: String
                var base64: String
                var width: Int
                var height: Int
            }
            let payload = try Self.encodePayload(Payload(
                format: res.format,
                base64: res.base64,
                width: res.width,
                height: res.height))
            self.showCameraHUD(text: "照片已捕获", kind: .success, autoHideSeconds: 1.6)
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        case MoltbotCameraCommand.clip.rawValue:
            let params = (try? Self.decodeParams(MoltbotCameraClipParams.self, from: req.paramsJSON)) ??
                MoltbotCameraClipParams()

            let suspended = (params.includeAudio ?? true) ? self.voiceWake.suspendForExternalAudioCapture() : false
            defer { self.voiceWake.resumeAfterExternalAudioCapture(wasSuspended: suspended) }

            self.showCameraHUD(text: "录制中...", kind: .recording)
            let res = try await self.camera.clip(params: params)

            struct Payload: Codable {
                var format: String
                var base64: String
                var durationMs: Int
                var hasAudio: Bool
            }
            let payload = try Self.encodePayload(Payload(
                format: res.format,
                base64: res.base64,
                durationMs: res.durationMs,
                hasAudio: res.hasAudio))
            self.showCameraHUD(text: "视频已捕获", kind: .success, autoHideSeconds: 1.8)
            return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
        default:
            return BridgeInvokeResponse(
                id: req.id,
                ok: false,
                error: MoltbotNodeError(code: .invalidRequest, message: "INVALID_REQUEST: 未知命令"))
        }
    }

    /// 处理屏幕录制调用请求
    private func handleScreenRecordInvoke(_ req: BridgeInvokeRequest) async throws -> BridgeInvokeResponse {
        let params = (try? Self.decodeParams(MoltbotScreenRecordParams.self, from: req.paramsJSON)) ??
            MoltbotScreenRecordParams()
        if let format = params.format, format.lowercased() != "mp4" {
            throw NSError(domain: "Screen", code: 30, userInfo: [
                NSLocalizedDescriptionKey: "INVALID_REQUEST: 屏幕格式必须是 mp4",
            ])
        }
        // 状态栏镜像屏幕录制状态，使其在没有覆盖堆叠的情况下保持可见。
        self.screenRecordActive = true
        defer { self.screenRecordActive = false }
        let path = try await self.screenRecorder.record(
            screenIndex: params.screenIndex,
            durationMs: params.durationMs,
            fps: params.fps,
            includeAudio: params.includeAudio,
            outPath: nil)
        defer { try? FileManager().removeItem(atPath: path) }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        struct Payload: Codable {
            var format: String
            var base64: String
            var durationMs: Int?
            var fps: Double?
            var screenIndex: Int?
            var hasAudio: Bool
        }
        let payload = try Self.encodePayload(Payload(
            format: "mp4",
            base64: data.base64EncodedString(),
            durationMs: params.durationMs,
            fps: params.fps,
            screenIndex: params.screenIndex,
            hasAudio: params.includeAudio ?? true))
        return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: payload)
    }

}

/// NodeAppModel 的私有扩展
private extension NodeAppModel {
    /// 获取位置模式
    func locationMode() -> MoltbotLocationMode {
        let raw = UserDefaults.standard.string(forKey: "location.enabledMode") ?? "off"
        return MoltbotLocationMode(rawValue: raw) ?? .off
    }

    /// 检查位置精度是否启用
    func isLocationPreciseEnabled() -> Bool {
        if UserDefaults.standard.object(forKey: "location.preciseEnabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "location.preciseEnabled")
    }

    /// 解码参数
    static func decodeParams<T: Decodable>(_ type: T.Type, from json: String?) throws -> T {
        guard let json, let data = json.data(using: .utf8) else {
            throw NSError(domain: "Gateway", code: 20, userInfo: [
                NSLocalizedDescriptionKey: "INVALID_REQUEST: 需要 paramsJSON",
            ])
        }
        return try JSONDecoder().decode(type, from: data)
    }

    /// 编码负载
    static func encodePayload(_ obj: some Encodable) throws -> String {
        let data = try JSONEncoder().encode(obj)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw NSError(domain: "NodeAppModel", code: 21, userInfo: [
                NSLocalizedDescriptionKey: "无法将负载编码为 UTF-8",
            ])
        }
        return json
    }

    /// 检查相机是否启用
    func isCameraEnabled() -> Bool {
        // 默认启用：如果键不存在，则视为启用。
        if UserDefaults.standard.object(forKey: "camera.enabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "camera.enabled")
    }

    /// 触发相机闪光灯
    func triggerCameraFlash() {
        self.cameraFlashNonce &+= 1
    }

    /// 显示相机HUD
    func showCameraHUD(text: String, kind: CameraHUDKind, autoHideSeconds: Double? = nil) {
        self.cameraHUDDismissTask?.cancel()

        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            self.cameraHUDText = text
            self.cameraHUDKind = kind
        }

        guard let autoHideSeconds else { return }
        self.cameraHUDDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(autoHideSeconds * 1_000_000_000))
            withAnimation(.easeOut(duration: 0.25)) {
                self.cameraHUDText = nil
                self.cameraHUDKind = nil
            }
        }
    }
}

#if DEBUG
/// NodeAppModel 的调试扩展
extension NodeAppModel {
    /// 测试处理调用请求
    func _test_handleInvoke(_ req: BridgeInvokeRequest) async -> BridgeInvokeResponse {
        await self.handleInvoke(req)
    }

    /// 测试解码参数
    static func _test_decodeParams<T: Decodable>(_ type: T.Type, from json: String?) throws -> T {
        try self.decodeParams(type, from: json)
    }

    /// 测试编码负载
    static func _test_encodePayload(_ obj: some Encodable) throws -> String {
        try self.encodePayload(obj)
    }

    /// 测试检查相机是否启用
    func _test_isCameraEnabled() -> Bool {
        self.isCameraEnabled()
    }

    /// 测试触发相机闪光灯
    func _test_triggerCameraFlash() {
        self.triggerCameraFlash()
    }

    /// 测试显示相机HUD
    func _test_showCameraHUD(text: String, kind: CameraHUDKind, autoHideSeconds: Double? = nil) {
        self.showCameraHUD(text: text, kind: kind, autoHideSeconds: autoHideSeconds)
    }

    /// 测试处理Canvas A2UI操作
    func _test_handleCanvasA2UIAction(body: [String: Any]) async {
        await self.handleCanvasA2UIAction(body: body)
    }

    /// 测试解析A2UI主机URL
    func _test_resolveA2UIHostURL() async -> String? {
        await self.resolveA2UIHostURL()
    }

    /// 测试在断开连接时显示本地画布
    func _test_showLocalCanvasOnDisconnect() {
        self.showLocalCanvasOnDisconnect()
    }
}
#endif

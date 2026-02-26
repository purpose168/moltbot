import AppKit
import Foundation
import Observation
import ServiceManagement
import SwiftUI

/// 应用状态管理类，负责管理应用的所有配置和状态
@MainActor
@Observable
final class AppState {
    // 预览模式标志
    private let isPreview: Bool
    // 初始化标志
    private var isInitializing = true
    // 配置文件监视器
    private var configWatcher: ConfigFileWatcher?
    // 语音唤醒全局同步抑制标志
    private var suppressVoiceWakeGlobalSync = false
    // 语音唤醒全局同步任务
    private var voiceWakeGlobalSyncTask: Task<Void, Never>?

    /// 在非预览模式下执行操作
    private func ifNotPreview(_ action: () -> Void) {
        guard !self.isPreview else { return }
        action()
    }

    /// 连接模式枚举
    enum ConnectionMode: String {
        case unconfigured // 未配置
        case local         // 本地连接
        case remote        // 远程连接
    }

    /// 远程传输方式枚举
    enum RemoteTransport: String {
        case ssh    // SSH传输
        case direct // 直接传输
    }

    /// 应用暂停状态
    var isPaused: Bool {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.isPaused, forKey: pauseDefaultsKey) } }
    }

    /// 开机自启动状态
    var launchAtLogin: Bool {
        didSet {
            guard !self.isInitializing else { return }
            self.ifNotPreview { Task { AppStateStore.updateLaunchAtLogin(enabled: self.launchAtLogin) } }
        }
    }

    /// 首次引导已查看状态
    var onboardingSeen: Bool {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.onboardingSeen, forKey: "moltbot.onboardingSeen") }
        }
    }

    /// 调试面板启用状态
    var debugPaneEnabled: Bool {
        didSet {
            self.ifNotPreview { UserDefaults.standard.set(self.debugPaneEnabled, forKey: "moltbot.debugPaneEnabled") }
            CanvasManager.shared.refreshDebugStatus()
        }
    }

    /// 语音唤醒启用状态
    var swabbleEnabled: Bool {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.swabbleEnabled, forKey: swabbleEnabledKey)
                Task { await VoiceWakeRuntime.shared.refresh(state: self) }
            }
        }
    }

    /// 语音唤醒触发词
    var swabbleTriggerWords: [String] {
        didSet {
            // 保留原始编辑状态；实际使用触发词时会进行清理
            self.ifNotPreview {
                UserDefaults.standard.set(self.swabbleTriggerWords, forKey: swabbleTriggersKey)
                if self.swabbleEnabled {
                    Task { await VoiceWakeRuntime.shared.refresh(state: self) }
                }
                self.scheduleVoiceWakeGlobalSyncIfNeeded()
            }
        }
    }

    /// 语音唤醒触发提示音
    var voiceWakeTriggerChime: VoiceWakeChime {
        didSet { self.ifNotPreview { self.storeChime(self.voiceWakeTriggerChime, key: voiceWakeTriggerChimeKey) } }
    }

    /// 语音唤醒发送提示音
    var voiceWakeSendChime: VoiceWakeChime {
        didSet { self.ifNotPreview { self.storeChime(self.voiceWakeSendChime, key: voiceWakeSendChimeKey) } }
    }

    /// 图标动画启用状态
    var iconAnimationsEnabled: Bool {
        didSet { self.ifNotPreview { UserDefaults.standard.set(
            self.iconAnimationsEnabled,
            forKey: iconAnimationsEnabledKey) } }
    }

    /// 显示 Dock 图标状态
    var showDockIcon: Bool {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.showDockIcon, forKey: showDockIconKey)
                AppActivationPolicy.apply(showDockIcon: self.showDockIcon)
            }
        }
    }

    /// 语音唤醒麦克风 ID
    var voiceWakeMicID: String {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.voiceWakeMicID, forKey: voiceWakeMicKey)
                if self.swabbleEnabled {
                    Task { await VoiceWakeRuntime.shared.refresh(state: self) }
                }
            }
        }
    }

    /// 语音唤醒麦克风名称
    var voiceWakeMicName: String {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.voiceWakeMicName, forKey: voiceWakeMicNameKey) } }
    }

    /// 语音唤醒语言区域 ID
    var voiceWakeLocaleID: String {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.voiceWakeLocaleID, forKey: voiceWakeLocaleKey)
                if self.swabbleEnabled {
                    Task { await VoiceWakeRuntime.shared.refresh(state: self) }
                }
            }
        }
    }

    /// 语音唤醒附加语言区域 ID 数组
    var voiceWakeAdditionalLocaleIDs: [String] {
        didSet { self.ifNotPreview { UserDefaults.standard.set(
            self.voiceWakeAdditionalLocaleIDs,
            forKey: voiceWakeAdditionalLocalesKey) } }
    }

    /// 语音按键通话启用状态
    var voicePushToTalkEnabled: Bool {
        didSet { self.ifNotPreview { UserDefaults.standard.set(
            self.voicePushToTalkEnabled,
            forKey: voicePushToTalkEnabledKey) } }
    }

    /// 通话模式启用状态
    var talkEnabled: Bool {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.talkEnabled, forKey: talkEnabledKey)
                Task { await TalkModeController.shared.setEnabled(self.talkEnabled) }
            }
        }
    }

    /// Gateway 提供的 UI 强调色（十六进制）。可选；客户端提供默认值。
    var seamColorHex: String?

    /// 图标覆盖选择
    var iconOverride: IconOverrideSelection {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.iconOverride.rawValue, forKey: iconOverrideKey) } }
    }

    /// 应用工作状态
    var isWorking: Bool = false
    /// 语音耳朵增强活动状态
    var earBoostActive: Bool = false
    /// 眨眼动画计数器
    var blinkTick: Int = 0
    /// 发送庆祝动画计数器
    var sendCelebrationTick: Int = 0
    /// 心跳启用状态
    var heartbeatsEnabled: Bool {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.heartbeatsEnabled, forKey: heartbeatsEnabledKey)
                Task { _ = await GatewayConnection.shared.setHeartbeatsEnabled(self.heartbeatsEnabled) }
            }
        }
    }

    /// 连接模式
    var connectionMode: ConnectionMode {
        didSet {
            self.ifNotPreview { UserDefaults.standard.set(self.connectionMode.rawValue, forKey: connectionModeKey) }
            self.syncGatewayConfigIfNeeded()
        }
    }

    /// 远程传输方式
    var remoteTransport: RemoteTransport {
        didSet { self.syncGatewayConfigIfNeeded() }
    }

    /// 画布启用状态
    var canvasEnabled: Bool {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.canvasEnabled, forKey: canvasEnabledKey) } }
    }

    /// 执行批准模式
    var execApprovalMode: ExecApprovalQuickMode {
        didSet {
            self.ifNotPreview {
                ExecApprovalsStore.updateDefaults { defaults in
                    defaults.security = self.execApprovalMode.security
                    defaults.ask = self.execApprovalMode.ask
                }
            }
        }
    }

    /// 跟踪画布面板当前是否可见（不持久化）。
    var canvasPanelVisible: Bool = false

    /// Peekaboo 桥接启用状态
    var peekabooBridgeEnabled: Bool {
        didSet {
            self.ifNotPreview {
                UserDefaults.standard.set(self.peekabooBridgeEnabled, forKey: peekabooBridgeEnabledKey)
                Task { await PeekabooBridgeHostCoordinator.shared.setEnabled(self.peekabooBridgeEnabled) }
            }
        }
    }

    /// 远程目标
    var remoteTarget: String {
        didSet {
            self.ifNotPreview { UserDefaults.standard.set(self.remoteTarget, forKey: remoteTargetKey) }
            self.syncGatewayConfigIfNeeded()
        }
    }

    /// 远程 URL
    var remoteUrl: String {
        didSet { self.syncGatewayConfigIfNeeded() }
    }

    /// 远程身份
    var remoteIdentity: String {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.remoteIdentity, forKey: remoteIdentityKey) } }
    }

    /// 远程项目根目录
    var remoteProjectRoot: String {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.remoteProjectRoot, forKey: remoteProjectRootKey) } }
    }

    /// 远程 CLI 路径
    var remoteCliPath: String {
        didSet { self.ifNotPreview { UserDefaults.standard.set(self.remoteCliPath, forKey: remoteCliPathKey) } }
    }

    /// 语音耳朵增强任务
    private var earBoostTask: Task<Void, Never>?

    /// 初始化应用状态
    init(preview: Bool = false) {
        self.isPreview = preview || ProcessInfo.processInfo.isRunningTests
        let onboardingSeen = UserDefaults.standard.bool(forKey: "moltbot.onboardingSeen")
        self.isPaused = UserDefaults.standard.bool(forKey: pauseDefaultsKey)
        self.launchAtLogin = false
        self.onboardingSeen = onboardingSeen
        self.debugPaneEnabled = UserDefaults.standard.bool(forKey: "moltbot.debugPaneEnabled")
        let savedVoiceWake = UserDefaults.standard.bool(forKey: swabbleEnabledKey)
        self.swabbleEnabled = voiceWakeSupported ? savedVoiceWake : false
        self.swabbleTriggerWords = UserDefaults.standard
            .stringArray(forKey: swabbleTriggersKey) ?? defaultVoiceWakeTriggers
        self.voiceWakeTriggerChime = Self.loadChime(
            key: voiceWakeTriggerChimeKey,
            fallback: .system(name: "Glass"))
        self.voiceWakeSendChime = Self.loadChime(
            key: voiceWakeSendChimeKey,
            fallback: .system(name: "Glass"))
        if let storedIconAnimations = UserDefaults.standard.object(forKey: iconAnimationsEnabledKey) as? Bool {
            self.iconAnimationsEnabled = storedIconAnimations
        } else {
            self.iconAnimationsEnabled = true
            UserDefaults.standard.set(true, forKey: iconAnimationsEnabledKey)
        }
        self.showDockIcon = UserDefaults.standard.bool(forKey: showDockIconKey)
        self.voiceWakeMicID = UserDefaults.standard.string(forKey: voiceWakeMicKey) ?? ""
        self.voiceWakeMicName = UserDefaults.standard.string(forKey: voiceWakeMicNameKey) ?? ""
        self.voiceWakeLocaleID = UserDefaults.standard.string(forKey: voiceWakeLocaleKey) ?? Locale.current.identifier
        self.voiceWakeAdditionalLocaleIDs = UserDefaults.standard
            .stringArray(forKey: voiceWakeAdditionalLocalesKey) ?? []
        self.voicePushToTalkEnabled = UserDefaults.standard
            .object(forKey: voicePushToTalkEnabledKey) as? Bool ?? false
        self.talkEnabled = UserDefaults.standard.bool(forKey: talkEnabledKey)
        self.seamColorHex = nil
        if let storedHeartbeats = UserDefaults.standard.object(forKey: heartbeatsEnabledKey) as? Bool {
            self.heartbeatsEnabled = storedHeartbeats
        } else {
            self.heartbeatsEnabled = true
            UserDefaults.standard.set(true, forKey: heartbeatsEnabledKey)
        }
        if let storedOverride = UserDefaults.standard.string(forKey: iconOverrideKey),
           let selection = IconOverrideSelection(rawValue: storedOverride)
        {
            self.iconOverride = selection
        } else {
            self.iconOverride = .system
            UserDefaults.standard.set(IconOverrideSelection.system.rawValue, forKey: iconOverrideKey)
        }

        let configRoot = MoltbotConfigFile.loadDict()
        let configRemoteUrl = GatewayRemoteConfig.resolveUrlString(root: configRoot)
        let configRemoteTransport = GatewayRemoteConfig.resolveTransport(root: configRoot)
        let resolvedConnectionMode = ConnectionModeResolver.resolve(root: configRoot).mode
        self.remoteTransport = configRemoteTransport
        self.connectionMode = resolvedConnectionMode

        let storedRemoteTarget = UserDefaults.standard.string(forKey: remoteTargetKey) ?? ""
        if resolvedConnectionMode == .remote,
           configRemoteTransport != .direct,
           storedRemoteTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let host = AppState.remoteHost(from: configRemoteUrl)
        {
            self.remoteTarget = "\(NSUserName())@\(host)"
        } else {
            self.remoteTarget = storedRemoteTarget
        }
        self.remoteUrl = configRemoteUrl ?? ""
        self.remoteIdentity = UserDefaults.standard.string(forKey: remoteIdentityKey) ?? ""
        self.remoteProjectRoot = UserDefaults.standard.string(forKey: remoteProjectRootKey) ?? ""
        self.remoteCliPath = UserDefaults.standard.string(forKey: remoteCliPathKey) ?? ""
        self.canvasEnabled = UserDefaults.standard.object(forKey: canvasEnabledKey) as? Bool ?? true
        let execDefaults = ExecApprovalsStore.resolveDefaults()
        self.execApprovalMode = ExecApprovalQuickMode.from(security: execDefaults.security, ask: execDefaults.ask)
        self.peekabooBridgeEnabled = UserDefaults.standard
            .object(forKey: peekabooBridgeEnabledKey) as? Bool ?? true
        if !self.isPreview {
            Task.detached(priority: .utility) { [weak self] in
                let current = await LaunchAgentManager.status()
                await MainActor.run { [weak self] in self?.launchAtLogin = current }
            }
        }

        if self.swabbleEnabled, !PermissionManager.voiceWakePermissionsGranted() {
            self.swabbleEnabled = false
        }
        if self.talkEnabled, !PermissionManager.voiceWakePermissionsGranted() {
            self.talkEnabled = false
        }

        if !self.isPreview {
            Task { await VoiceWakeRuntime.shared.refresh(state: self) }
            Task { await TalkModeController.shared.setEnabled(self.talkEnabled) }
        }

        self.isInitializing = false
        if !self.isPreview {
            self.startConfigWatcher()
        }
    }

    /// 析构函数
    @MainActor
    deinit {
        self.configWatcher?.stop()
    }

    /// 从 URL 字符串中提取远程主机
    private static func remoteHost(from urlString: String?) -> String? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return nil
        }
        return host
    }

    /// 清理 SSH 目标字符串
    private static func sanitizeSSHTarget(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ssh ") {
            return trimmed.replacingOccurrences(of: "ssh ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// 启动配置文件监视器
    private func startConfigWatcher() {
        let configUrl = MoltbotConfigFile.url()
        self.configWatcher = ConfigFileWatcher(url: configUrl) { [weak self] in
            Task { @MainActor in
                self?.applyConfigFromDisk()
            }
        }
        self.configWatcher?.start()
    }

    /// 从磁盘应用配置
    private func applyConfigFromDisk() {
        let root = MoltbotConfigFile.loadDict()
        self.applyConfigOverrides(root)
    }

    /// 应用配置覆盖
    private func applyConfigOverrides(_ root: [String: Any]) {
        let gateway = root["gateway"] as? [String: Any]
        let modeRaw = (gateway?["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let remoteUrl = GatewayRemoteConfig.resolveUrlString(root: root)
        let hasRemoteUrl = !(remoteUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ?? true)
        let remoteTransport = GatewayRemoteConfig.resolveTransport(root: root)

        let desiredMode: ConnectionMode? = switch modeRaw {
        case "local":
            .local
        case "remote":
            .remote
        case "unconfigured":
            .unconfigured
        default:
            nil
        }

        if let desiredMode {
            if desiredMode != self.connectionMode {
                self.connectionMode = desiredMode
            }
        } else if hasRemoteUrl, self.connectionMode != .remote {
            self.connectionMode = .remote
        }

        if remoteTransport != self.remoteTransport {
            self.remoteTransport = remoteTransport
        }
        let remoteUrlText = remoteUrl ?? ""
        if remoteUrlText != self.remoteUrl {
            self.remoteUrl = remoteUrlText
        }

        let targetMode = desiredMode ?? self.connectionMode
        if targetMode == .remote,
           remoteTransport != .direct,
           let host = AppState.remoteHost(from: remoteUrl)
        {
            self.updateRemoteTarget(host: host)
        }
    }

    /// 更新远程目标
    private func updateRemoteTarget(host: String) {
        let trimmed = self.remoteTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = CommandResolver.parseSSHTarget(trimmed) else { return }
        let trimmedUser = parsed.user?.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = (trimmedUser?.isEmpty ?? true) ? nil : trimmedUser
        let port = parsed.port
        let assembled: String
        if let user {
            assembled = port == 22 ? "\(user)@\(host)" : "\(user)@\(host):\(port)"
        } else {
            assembled = port == 22 ? host : "\(host):\(port)"
        }
        if assembled != self.remoteTarget {
            self.remoteTarget = assembled
        }
    }

    /// 同步网关配置（如果需要）
    private func syncGatewayConfigIfNeeded() {
        guard !self.isPreview, !self.isInitializing else { return }

        let connectionMode = self.connectionMode
        let remoteTarget = self.remoteTarget
        let remoteIdentity = self.remoteIdentity
        let remoteTransport = self.remoteTransport
        let remoteUrl = self.remoteUrl
        let desiredMode: String? = switch connectionMode {
        case .local:
            "local"
        case .remote:
            "remote"
        case .unconfigured:
            nil
        }
        let remoteHost = connectionMode == .remote
            ? CommandResolver.parseSSHTarget(remoteTarget)?.host
            : nil

        Task { @MainActor in
            // 保持应用专用连接设置为本地，以避免覆盖远程网关配置。
            var root = MoltbotConfigFile.loadDict()
            var gateway = root["gateway"] as? [String: Any] ?? [:]
            var changed = false

            let currentMode = (gateway["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let desiredMode {
                if currentMode != desiredMode {
                    gateway["mode"] = desiredMode
                    changed = true
                }
            } else if currentMode != nil {
                gateway.removeValue(forKey: "mode")
                changed = true
            }

            if connectionMode == .remote {
                var remote = gateway["remote"] as? [String: Any] ?? [:]
                var remoteChanged = false

                if remoteTransport == .direct {
                    let trimmedUrl = remoteUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedUrl.isEmpty {
                        if remote["url"] != nil {
                            remote.removeValue(forKey: "url")
                            remoteChanged = true
                        }
                    } else {
                        let normalizedUrl = GatewayRemoteConfig.normalizeGatewayUrlString(trimmedUrl) ?? trimmedUrl
                        if (remote["url"] as? String) != normalizedUrl {
                            remote["url"] = normalizedUrl
                            remoteChanged = true
                        }
                    }
                    if (remote["transport"] as? String) != RemoteTransport.direct.rawValue {
                        remote["transport"] = RemoteTransport.direct.rawValue
                        remoteChanged = true
                    }
                } else {
                    if remote["transport"] != nil {
                        remote.removeValue(forKey: "transport")
                        remoteChanged = true
                    }
                    if let host = remoteHost {
                        let existingUrl = (remote["url"] as? String)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        let parsedExisting = existingUrl.isEmpty ? nil : URL(string: existingUrl)
                        let scheme = parsedExisting?.scheme?.isEmpty == false ? parsedExisting?.scheme : "ws"
                        let port = parsedExisting?.port ?? 18789
                        let desiredUrl = "\(scheme ?? "ws")://\(host):\(port)"
                        if existingUrl != desiredUrl {
                            remote["url"] = desiredUrl
                            remoteChanged = true
                        }
                    }

                    let sanitizedTarget = Self.sanitizeSSHTarget(remoteTarget)
                    if !sanitizedTarget.isEmpty {
                        if (remote["sshTarget"] as? String) != sanitizedTarget {
                            remote["sshTarget"] = sanitizedTarget
                            remoteChanged = true
                        }
                    } else if remote["sshTarget"] != nil {
                        remote.removeValue(forKey: "sshTarget")
                        remoteChanged = true
                    }

                    let trimmedIdentity = remoteIdentity.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedIdentity.isEmpty {
                        if (remote["sshIdentity"] as? String) != trimmedIdentity {
                            remote["sshIdentity"] = trimmedIdentity
                            remoteChanged = true
                        }
                    } else if remote["sshIdentity"] != nil {
                        remote.removeValue(forKey: "sshIdentity")
                        remoteChanged = true
                    }
                }

                if remoteChanged {
                    gateway["remote"] = remote
                    changed = true
                }
            }

            guard changed else { return }
            if gateway.isEmpty {
                root.removeValue(forKey: "gateway")
            } else {
                root["gateway"] = gateway
            }
            MoltbotConfigFile.saveDict(root)
        }
    }

    /// 触发语音耳朵增强
    func triggerVoiceEars(ttl: TimeInterval? = 5) {
        self.earBoostTask?.cancel()
        self.earBoostActive = true

        guard let ttl else { return }

        self.earBoostTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(ttl * 1_000_000_000))
            await MainActor.run { [weak self] in self?.earBoostActive = false }
        }
    }

    /// 停止语音耳朵增强
    func stopVoiceEars() {
        self.earBoostTask?.cancel()
        self.earBoostTask = nil
        self.earBoostActive = false
    }

    /// 执行一次眨眼动画
    func blinkOnce() {
        self.blinkTick &+= 1
    }

    /// 执行发送庆祝动画
    func celebrateSend() {
        self.sendCelebrationTick &+= 1
    }

    /// 设置语音唤醒启用状态
    func setVoiceWakeEnabled(_ enabled: Bool) async {
        guard voiceWakeSupported else {
            self.swabbleEnabled = false
            return
        }

        self.swabbleEnabled = enabled
        guard !self.isPreview else { return }

        if !enabled {
            Task { await VoiceWakeRuntime.shared.refresh(state: self) }
            return
        }

        if PermissionManager.voiceWakePermissionsGranted() {
            Task { await VoiceWakeRuntime.shared.refresh(state: self) }
            return
        }

        let granted = await PermissionManager.ensureVoiceWakePermissions(interactive: true)
        self.swabbleEnabled = granted
        Task { await VoiceWakeRuntime.shared.refresh(state: self) }
    }

    /// 设置通话模式启用状态
    func setTalkEnabled(_ enabled: Bool) async {
        guard voiceWakeSupported else {
            self.talkEnabled = false
            await GatewayConnection.shared.talkMode(enabled: false, phase: "disabled")
            return
        }

        self.talkEnabled = enabled
        guard !self.isPreview else { return }

        if !enabled {
            await GatewayConnection.shared.talkMode(enabled: false, phase: "disabled")
            return
        }

        if PermissionManager.voiceWakePermissionsGranted() {
            await GatewayConnection.shared.talkMode(enabled: true, phase: "enabled")
            return
        }

        let granted = await PermissionManager.ensureVoiceWakePermissions(interactive: true)
        self.talkEnabled = granted
        await GatewayConnection.shared.talkMode(enabled: granted, phase: granted ? "enabled" : "denied")
    }

    // MARK: - 全局唤醒词同步（Gateway 拥有）

    /// 应用全局语音唤醒触发词
    func applyGlobalVoiceWakeTriggers(_ triggers: [String]) {
        self.suppressVoiceWakeGlobalSync = true
        self.swabbleTriggerWords = triggers
        self.suppressVoiceWakeGlobalSync = false
    }

    /// 调度语音唤醒全局同步（如果需要）
    private func scheduleVoiceWakeGlobalSyncIfNeeded() {
        guard !self.suppressVoiceWakeGlobalSync else { return }
        let sanitized = sanitizeVoiceWakeTriggers(self.swabbleTriggerWords)
        self.voiceWakeGlobalSyncTask?.cancel()
        self.voiceWakeGlobalSyncTask = Task { [sanitized] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            await GatewayConnection.shared.voiceWakeSetTriggers(sanitized)
        }
    }

    /// 设置工作状态
    func setWorking(_ working: Bool) {
        self.isWorking = working
    }

    // MARK: - 提示音持久化

    /// 加载提示音
    private static func loadChime(key: String, fallback: VoiceWakeChime) -> VoiceWakeChime {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        if let decoded = try? JSONDecoder().decode(VoiceWakeChime.self, from: data) {
            return decoded
        }
        return fallback
    }

    /// 存储提示音
    private func storeChime(_ chime: VoiceWakeChime, key: String) {
        guard let data = try? JSONEncoder().encode(chime) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// AppState 扩展
 extension AppState {
    /// 预览状态
    static var preview: AppState {
        let state = AppState(preview: true)
        state.isPaused = false
        state.launchAtLogin = true
        state.onboardingSeen = true
        state.debugPaneEnabled = true
        state.swabbleEnabled = true
        state.swabbleTriggerWords = ["Claude", "Computer", "Jarvis"]
        state.voiceWakeTriggerChime = .system(name: "Glass")
        state.voiceWakeSendChime = .system(name: "Ping")
        state.iconAnimationsEnabled = true
        state.showDockIcon = true
        state.voiceWakeMicID = "BuiltInMic"
        state.voiceWakeMicName = "Built-in Microphone"
        state.voiceWakeLocaleID = Locale.current.identifier
        state.voiceWakeAdditionalLocaleIDs = ["en-US", "de-DE"]
        state.voicePushToTalkEnabled = false
        state.talkEnabled = false
        state.iconOverride = .system
        state.heartbeatsEnabled = true
        state.connectionMode = .local
        state.remoteTransport = .ssh
        state.canvasEnabled = true
        state.remoteTarget = "user@example.com"
        state.remoteUrl = "wss://gateway.example.ts.net"
        state.remoteIdentity = "~/.ssh/id_ed25519"
        state.remoteProjectRoot = "~/Projects/moltbot"
        state.remoteCliPath = ""
        return state
    }
}

/// 应用状态存储
@MainActor
enum AppStateStore {
    static let shared = AppState()
    static var isPausedFlag: Bool { UserDefaults.standard.bool(forKey: pauseDefaultsKey) }

    /// 更新开机自启动设置
    static func updateLaunchAtLogin(enabled: Bool) {
        Task.detached(priority: .utility) {
            await LaunchAgentManager.set(enabled: enabled, bundlePath: Bundle.main.bundlePath)
        }
    }

    /// 画布启用状态
    static var canvasEnabled: Bool {
        UserDefaults.standard.object(forKey: canvasEnabledKey) as? Bool ?? true
    }
}

/// 应用激活策略
@MainActor
enum AppActivationPolicy {
    /// 应用 Dock 图标显示设置
    static func apply(showDockIcon: Bool) {
        _ = showDockIcon
        DockIconManager.shared.updateDockVisibility()
    }
}
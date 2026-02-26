import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Moltbot 菜单栏扩展的菜单内容
struct MenuContent: View {
    @Bindable var state: AppState
    let updater: UpdaterProviding?
    @Bindable private var updateStatus: UpdateStatus
    private let gatewayManager = GatewayProcessManager.shared
    private let healthStore = HealthStore.shared
    private let heartbeatStore = HeartbeatStore.shared
    private let controlChannel = ControlChannel.shared
    private let activityStore = WorkActivityStore.shared
    @Bindable private var pairingPrompter = NodePairingApprovalPrompter.shared
    @Bindable private var devicePairingPrompter = DevicePairingApprovalPrompter.shared
    @Environment(\.openSettings) private var openSettings
    @State private var availableMics: [AudioInputDevice] = []
    @State private var loadingMics = false
    @State private var micObserver = AudioInputDeviceObserver()
    @State private var micRefreshTask: Task<Void, Never>?
    @State private var browserControlEnabled = true
    @AppStorage(cameraEnabledKey) private var cameraEnabled: Bool = false
    @AppStorage(appLogLevelKey) private var appLogLevelRaw: String = AppLogLevel.default.rawValue
    @AppStorage(debugFileLogEnabledKey) private var appFileLoggingEnabled: Bool = false

    init(state: AppState, updater: UpdaterProviding?) {
        self._state = Bindable(wrappedValue: state)
        self.updater = updater
        self._updateStatus = Bindable(wrappedValue: updater?.updateStatus ?? UpdateStatus.disabled)
    }

    /// 执行批准模式绑定
    private var execApprovalModeBinding: Binding<ExecApprovalQuickMode> {
        Binding(
            get: { self.state.execApprovalMode },
            set: { self.state.execApprovalMode = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: self.activeBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(self.connectionLabel)
                    self.statusLine(label: self.healthStatus.label, color: self.healthStatus.color)
                    if self.pairingPrompter.pendingCount > 0 {
                        let repairCount = self.pairingPrompter.pendingRepairCount
                        let repairSuffix = repairCount > 0 ? " · \(repairCount) 修复" : ""
                        self.statusLine(
                            label: "配对批准待处理 (\(self.pairingPrompter.pendingCount))\(repairSuffix)",
                            color: .orange)
                    }
                    if self.devicePairingPrompter.pendingCount > 0 {
                        let repairCount = self.devicePairingPrompter.pendingRepairCount
                        let repairSuffix = repairCount > 0 ? " · \(repairCount) 修复" : ""
                        self.statusLine(
                            label: "设备配对待处理 (\(self.devicePairingPrompter.pendingCount))\(repairSuffix)",
                            color: .orange)
                    }
                }
            }
            .disabled(self.state.connectionMode == .unconfigured)

            Divider()
            Toggle(isOn: self.heartbeatsBinding) {
                HStack(spacing: 8) {
                    Label("发送心跳", systemImage: "waveform.path.ecg")
                    Spacer(minLength: 0)
                    self.statusLine(label: self.heartbeatStatus.label, color: self.heartbeatStatus.color)
                }
            }
            Toggle(
                isOn: Binding(
                    get: { self.browserControlEnabled },
                    set: { enabled in
                        self.browserControlEnabled = enabled
                        Task { await self.saveBrowserControlEnabled(enabled) }
                    })) {
                Label("浏览器控制", systemImage: "globe")
            }
            Toggle(isOn: self.$cameraEnabled) {
                Label("允许摄像头", systemImage: "camera")
            }
            Picker(selection: self.execApprovalModeBinding) {
                ForEach(ExecApprovalQuickMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Label("执行批准", systemImage: "terminal")
            }
            Toggle(isOn: Binding(get: { self.state.canvasEnabled }, set: { self.state.canvasEnabled = $0 })) {
                Label("允许画布", systemImage: "rectangle.and.pencil.and.ellipsis")
            }
            .onChange(of: self.state.canvasEnabled) { _, enabled in
                if !enabled {
                    CanvasManager.shared.hideAll()
                }
            }
            Toggle(isOn: self.voiceWakeBinding) {
                Label("语音唤醒", systemImage: "mic.fill")
            }
            .disabled(!voiceWakeSupported)
            .opacity(voiceWakeSupported ? 1 : 0.5)
            if self.showVoiceWakeMicPicker {
                self.voiceWakeMicMenu
            }
            Divider()
            Button {
                Task { @MainActor in
                    await self.openDashboard()
                }
            } label: {
                Label("打开仪表板", systemImage: "gauge")
            }
            Button {
                Task { @MainActor in
                    let sessionKey = await WebChatManager.shared.preferredSessionKey()
                    WebChatManager.shared.show(sessionKey: sessionKey)
                }
            } label: {
                Label("打开聊天", systemImage: "bubble.left.and.bubble.right")
            }
            if self.state.canvasEnabled {
                Button {
                    Task { @MainActor in
                        if self.state.canvasPanelVisible {
                            CanvasManager.shared.hideAll()
                        } else {
                            let sessionKey = await GatewayConnection.shared.mainSessionKey()
                            // 不要在重新打开时强制导航：保留当前 Web 视图状态。
                            _ = try? CanvasManager.shared.show(sessionKey: sessionKey, path: nil)
                        }
                    }
                } label: {
                    Label(
                        self.state.canvasPanelVisible ? "关闭画布" : "打开画布",
                        systemImage: "rectangle.inset.filled.on.rectangle")
                }
            }
            Button {
                Task { await self.state.setTalkEnabled(!self.state.talkEnabled) }
            } label: {
                Label(self.state.talkEnabled ? "停止对话模式" : "对话模式", systemImage: "waveform.circle.fill")
            }
            .disabled(!voiceWakeSupported)
            .opacity(voiceWakeSupported ? 1 : 0.5)
            Divider()
            Button("设置…") { self.open(tab: .general) }
                .keyboardShortcut(",", modifiers: [.command])
            self.debugMenu
            Button("关于 Moltbot") { self.open(tab: .about) }
            if let updater, updater.isAvailable, self.updateStatus.isUpdateReady {
                Button("更新就绪，现在重启？") { updater.checkForUpdates(nil) }
            }
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .task(id: self.state.swabbleEnabled) {
            if self.state.swabbleEnabled {
                await self.loadMicrophones(force: true)
            }
        }
        .task {
            VoicePushToTalkHotkey.shared.setEnabled(voiceWakeSupported && self.state.voicePushToTalkEnabled)
        }
        .onChange(of: self.state.voicePushToTalkEnabled) { _, enabled in
            VoicePushToTalkHotkey.shared.setEnabled(voiceWakeSupported && enabled)
        }
        .task(id: self.state.connectionMode) {
            await self.loadBrowserControlEnabled()
        }
        .onAppear {
            self.startMicObserver()
        }
        .onDisappear {
            self.micRefreshTask?.cancel()
            self.micRefreshTask = nil
            self.micObserver.stop()
        }
        .task { @MainActor in
            SettingsWindowOpener.shared.register(openSettings: self.openSettings)
        }
    }

    /// 连接标签
    private var connectionLabel: String {
        switch self.state.connectionMode {
        case .unconfigured:
            "Moltbot 未配置"
        case .remote:
            "远程 Moltbot 活动"
        case .local:
            "Moltbot 活动"
        }
    }

    /// 加载浏览器控制启用状态
    private func loadBrowserControlEnabled() async {
        let root = await ConfigStore.load()
        let browser = root["browser"] as? [String: Any]
        let enabled = browser?["enabled"] as? Bool ?? true
        await MainActor.run { self.browserControlEnabled = enabled }
    }

    /// 保存浏览器控制启用状态
    private func saveBrowserControlEnabled(_ enabled: Bool) async {
        let (success, _) = await MenuContent.buildAndSaveBrowserEnabled(enabled)
        if !success {
            await self.loadBrowserControlEnabled()
        }
    }

    /// 构建并保存浏览器控制启用状态
    @MainActor
    private static func buildAndSaveBrowserEnabled(_ enabled: Bool) async -> (Bool, ()) {
        var root = await ConfigStore.load()
        var browser = root["browser"] as? [String: Any] ?? [:]
        browser["enabled"] = enabled
        root["browser"] = browser
        do {
            try await ConfigStore.save(root)
            return (true, ())
        } catch {
            return (false, ())
        }
    }

    /// 调试菜单
    @ViewBuilder
    private var debugMenu: some View {
        if self.state.debugPaneEnabled {
            Menu("调试") {
                Button {
                    DebugActions.openConfigFolder()
                } label: {
                    Label("打开配置文件夹", systemImage: "folder")
                }
                Button {
                    Task { await DebugActions.runHealthCheckNow() }
                } label: {
                    Label("立即运行健康检查", systemImage: "stethoscope")
                }
                Button {
                    Task { _ = await DebugActions.sendTestHeartbeat() }
                } label: {
                    Label("发送测试心跳", systemImage: "waveform.path.ecg")
                }
                if self.state.connectionMode == .remote {
                    Button {
                        Task { @MainActor in
                            let result = await DebugActions.resetGatewayTunnel()
                            self.presentDebugResult(result, title: "远程隧道")
                        }
                    } label: {
                        Label("重置远程隧道", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Button {
                    Task { _ = await DebugActions.toggleVerboseLoggingMain() }
                } label: {
                    Label(
                        DebugActions.verboseLoggingEnabledMain
                            ? "详细日志（主进程）：开"
                            : "详细日志（主进程）：关",
                        systemImage: "text.alignleft")
                }
                Menu {
                    Picker("详细程度", selection: self.$appLogLevelRaw) {
                        ForEach(AppLogLevel.allCases) { level in
                            Text(level.title).tag(level.rawValue)
                        }
                    }
                    Toggle(isOn: self.$appFileLoggingEnabled) {
                        Label(
                            self.appFileLoggingEnabled
                                ? "文件日志：开"
                                : "文件日志：关",
                            systemImage: "doc.text.magnifyingglass")
                    }
                } label: {
                    Label("应用日志", systemImage: "doc.text")
                }
                Button {
                    DebugActions.openSessionStore()
                } label: {
                    Label("打开会话存储", systemImage: "externaldrive")
                }
                Divider()
                Button {
                    DebugActions.openAgentEventsWindow()
                } label: {
                    Label("打开代理事件…", systemImage: "bolt.horizontal.circle")
                }
                Button {
                    DebugActions.openLog()
                } label: {
                    Label("打开日志", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    Task { _ = await DebugActions.sendDebugVoice() }
                } label: {
                    Label("发送调试语音文本", systemImage: "waveform.circle")
                }
                Button {
                    Task { await DebugActions.sendTestNotification() }
                } label: {
                    Label("发送测试通知", systemImage: "bell")
                }
                Divider()
                if self.state.connectionMode == .local {
                    Button {
                        DebugActions.restartGateway()
                    } label: {
                        Label("重启网关", systemImage: "arrow.clockwise")
                    }
                }
                Button {
                    DebugActions.restartOnboarding()
                } label: {
                    Label("重启引导", systemImage: "arrow.counterclockwise")
                }
                Button {
                    DebugActions.restartApp()
                } label: {
                    Label("重启应用", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    /// 打开设置标签
    private func open(tab: SettingsTab) {
        SettingsTabRouter.request(tab)
        NSApp.activate(ignoringOtherApps: true)
        self.openSettings()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .moltbotSelectSettingsTab, object: tab)
        }
    }

    /// 打开仪表板
    @MainActor
    private func openDashboard() async {
        do {
            let config = try await GatewayEndpointStore.shared.requireConfig()
            let url = try GatewayEndpointStore.dashboardURL(for: config)
            NSWorkspace.shared.open(url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "仪表板不可用"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// 健康状态
    private var healthStatus: (label: String, color: Color) {
        if let activity = self.activityStore.current {
            let color: Color = activity.role == .main ? .accentColor : .gray
            let roleLabel = activity.role == .main ? "主进程" : "其他"
            let text = "\(roleLabel) · \(activity.label)"
            return (text, color)
        }

        let health = self.healthStore.state
        let isRefreshing = self.healthStore.isRefreshing
        let lastAge = self.healthStore.lastSuccess.map { age(from: $0) }

        if isRefreshing {
            return ("健康检查运行中…", health.tint)
        }

        switch health {
        case .ok:
            let ageText = lastAge.map { " · 已检查 \($0)" } ?? ""
            return ("健康正常\(ageText)", .green)
        case .linkingNeeded:
            return ("健康：需要登录", .red)
        case let .degraded(reason):
            let detail = HealthStore.shared.degradedSummary ?? reason
            let ageText = lastAge.map { " · 已检查 \($0)" } ?? ""
            return ("\(detail)\(ageText)", .orange)
        case .unknown:
            return ("健康待定", .secondary)
        }
    }

    /// 心跳状态
    private var heartbeatStatus: (label: String, color: Color) {
        if case .degraded = self.controlChannel.state {
            return ("控制通道已断开", .red)
        } else if let evt = self.heartbeatStore.lastEvent {
            let ageText = age(from: Date(timeIntervalSince1970: evt.ts / 1000))
            switch evt.status {
            case "sent":
                return ("上次心跳发送 · \(ageText)", .blue)
            case "ok-empty", "ok-token":
                return ("心跳正常 · \(ageText)", .green)
            case "skipped":
                return ("心跳已跳过 · \(ageText)", .secondary)
            case "failed":
                return ("心跳失败 · \(ageText)", .red)
            default:
                return ("心跳 · \(ageText)", .secondary)
            }
        } else {
            return ("暂无心跳", .secondary)
        }
    }

    /// 状态行视图
    @ViewBuilder
    private func statusLine(label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
        .padding(.top, 2)
    }

    /// 活动绑定
    private var activeBinding: Binding<Bool> {
        Binding(get: { !self.state.isPaused }, set: { self.state.isPaused = !$0 })
    }

    /// 心跳绑定
    private var heartbeatsBinding: Binding<Bool> {
        Binding(get: { self.state.heartbeatsEnabled }, set: { self.state.heartbeatsEnabled = $0 })
    }

    /// 语音唤醒绑定
    private var voiceWakeBinding: Binding<Bool> {
        Binding(
            get: { self.state.swabbleEnabled },
            set: { newValue in
                Task { await self.state.setVoiceWakeEnabled(newValue) }
            })
    }

    /// 是否显示语音唤醒麦克风选择器
    private var showVoiceWakeMicPicker: Bool {
        voiceWakeSupported && self.state.swabbleEnabled
    }

    /// 语音唤醒麦克风菜单
    private var voiceWakeMicMenu: some View {
        Menu {
            self.microphoneMenuItems

            if self.loadingMics {
                Divider()
                Label("正在刷新麦克风…", systemImage: "arrow.triangle.2.circlepath")
                    .labelStyle(.titleOnly)
                    .foregroundStyle(.secondary)
                    .disabled(true)
            }
        } label: {
            HStack {
                Text("麦克风")
                Spacer()
                Text(self.selectedMicLabel)
                    .foregroundStyle(.secondary)
            }
        }
        .task { await self.loadMicrophones() }
    }

    /// 选中的麦克风标签
    private var selectedMicLabel: String {
        if self.state.voiceWakeMicID.isEmpty { return self.defaultMicLabel }
        if let match = self.availableMics.first(where: { $0.uid == self.state.voiceWakeMicID }) {
            return match.name
        }
        if !self.state.voiceWakeMicName.isEmpty { return self.state.voiceWakeMicName }
        return "不可用"
    }

    /// 麦克风菜单项
    private var microphoneMenuItems: some View {
        Group {
            if self.isSelectedMicUnavailable {
                Label("已断开（使用系统默认）", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .disabled(true)
                Divider()
            }
            Button {
                self.state.voiceWakeMicID = ""
                self.state.voiceWakeMicName = ""
            } label: {
                Label(self.defaultMicLabel, systemImage: self.state.voiceWakeMicID.isEmpty ? "checkmark" : "")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)

            ForEach(self.availableMics) { mic in
                Button {
                    self.state.voiceWakeMicID = mic.uid
                    self.state.voiceWakeMicName = mic.name
                } label: {
                    Label(mic.name, systemImage: self.state.voiceWakeMicID == mic.uid ? "checkmark" : "")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// 选中的麦克风是否不可用
    private var isSelectedMicUnavailable: Bool {
        let selected = self.state.voiceWakeMicID
        guard !selected.isEmpty else { return false }
        return !self.availableMics.contains(where: { $0.uid == selected })
    }

    /// 默认麦克风标签
    private var defaultMicLabel: String {
        if let host = Host.current().localizedName, !host.isEmpty {
            return "自动检测 (\(host))"
        }
        return "系统默认"
    }

    /// 展示调试结果
    @MainActor
    private func presentDebugResult(_ result: Result<String, DebugActionError>, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        switch result {
        case let .success(message):
            alert.informativeText = message
            alert.alertStyle = .informational
        case let .failure(error):
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    /// 加载麦克风
    @MainActor
    private func loadMicrophones(force: Bool = false) async {
        guard self.showVoiceWakeMicPicker else {
            self.availableMics = []
            self.loadingMics = false
            return
        }
        if !force, !self.availableMics.isEmpty { return }
        self.loadingMics = true
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external, .microphone],
            mediaType: .audio,
            position: .unspecified)
        let connectedDevices = discovery.devices.filter(\.isConnected)
        self.availableMics = connectedDevices
            .sorted { lhs, rhs in
                lhs.localizedName.localizedCaseInsensitiveCompare(rhs.localizedName) == .orderedAscending
            }
            .map { AudioInputDevice(uid: $0.uniqueID, name: $0.localizedName) }
        self.availableMics = self.filterAliveInputs(self.availableMics)
        self.updateSelectedMicName()
        self.loadingMics = false
    }

    /// 启动麦克风观察器
    private func startMicObserver() {
        self.micObserver.start {
            Task { @MainActor in
                self.scheduleMicRefresh()
            }
        }
    }

    /// 调度麦克风刷新
    @MainActor
    private func scheduleMicRefresh() {
        self.micRefreshTask?.cancel()
        self.micRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self.loadMicrophones(force: true)
        }
    }

    /// 过滤可用的输入设备
    private func filterAliveInputs(_ inputs: [AudioInputDevice]) -> [AudioInputDevice] {
        let aliveUIDs = AudioInputDeviceObserver.aliveInputDeviceUIDs()
        guard !aliveUIDs.isEmpty else { return inputs }
        return inputs.filter { aliveUIDs.contains($0.uid) }
    }

    /// 更新选中的麦克风名称
    @MainActor
    private func updateSelectedMicName() {
        let selected = self.state.voiceWakeMicID
        if selected.isEmpty {
            self.state.voiceWakeMicName = ""
            return
        }
        if let match = self.availableMics.first(where: { $0.uid == selected }) {
            self.state.voiceWakeMicName = match.name
        }
    }

    /// 音频输入设备
    private struct AudioInputDevice: Identifiable, Equatable {
        let uid: String
        let name: String
        var id: String { self.uid }
    }
}

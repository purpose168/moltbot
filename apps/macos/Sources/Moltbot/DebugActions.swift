import AppKit
import Foundation
import SwiftUI

/// 调试操作
/// 提供各种调试功能，如打开日志、重启网关、发送测试通知等
enum DebugActions {
    private static let verboseDefaultsKey = "moltbot.debug.verboseMain"
    private static let sessionMenuLimit = 12
    private static let onboardingSeenKey = "moltbot.onboardingSeen"

    /// 打开代理事件窗口
    @MainActor
    static func openAgentEventsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "代理事件"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AgentEventsWindow())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 打开日志
    @MainActor
    static func openLog() {
        let path = self.pinoLogPath()
        let url = URL(fileURLWithPath: path)
        guard FileManager().fileExists(atPath: path) else {
            let alert = NSAlert()
            alert.messageText = "未找到日志文件"
            alert.informativeText = path
            alert.runModal()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 打开配置文件夹
    @MainActor
    static func openConfigFolder() {
        let url = FileManager()
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".clawdbot", isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 打开会话存储
    @MainActor
    static func openSessionStore() {
        if AppStateStore.shared.connectionMode == .remote {
            let alert = NSAlert()
            alert.messageText = "远程模式"
            alert.informativeText = "远程模式下会话存储位于网关主机上。"
            alert.runModal()
            return
        }
        let path = self.resolveSessionStorePath()
        let url = URL(fileURLWithPath: path)
        if FileManager().fileExists(atPath: path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    /// 发送测试通知
    static func sendTestNotification() async {
        _ = await NotificationManager().send(title: "Moltbot", body: "测试通知", sound: nil)
    }

    /// 发送调试语音
    static func sendDebugVoice() async -> Result<String, DebugActionError> {
        let message = """
        这是来自 Mac 应用的调试测试。如果您收到了，请回复"调试测试有效（还有个双关语）"。
        """
        let result = await VoiceWakeForwarder.forward(transcript: message)
        switch result {
        case .success:
            return .success("已发送。等待回复。")
        case let .failure(error):
            let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.message("发送失败：\(detail)"))
        }
    }

    /// 重启网关
    static func restartGateway() {
        Task { @MainActor in
            switch AppStateStore.shared.connectionMode {
            case .local:
                GatewayProcessManager.shared.stop()
                // 启动控制通道 + 健康检查，以便 UI 立即恢复。
                await GatewayConnection.shared.shutdown()
                try? await Task.sleep(nanoseconds: 300_000_000)
                GatewayProcessManager.shared.setActive(true)
                Task { try? await ControlChannel.shared.configure(mode: .local) }
                Task { await HealthStore.shared.refresh(onDemand: true) }

            case .remote:
                // 在远程模式下，没有本地网关可以重启。"重启网关"应该
                // 重置 SSH 控制隧道 + 重新连接，以便菜单恢复。
                await RemoteTunnelManager.shared.stopAll()
                await GatewayConnection.shared.shutdown()
                do {
                    _ = try await RemoteTunnelManager.shared.ensureControlTunnel()
                    let settings = CommandResolver.connectionSettings()
                    try await ControlChannel.shared.configure(mode: .remote(
                        target: settings.target,
                        identity: settings.identity))
                } catch {
                    // ControlChannel 将显示降级状态；同时刷新健康状态以更新菜单文本。
                    Task { await HealthStore.shared.refresh(onDemand: true) }
                }

            case .unconfigured:
                await GatewayConnection.shared.shutdown()
                await ControlChannel.shared.disconnect()
            }
        }
    }

    /// 重置网关隧道
    static func resetGatewayTunnel() async -> Result<String, DebugActionError> {
        let mode = CommandResolver.connectionSettings().mode
        guard mode == .remote else {
            return .failure(.message("未启用远程模式。"))
        }
        await RemoteTunnelManager.shared.stopAll()
        await GatewayConnection.shared.shutdown()
        do {
            _ = try await RemoteTunnelManager.shared.ensureControlTunnel()
            let settings = CommandResolver.connectionSettings()
            try await ControlChannel.shared.configure(mode: .remote(
                target: settings.target,
                identity: settings.identity))
            await HealthStore.shared.refresh(onDemand: true)
            return .success("SSH 隧道已重置。")
        } catch {
            Task { await HealthStore.shared.refresh(onDemand: true) }
            return .failure(.message(error.localizedDescription))
        }
    }

    /// 获取 Pino 日志路径
    static func pinoLogPath() -> String {
        LogLocator.bestLogFile()?.path ?? LogLocator.launchdLogPath
    }

    /// 立即运行健康检查
    @MainActor
    static func runHealthCheckNow() async {
        await HealthStore.shared.refresh(onDemand: true)
    }

    /// 发送测试心跳
    static func sendTestHeartbeat() async -> Result<ControlHeartbeatEvent?, Error> {
        do {
            _ = await GatewayConnection.shared.setHeartbeatsEnabled(true)
            await ControlChannel.shared.configure()
            let data = try await ControlChannel.shared.request(method: "last-heartbeat")
            if let evt = try? JSONDecoder().decode(ControlHeartbeatEvent.self, from: data) {
                return .success(evt)
            }
            return .success(nil)
        } catch {
            return .failure(error)
        }
    }

    /// 主进程详细日志是否启用
    static var verboseLoggingEnabledMain: Bool {
        UserDefaults.standard.bool(forKey: self.verboseDefaultsKey)
    }

    /// 切换主进程详细日志
    static func toggleVerboseLoggingMain() async -> Bool {
        let newValue = !self.verboseLoggingEnabledMain
        UserDefaults.standard.set(newValue, forKey: self.verboseDefaultsKey)
        _ = try? await ControlChannel.shared.request(
            method: "system-event",
            params: ["text": AnyHashable("verbose-main:\(newValue ? "on" : "off")")])
        return newValue
    }

    /// 重启应用
    @MainActor
    static func restartApp() {
        let url = Bundle.main.bundleURL
        let task = Process()
        // 在此实例退出后不久重新启动，以便即使在调试时也能获得真正的重启。
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.2; open -n \"$1\"", "_", url.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// 重启引导
    @MainActor
    static func restartOnboarding() {
        UserDefaults.standard.set(false, forKey: self.onboardingSeenKey)
        UserDefaults.standard.set(0, forKey: onboardingVersionKey)
        AppStateStore.shared.onboardingSeen = false
        OnboardingController.shared.restart()
    }

    /// 解析会话存储路径
    @MainActor
    private static func resolveSessionStorePath() -> String {
        let defaultPath = SessionLoader.defaultStorePath
        let configURL = FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(".clawdbot/moltbot.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let session = parsed["session"] as? [String: Any],
            let path = session["store"] as? String,
            !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return defaultPath
        }
        return path
    }

    // MARK: - 会话（思考/详细）

    /// 获取最近的会话
    static func recentSessions(limit: Int = sessionMenuLimit) async -> [SessionRow] {
        guard let snapshot = try? await SessionLoader.loadSnapshot(limit: limit) else { return [] }
        return Array(snapshot.rows.prefix(limit))
    }

    /// 更新会话
    static func updateSession(
        key: String,
        thinking: String?,
        verbose: String?) async throws
    {
        var params: [String: AnyHashable] = ["key": AnyHashable(key)]
        params["thinkingLevel"] = thinking.map(AnyHashable.init) ?? AnyHashable(NSNull())
        params["verboseLevel"] = verbose.map(AnyHashable.init) ?? AnyHashable(NSNull())
        _ = try await ControlChannel.shared.request(method: "sessions.patch", params: params)
    }

    // MARK: - 端口诊断

    typealias PortListener = PortGuardian.ReportListener
    typealias PortReport = PortGuardian.PortReport

    /// 检查网关端口
    static func checkGatewayPorts() async -> [PortReport] {
        let mode = CommandResolver.connectionSettings().mode
        return await PortGuardian.shared.diagnose(mode: mode)
    }

    /// 终止进程
    static func killProcess(_ pid: Int) async -> Result<Void, DebugActionError> {
        let primary = await ShellExecutor.run(command: ["kill", "-TERM", "\(pid)"], cwd: nil, env: nil, timeout: 2)
        if primary.ok { return .success(()) }
        let force = await ShellExecutor.run(command: ["kill", "-KILL", "\(pid)"], cwd: nil, env: nil, timeout: 2)
        if force.ok { return .success(()) }
        let detail = force.message ?? primary.message ?? "kill 失败"
        return .failure(.message(detail))
    }

    /// 在代码编辑器中打开会话存储
    @MainActor
    static func openSessionStoreInCode() {
        let path = SessionLoader.defaultStorePath
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["code", path]
        try? proc.run()
    }
}

/// 调试操作错误
enum DebugActionError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(text):
            text
        }
    }
}

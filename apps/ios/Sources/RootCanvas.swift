import SwiftUI
import UIKit

/// 根画布视图，作为应用的主界面容器
struct RootCanvas: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("canvas.debugStatusEnabled") private var canvasDebugStatusEnabled: Bool = false
    @State private var presentedSheet: PresentedSheet?
    @State private var voiceWakeToastText: String?
    @State private var toastDismissTask: Task<Void, Never>?

    /// 弹出表单类型枚举
    private enum PresentedSheet: Identifiable {
        case settings
        case chat

        var id: Int {
            switch self {
            case .settings: 0
            case .chat: 1
            }
        }
    }

    var body: some View {
        ZStack {
            CanvasContent(
                systemColorScheme: self.systemColorScheme,
                gatewayStatus: self.gatewayStatus,
                voiceWakeEnabled: self.voiceWakeEnabled,
                voiceWakeToastText: self.voiceWakeToastText,
                cameraHUDText: self.appModel.cameraHUDText,
                cameraHUDKind: self.appModel.cameraHUDKind,
                openChat: {
                    self.presentedSheet = .chat
                },
                openSettings: {
                    self.presentedSheet = .settings
                })
                .preferredColorScheme(.dark)

            if self.appModel.cameraFlashNonce != 0 {
                CameraFlashOverlay(nonce: self.appModel.cameraFlashNonce)
            }
        }
        .sheet(item: self.$presentedSheet) { sheet in
            switch sheet {
            case .settings:
                SettingsTab()
            case .chat:
                ChatSheet(
                    gateway: self.appModel.gatewaySession,
                    sessionKey: self.appModel.mainSessionKey,
                    userAccent: self.appModel.seamColor)
            }
        }
        .onAppear { self.updateIdleTimer() }
        .onChange(of: self.preventSleep) { _, _ in self.updateIdleTimer() }
        .onChange(of: self.scenePhase) { _, _ in self.updateIdleTimer() }
        .onAppear { self.updateCanvasDebugStatus() }
        .onChange(of: self.canvasDebugStatusEnabled) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.appModel.gatewayStatusText) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.appModel.gatewayServerName) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.appModel.gatewayRemoteAddress) { _, _ in self.updateCanvasDebugStatus() }
        .onChange(of: self.voiceWake.lastTriggeredCommand) { _, newValue in
            guard let newValue else { return }
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            self.toastDismissTask?.cancel()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self.voiceWakeToastText = trimmed
            }

            self.toastDismissTask = Task {
                try? await Task.sleep(nanoseconds: 2_300_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.25)) {
                        self.voiceWakeToastText = nil
                    }
                }
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            self.toastDismissTask?.cancel()
            self.toastDismissTask = nil
        }
    }

    /// 获取网关状态
    private var gatewayStatus: StatusPill.GatewayState {
        if self.appModel.gatewayServerName != nil { return .connected }

        let text = self.appModel.gatewayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.localizedCaseInsensitiveContains("connecting") ||
            text.localizedCaseInsensitiveContains("reconnecting")
        {
            return .connecting
        }

        if text.localizedCaseInsensitiveContains("error") {
            return .error
        }

        return .disconnected
    }

    /// 更新空闲计时器设置
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = (self.scenePhase == .active && self.preventSleep)
    }

    /// 更新画布调试状态
    private func updateCanvasDebugStatus() {
        self.appModel.screen.setDebugStatusEnabled(self.canvasDebugStatusEnabled)
        guard self.canvasDebugStatusEnabled else { return }
        let title = self.appModel.gatewayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = self.appModel.gatewayServerName ?? self.appModel.gatewayRemoteAddress
        self.appModel.screen.updateDebugStatus(title: title, subtitle: subtitle)
    }
}

/// 画布内容视图
private struct CanvasContent: View {
    @Environment(NodeAppModel.self) private var appModel
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false
    @AppStorage("talk.button.enabled") private var talkButtonEnabled: Bool = true
    var systemColorScheme: ColorScheme
    var gatewayStatus: StatusPill.GatewayState
    var voiceWakeEnabled: Bool
    var voiceWakeToastText: String?
    var cameraHUDText: String?
    var cameraHUDKind: NodeAppModel.CameraHUDKind?
    var openChat: () -> Void
    var openSettings: () -> Void

    /// 是否需要提亮按钮
    private var brightenButtons: Bool { self.systemColorScheme == .light }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScreenTab()

            VStack(spacing: 10) {
                OverlayButton(systemImage: "text.bubble.fill", brighten: self.brightenButtons) {
                    self.openChat()
                }
                .accessibilityLabel("聊天")

                if self.talkButtonEnabled {
                    // 语音模式位于侧边气泡中，避免在设置中被掩埋
                    OverlayButton(
                        systemImage: self.appModel.talkMode.isEnabled ? "waveform.circle.fill" : "waveform.circle",
                        brighten: self.brightenButtons,
                        tint: self.appModel.seamColor,
                        isActive: self.appModel.talkMode.isEnabled)
                    {
                        let next = !self.appModel.talkMode.isEnabled
                        self.talkEnabled = next
                        self.appModel.setTalkEnabled(next)
                    }
                    .accessibilityLabel("语音模式")
                }

                OverlayButton(systemImage: "gearshape.fill", brighten: self.brightenButtons) {
                    self.openSettings()
                }
                .accessibilityLabel("设置")
            }
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .overlay(alignment: .center) {
            if self.appModel.talkMode.isEnabled {
                TalkOrbOverlay()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            StatusPill(
                gateway: self.gatewayStatus,
                voiceWakeEnabled: self.voiceWakeEnabled,
                activity: self.statusActivity,
                brighten: self.brightenButtons,
                onTap: {
                    self.openSettings()
                })
                .padding(.leading, 10)
                .safeAreaPadding(.top, 10)
        }
        .overlay(alignment: .topLeading) {
            if let voiceWakeToastText, !voiceWakeToastText.isEmpty {
                VoiceWakeToast(
                    command: voiceWakeToastText,
                    brighten: self.brightenButtons)
                    .padding(.leading, 10)
                    .safeAreaPadding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    /// 获取状态活动信息
    private var statusActivity: StatusPill.Activity? {
        // 状态胶囊拥有瞬态活动状态，避免与连接指示器重叠
        if self.appModel.isBackgrounded {
            return StatusPill.Activity(
                title: "需要前台运行",
                systemImage: "exclamationmark.triangle.fill",
                tint: .orange)
        }

        let gatewayStatus = self.appModel.gatewayStatusText.trimmingCharacters(in: .whitespacesAndNewlines)
        let gatewayLower = gatewayStatus.lowercased()
        if gatewayLower.contains("repair") {
            return StatusPill.Activity(title: "正在修复…", systemImage: "wrench.and.screwdriver", tint: .orange)
        }
        if gatewayLower.contains("approval") || gatewayLower.contains("pairing") {
            return StatusPill.Activity(title: "等待批准", systemImage: "person.crop.circle.badge.clock")
        }
        // 避免在活动槽中重复显示主要网关状态（"正在连接…"）

        if self.appModel.screenRecordActive {
            return StatusPill.Activity(title: "正在录制屏幕…", systemImage: "record.circle.fill", tint: .red)
        }

        if let cameraHUDText, !cameraHUDText.isEmpty, let cameraHUDKind {
            let systemImage: String
            let tint: Color?
            switch cameraHUDKind {
            case .photo:
                systemImage = "camera.fill"
                tint = nil
            case .recording:
                systemImage = "video.fill"
                tint = .red
            case .success:
                systemImage = "checkmark.circle.fill"
                tint = .green
            case .error:
                systemImage = "exclamationmark.triangle.fill"
                tint = .red
            }
            return StatusPill.Activity(title: cameraHUDText, systemImage: systemImage, tint: tint)
        }

        if self.voiceWakeEnabled {
            let voiceStatus = self.appModel.voiceWake.statusText
            if voiceStatus.localizedCaseInsensitiveContains("microphone permission") {
                return StatusPill.Activity(title: "麦克风权限", systemImage: "mic.slash", tint: .orange)
            }
            if voiceStatus == "Paused" {
                let suffix = self.appModel.isBackgrounded ? " (后台)" : ""
                return StatusPill.Activity(title: "语音唤醒已暂停\(suffix)", systemImage: "pause.circle.fill")
            }
        }

        return nil
    }
}

/// 覆盖按钮视图
private struct OverlayButton: View {
    let systemImage: String
    let brighten: Bool
    var tint: Color?
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: self.action) {
            Image(systemName: self.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(self.isActive ? (self.tint ?? .primary) : .primary)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(self.brighten ? 0.26 : 0.18),
                                            .white.opacity(self.brighten ? 0.08 : 0.04),
                                            .clear,
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing))
                                .blendMode(.overlay)
                        }
                        .overlay {
                            if let tint {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                tint.opacity(self.isActive ? 0.22 : 0.14),
                                                tint.opacity(self.isActive ? 0.10 : 0.06),
                                                .clear,
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing))
                                    .blendMode(.overlay)
                            }
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    (self.tint ?? .white).opacity(self.isActive ? 0.34 : (self.brighten ? 0.24 : 0.18)),
                                    lineWidth: self.isActive ? 0.7 : 0.5)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                }
        }
        .buttonStyle(.plain)
    }
}

/// 相机闪光覆盖视图
private struct CameraFlashOverlay: View {
    var nonce: Int

    @State private var opacity: CGFloat = 0
    @State private var task: Task<Void, Never>?

    var body: some View {
        Color.white
            .opacity(self.opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: self.nonce) { _, _ in
                self.task?.cancel()
                self.task = Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.08)) {
                        self.opacity = 0.85
                    }
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    withAnimation(.easeOut(duration: 0.32)) {
                        self.opacity = 0
                    }
                }
            }
    }
}

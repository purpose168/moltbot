import SwiftUI

/// 根标签视图，包含屏幕、语音和设置三个标签
struct RootTabs: View {
    @Environment(NodeAppModel.self) private var appModel
    @Environment(VoiceWakeManager.self) private var voiceWake
    @AppStorage(VoiceWakePreferences.enabledKey) private var voiceWakeEnabled: Bool = false
    @State private var selectedTab: Int = 0
    @State private var voiceWakeToastText: String?
    @State private var toastDismissTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: self.$selectedTab) {
            ScreenTab()
                .tabItem { Label("屏幕", systemImage: "rectangle.and.hand.point.up.left") }
                .tag(0)

            VoiceTab()
                .tabItem { Label("语音", systemImage: "mic") }
                .tag(1)

            SettingsTab()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(2)
        }
        .overlay(alignment: .topLeading) {
            StatusPill(
                gateway: self.gatewayStatus,
                voiceWakeEnabled: self.voiceWakeEnabled,
                activity: self.statusActivity,
                onTap: { self.selectedTab = 2 })
                .padding(.leading, 10)
                .safeAreaPadding(.top, 10)
        }
        .overlay(alignment: .topLeading) {
            if let voiceWakeToastText, !voiceWakeToastText.isEmpty {
                VoiceWakeToast(command: voiceWakeToastText)
                    .padding(.leading, 10)
                    .safeAreaPadding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
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

    /// 获取状态活动信息
    private var statusActivity: StatusPill.Activity? {
        // 保持所有标签页顶部状态一致（相机 + 语音唤醒 + 配对状态）
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

        if let cameraHUDText = self.appModel.cameraHUDText,
           let cameraHUDKind = self.appModel.cameraHUDKind,
           !cameraHUDText.isEmpty
        {
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

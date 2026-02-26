import MoltbotKit
import SwiftUI
import Testing
import UIKit
@testable import Moltbot

/// SwiftUI 渲染冒烟测试套件
@Suite struct SwiftUIRenderSmokeTests {
    /// 将 SwiftUI 视图托管到 UIWindow 中
    /// - Parameter view: 要托管的 SwiftUI 视图
    /// - Returns: 包含视图的 UIWindow
    @MainActor private static func host(_ view: some View) -> UIWindow {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        window.rootViewController?.view.setNeedsLayout()
        window.rootViewController?.view.layoutIfNeeded()
        return window
    }

    /// 测试连接状态的状态药丸是否能正确构建视图层次结构
    @Test @MainActor func statusPillConnectingBuildsAViewHierarchy() {
        let root = StatusPill(gateway: .connecting, voiceWakeEnabled: true, brighten: true) {}
        _ = Self.host(root)
    }

    /// 测试断开连接状态的状态药丸是否能正确构建视图层次结构
    @Test @MainActor func statusPillDisconnectedBuildsAViewHierarchy() {
        let root = StatusPill(gateway: .disconnected, voiceWakeEnabled: false) {}
        _ = Self.host(root)
    }

    /// 测试设置标签页是否能正确构建视图层次结构
    @Test @MainActor func settingsTabBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let gatewayController = GatewayConnectionController(appModel: appModel, startDiscovery: false)

        let root = SettingsTab()
            .environment(appModel)
            .environment(appModel.voiceWake)
            .environment(gatewayController)

        _ = Self.host(root)
    }

    /// 测试根标签页是否能正确构建视图层次结构
    @Test @MainActor func rootTabsBuildAViewHierarchy() {
        let appModel = NodeAppModel()
        let gatewayController = GatewayConnectionController(appModel: appModel, startDiscovery: false)

        let root = RootTabs()
            .environment(appModel)
            .environment(appModel.voiceWake)
            .environment(gatewayController)

        _ = Self.host(root)
    }

    /// 测试语音标签页是否能正确构建视图层次结构
    @Test @MainActor func voiceTabBuildsAViewHierarchy() {
        let appModel = NodeAppModel()

        let root = VoiceTab()
            .environment(appModel)
            .environment(appModel.voiceWake)

        _ = Self.host(root)
    }

    /// 测试语音唤醒词设置视图是否能正确构建视图层次结构
    @Test @MainActor func voiceWakeWordsViewBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let root = NavigationStack { VoiceWakeWordsSettingsView() }
            .environment(appModel)
        _ = Self.host(root)
    }

    /// 测试聊天面板是否能正确构建视图层次结构
    @Test @MainActor func chatSheetBuildsAViewHierarchy() {
        let appModel = NodeAppModel()
        let gateway = GatewayNodeSession()
        let root = ChatSheet(gateway: gateway, sessionKey: "test")
            .environment(appModel)
            .environment(appModel.voiceWake)
        _ = Self.host(root)
    }

    /// 测试语音唤醒提示框是否能正确构建视图层次结构
    @Test @MainActor func voiceWakeToastBuildsAViewHierarchy() {
        let root = VoiceWakeToast(command: "moltbot: do something")
        _ = Self.host(root)
    }
}

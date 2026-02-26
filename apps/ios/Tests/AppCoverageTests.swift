import SwiftUI
import Testing
@testable import Moltbot

/// 应用覆盖率测试套件
/// 测试应用关键功能模块的基本行为
@Suite struct AppCoverageTests {
    /// 测试 NodeAppModel 是否正确更新背景状态
    /// 验证应用在不同场景阶段下的背景状态切换
    @Test @MainActor func nodeAppModelUpdatesBackgroundedState() {
        // 创建 NodeAppModel 实例
        let appModel = NodeAppModel()

        // 测试进入后台状态
        appModel.setScenePhase(.background)
        #expect(appModel.isBackgrounded == true)  // 验证背景状态为 true

        // 测试进入非活动状态
        appModel.setScenePhase(.inactive)
        #expect(appModel.isBackgrounded == false)  // 验证背景状态为 false

        // 测试进入活动状态
        appModel.setScenePhase(.active)
        #expect(appModel.isBackgrounded == false)  // 验证背景状态为 false
    }

    /// 测试语音唤醒功能在模拟器上的行为
    /// 验证语音唤醒在模拟器上会报告不支持
    @Test @MainActor func voiceWakeStartReportsUnsupportedOnSimulator() async {
        // 创建 VoiceWakeManager 实例
        let voiceWake = VoiceWakeManager()
        // 启用语音唤醒
        voiceWake.isEnabled = true

        // 启动语音唤醒
        await voiceWake.start()

        // 验证在模拟器上不会真正监听
        #expect(voiceWake.isListening == false)
        // 验证状态文本包含 "Simulator" 表示在模拟器上
        #expect(voiceWake.statusText.contains("Simulator"))

        // 停止语音唤醒
        voiceWake.stop()
        // 验证状态文本变为 "Off"
        #expect(voiceWake.statusText == "Off")
    }
}

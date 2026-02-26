import Foundation
import SwabbleKit
import Testing
@testable import Moltbot

/// 语音唤醒管理器状态测试
@Suite(.serialized) struct VoiceWakeManagerStateTests {
    /// 测试暂停和恢复循环是否正确更新状态
    @Test @MainActor func suspendAndResumeCycleUpdatesState() async {
        // 创建语音唤醒管理器实例
        let manager = VoiceWakeManager()
        // 启用语音唤醒并开始监听
        manager.isEnabled = true
        manager.isListening = true
        manager.statusText = "正在监听"

        // 暂停外部音频捕获
        let suspended = manager.suspendForExternalAudioCapture()
        // 验证是否成功暂停
        #expect(suspended == true)
        // 验证监听状态是否变为false
        #expect(manager.isListening == false)
        // 验证状态文本是否变为"已暂停"
        #expect(manager.statusText == "已暂停")

        // 恢复外部音频捕获
        manager.resumeAfterExternalAudioCapture(wasSuspended: true)
        // 等待一段时间以确保状态更新
        try? await Task.sleep(nanoseconds: 900_000_000)
        // 验证状态文本是否包含"语音唤醒"
        #expect(manager.statusText.contains("语音唤醒") == true)
    }

    /// 测试处理识别回调在错误时是否会重启
    @Test @MainActor func handleRecognitionCallbackRestartsOnError() async {
        // 创建语音唤醒管理器实例
        let manager = VoiceWakeManager()
        // 启用语音唤醒并开始监听
        manager.isEnabled = true
        manager.isListening = true

        // 模拟识别错误
        manager._test_handleRecognitionCallback(transcript: nil, segments: [], errorText: "错误")
        // 验证状态文本是否包含"识别器错误"
        #expect(manager.statusText.contains("识别器错误") == true)
        // 验证监听状态是否变为false
        #expect(manager.isListening == false)

        // 等待一段时间以确保状态更新
        try? await Task.sleep(nanoseconds: 900_000_000)
        // 验证状态文本是否包含"语音唤醒"
        #expect(manager.statusText.contains("语音唤醒") == true)
    }

    /// 测试处理识别回调是否正确分发命令
    @Test @MainActor func handleRecognitionCallbackDispatchesCommand() async {
        // 创建语音唤醒管理器实例
        let manager = VoiceWakeManager()
        // 设置触发词为"clawd"
        manager.triggerWords = ["clawd"]
        // 启用语音唤醒
        manager.isEnabled = true

        // 创建一个捕获框来捕获分发的命令
        actor CaptureBox {
            var value: String?
            func set(_ next: String) { self.value = next }
        }
        let capture = CaptureBox()
        // 配置管理器的回调
        manager.configure { cmd in
            await capture.set(cmd)
        }

        // 模拟识别结果
        let transcript = "clawd hello"
        let clawdRange = transcript.range(of: "clawd")!
        let helloRange = transcript.range(of: "hello")!
        let segments = [
            WakeWordSegment(text: "clawd", start: 0.0, duration: 0.2, range: clawdRange),
            WakeWordSegment(text: "hello", start: 0.8, duration: 0.2, range: helloRange),
        ]

        // 处理识别回调
        manager._test_handleRecognitionCallback(transcript: transcript, segments: segments, errorText: nil)
        // 验证最后触发的命令是否为"hello"
        #expect(manager.lastTriggeredCommand == "hello")
        // 验证状态文本是否为"已触发"
        #expect(manager.statusText == "已触发")

        // 等待一段时间以确保命令分发
        try? await Task.sleep(nanoseconds: 300_000_000)
        // 验证捕获的命令是否为"hello"
        #expect(await capture.value == "hello")
    }
}

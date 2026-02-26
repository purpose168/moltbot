import Foundation
import Testing
@testable import Moltbot

// 语音唤醒偏好设置测试套件
@Suite struct VoiceWakePreferencesTests {
    // 测试触发词清理功能:去除空白字符并删除空字符串
    @Test func sanitizeTriggerWordsTrimsAndDropsEmpty() {
        #expect(VoiceWakePreferences.sanitizeTriggerWords([" clawd ", "", " \nclaude\t"]) == ["clawd", "claude"])
    }

    // 测试触发词清理功能:当输入为空时回退到默认触发词
    @Test func sanitizeTriggerWordsFallsBackToDefaultsWhenEmpty() {
        #expect(VoiceWakePreferences.sanitizeTriggerWords(["", "  "]) == VoiceWakePreferences.defaultTriggerWords)
    }

    // 测试触发词清理功能:限制触发词的最大长度
    @Test func sanitizeTriggerWordsLimitsWordLength() {
        let long = String(repeating: "x", count: VoiceWakePreferences.maxWordLength + 5)
        let cleaned = VoiceWakePreferences.sanitizeTriggerWords(["ok", long])
        #expect(cleaned[1].count == VoiceWakePreferences.maxWordLength)
    }

    // 测试触发词清理功能:限制触发词的最大数量
    @Test func sanitizeTriggerWordsLimitsWordCount() {
        let words = (1...VoiceWakePreferences.maxWords + 3).map { "w\($0)" }
        let cleaned = VoiceWakePreferences.sanitizeTriggerWords(words)
        #expect(cleaned.count == VoiceWakePreferences.maxWords)
    }

    // 测试显示字符串功能:使用清理后的触发词
    @Test func displayStringUsesSanitizedWords() {
        #expect(VoiceWakePreferences.displayString(for: ["", " "]) == "clawd, claude")
    }

    // 测试触发词的加载和保存功能:验证往返数据一致性
    @Test func loadAndSaveTriggerWordsRoundTrip() {
        let suiteName = "VoiceWakePreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        #expect(VoiceWakePreferences.loadTriggerWords(defaults: defaults) == VoiceWakePreferences.defaultTriggerWords)
        VoiceWakePreferences.saveTriggerWords(["computer"], defaults: defaults)
        #expect(VoiceWakePreferences.loadTriggerWords(defaults: defaults) == ["computer"])
    }
}

import Foundation
import SwabbleKit
import Testing
@testable import Moltbot

/// 测试 VoiceWakeManager 的命令提取功能
@Suite struct VoiceWakeManagerExtractCommandTests {
    /// 测试当未找到触发词时，extractCommand 应返回 nil
    @Test func extractCommandReturnsNilWhenNoTriggerFound() {
        let transcript = "hello world"
        let segments = makeSegments(
            transcript: transcript,
            words: [("hello", 0.0, 0.1), ("world", 0.2, 0.1)])
        #expect(VoiceWakeManager.extractCommand(from: transcript, segments: segments, triggers: ["clawd"]) == nil)
    }

    /// 测试 extractCommand 会修剪触发词和结果中的空白字符
    @Test func extractCommandTrimsTokensAndResult() {
        let transcript = "hey clawd do thing"
        let segments = makeSegments(
            transcript: transcript,
            words: [
                ("hey", 0.0, 0.1),
                ("clawd", 0.2, 0.1),
                ("do", 0.9, 0.1),
                ("thing", 1.1, 0.1),
            ])
        let cmd = VoiceWakeManager.extractCommand(
            from: transcript,
            segments: segments,
            triggers: ["  clawd  "],
            minPostTriggerGap: 0.3)
        #expect(cmd == "do thing")
    }

    /// 测试当触发词后的间隔太短时，extractCommand 应返回 nil
    @Test func extractCommandReturnsNilWhenGapTooShort() {
        let transcript = "hey clawd do thing"
        let segments = makeSegments(
            transcript: transcript,
            words: [
                ("hey", 0.0, 0.1),
                ("clawd", 0.2, 0.1),
                ("do", 0.35, 0.1),
                ("thing", 0.5, 0.1),
            ])
        let cmd = VoiceWakeManager.extractCommand(
            from: transcript,
            segments: segments,
            triggers: ["clawd"],
            minPostTriggerGap: 0.3)
        #expect(cmd == nil)
    }

    /// 测试当触发词后没有内容时，extractCommand 应返回 nil
    @Test func extractCommandReturnsNilWhenNothingAfterTrigger() {
        let transcript = "hey clawd"
        let segments = makeSegments(
            transcript: transcript,
            words: [("hey", 0.0, 0.1), ("clawd", 0.2, 0.1)])
        #expect(VoiceWakeManager.extractCommand(from: transcript, segments: segments, triggers: ["clawd"]) == nil)
    }

    /// 测试 extractCommand 会忽略空的触发词
    @Test func extractCommandIgnoresEmptyTriggers() {
        let transcript = "hey clawd do thing"
        let segments = makeSegments(
            transcript: transcript,
            words: [
                ("hey", 0.0, 0.1),
                ("clawd", 0.2, 0.1),
                ("do", 0.9, 0.1),
                ("thing", 1.1, 0.1),
            ])
        let cmd = VoiceWakeManager.extractCommand(
            from: transcript,
            segments: segments,
            triggers: ["", "   ", "clawd"],
            minPostTriggerGap: 0.3)
        #expect(cmd == "do thing")
    }
}

/// 辅助函数：根据提供的转录文本和单词信息创建唤醒词分段
/// - Parameters:
///   - transcript: 完整的转录文本
///   - words: 单词数组，每个元素包含单词文本、开始时间和持续时间
/// - Returns: 唤醒词分段数组
private func makeSegments(
    transcript: String,
    words: [(String, TimeInterval, TimeInterval)])
-> [WakeWordSegment] {
    var searchStart = transcript.startIndex
    var output: [WakeWordSegment] = []
    for (word, start, duration) in words {
        let range = transcript.range(of: word, range: searchStart..<transcript.endIndex)
        output.append(WakeWordSegment(text: word, start: start, duration: duration, range: range))
        if let range { searchStart = range.upperBound }
    }
    return output
}

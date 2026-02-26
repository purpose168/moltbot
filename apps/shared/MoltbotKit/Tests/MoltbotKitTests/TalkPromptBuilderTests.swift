import XCTest
@testable import MoltbotKit

/// 测试 TalkPromptBuilder 类的功能
final class TalkPromptBuilderTests: XCTestCase {
    /// 测试构建的提示是否包含对话记录
    func testBuildIncludesTranscript() {
        let prompt = TalkPromptBuilder.build(transcript: "你好", interruptedAtSeconds: nil)
        XCTAssertTrue(prompt.contains("对话模式已激活"))
        XCTAssertTrue(prompt.hasSuffix("\n\n你好"))
    }

    /// 测试当提供中断时间时，构建的提示是否包含中断行
    func testBuildIncludesInterruptionLineWhenProvided() {
        let prompt = TalkPromptBuilder.build(transcript: "嗨", interruptedAtSeconds: 1.234)
        XCTAssertTrue(prompt.contains("助手语音在 1.2s 处被中断"))
    }
}

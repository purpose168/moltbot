import Testing
@testable import MoltbotChatUI

/// AssistantTextParser的测试套件
@Suite struct AssistantTextParserTests {
    /// 测试是否能正确分割<think>和<final>标签的内容
    @Test func splitsThinkAndFinalSegments() {
        let segments = AssistantTextParser.segments(
            from: "<think>internal</think>\n\n<final>Hello there</final>")

        #expect(segments.count == 2)                          // 应该有2个段落
        #expect(segments[0].kind == .thinking)                 // 第一个段落类型为思考
        #expect(segments[0].text == "internal")               // 第一个段落文本为"internal"
        #expect(segments[1].kind == .response)                 // 第二个段落类型为回应
        #expect(segments[1].text == "Hello there")            // 第二个段落文本为"Hello there"
    }

    /// 测试如何处理没有标签的纯文本
    @Test func keepsTextWithoutTags() {
        let segments = AssistantTextParser.segments(from: "Just text.")

        #expect(segments.count == 1)                          // 应该有1个段落
        #expect(segments[0].kind == .response)                 // 段落类型为回应
        #expect(segments[0].text == "Just text.")             // 段落文本为"Just text."
    }

    /// 测试是否忽略类似<thinking>这样的非标准标签
    @Test func ignoresThinkingLikeTags() {
        let raw = "<thinking>example</thinking>\nKeep this."
        let segments = AssistantTextParser.segments(from: raw)

        #expect(segments.count == 1)                          // 应该有1个段落
        #expect(segments[0].kind == .response)                 // 段落类型为回应
        #expect(segments[0].text == raw.trimmingCharacters(in: .whitespacesAndNewlines))  // 段落文本为原始文本去除空白
    }

    /// 测试是否能正确处理空的<think>标签内容
    @Test func dropsEmptyTaggedContent() {
        let segments = AssistantTextParser.segments(from: "<think></think>")
        #expect(segments.isEmpty)                              // 空标签内容应该被丢弃，返回空数组
    }
}

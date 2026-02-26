import MoltbotKit
import Testing

/// Canvas A2UI 相关功能的测试套件
@Suite struct CanvasA2UITests {
    /// 测试命令字符串的稳定性，确保命令原始值不会意外更改
    @Test func commandStringsAreStable() {
        #expect(MoltbotCanvasA2UICommand.push.rawValue == "canvas.a2ui.push")        // 测试推送命令的原始值
        #expect(MoltbotCanvasA2UICommand.pushJSONL.rawValue == "canvas.a2ui.pushJSONL") // 测试推送JSONL命令的原始值
        #expect(MoltbotCanvasA2UICommand.reset.rawValue == "canvas.a2ui.reset")      // 测试重置命令的原始值
    }

    /// 测试 JSONL 格式的解码和验证功能（V0.8 版本）
    @Test func jsonlDecodesAndValidatesV0_8() throws {
        // 定义测试用的 JSONL 字符串，包含各种消息类型
        let jsonl = """
        {"beginRendering":{"surfaceId":"main","timestamp":1}}
        {"surfaceUpdate":{"surfaceId":"main","ops":[]}}
        {"dataModelUpdate":{"dataModel":{"title":"Hello"}}}
        {"deleteSurface":{"surfaceId":"main"}}
        """

        // 尝试从 JSONL 字符串解码消息
        let messages = try MoltbotCanvasA2UIJSONL.decodeMessagesFromJSONL(jsonl)
        #expect(messages.count == 4) // 验证是否成功解码了4条消息
    }

    /// 测试 JSONL 解析器是否正确拒绝 V0.9 版本的 createSurface 消息
    @Test func jsonlRejectsV0_9CreateSurface() {
        // 定义包含 V0.9 版本 createSurface 消息的 JSONL 字符串
        let jsonl = """
        {"createSurface":{"surfaceId":"main"}}
        """

        // 验证解析器是否会抛出错误
        #expect(throws: Error.self) {
            _ = try MoltbotCanvasA2UIJSONL.decodeMessagesFromJSONL(jsonl)
        }
    }

    /// 测试 JSONL 解析器是否正确拒绝未知形状的消息
    @Test func jsonlRejectsUnknownShape() {
        // 定义包含未知形状消息的 JSONL 字符串
        let jsonl = """
        {"wat":{"nope":1}}
        """

        // 验证解析器是否会抛出错误
        #expect(throws: Error.self) {
            _ = try MoltbotCanvasA2UIJSONL.decodeMessagesFromJSONL(jsonl)
        }
    }
}

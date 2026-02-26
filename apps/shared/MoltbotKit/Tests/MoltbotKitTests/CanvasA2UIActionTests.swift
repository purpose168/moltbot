import MoltbotKit
import Foundation
import Testing

/// 测试 Canvas A2UI 动作相关功能
@Suite struct CanvasA2UIActionTests {
    /// 测试 sanitizeTagValue 方法的稳定性
    @Test func sanitizeTagValueIsStable() {
        #expect(MoltbotCanvasA2UIAction.sanitizeTagValue("Hello World!") == "Hello_World_")
        #expect(MoltbotCanvasA2UIAction.sanitizeTagValue("  ") == "-")
        #expect(MoltbotCanvasA2UIAction.sanitizeTagValue("macOS 26.2") == "macOS_26.2")
    }

    /// 测试 extractActionName 方法是否接受 name 或 action 参数
    @Test func extractActionNameAcceptsNameOrAction() {
        #expect(MoltbotCanvasA2UIAction.extractActionName(["name": "Hello"]) == "Hello")
        #expect(MoltbotCanvasA2UIAction.extractActionName(["action": "Wave"]) == "Wave")
        #expect(MoltbotCanvasA2UIAction.extractActionName(["name": "  ", "action": "Fallback"]) == "Fallback")
        #expect(MoltbotCanvasA2UIAction.extractActionName(["action": " "]) == nil)
    }

    /// 测试 formatAgentMessage 方法是否生成高效且明确的消息
    @Test func formatAgentMessageIsTokenEfficientAndUnambiguous() {
        let messageContext = MoltbotCanvasA2UIAction.AgentMessageContext(
            actionName: "Get Weather",
            session: .init(key: "main", surfaceId: "main"),
            component: .init(id: "btnWeather", host: "Peter’s iPad", instanceId: "ipad16,6"),
            contextJSON: "{\"city\":\"Vienna\"}")
        let msg = MoltbotCanvasA2UIAction.formatAgentMessage(messageContext)

        #expect(msg.contains("CANVAS_A2UI "))
        #expect(msg.contains("action=Get_Weather"))
        #expect(msg.contains("session=main"))
        #expect(msg.contains("surface=main"))
        #expect(msg.contains("component=btnWeather"))
        #expect(msg.contains("host=Peter_s_iPad"))
        #expect(msg.contains("instance=ipad16_6 ctx={\"city\":\"Vienna\"}"))
        #expect(msg.hasSuffix(" default=update_canvas"))
    }
}

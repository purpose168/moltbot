import Foundation
import Testing
@testable import Moltbot

/// 语音唤醒网关同步测试
@Suite struct VoiceWakeGatewaySyncTests {
    /// 测试从JSON解码网关触发器时是否正确清理数据
    @Test func decodeGatewayTriggersFromJSONSanitizes() {
        // 包含空白和空字符串的测试数据
        let payload = #"{"triggers":[" clawd  ","", "computer"]}"#
        let triggers = VoiceWakePreferences.decodeGatewayTriggers(from: payload)
        // 期望结果：空白被清理，空字符串被移除
        #expect(triggers == ["clawd", "computer"])
    }

    /// 测试从JSON解码网关触发器时空数据的回退行为
    @Test func decodeGatewayTriggersFromJSONFallsBackWhenEmpty() {
        // 只包含空白字符串的测试数据
        let payload = #"{"triggers":["  ",""]}"#
        let triggers = VoiceWakePreferences.decodeGatewayTriggers(from: payload)
        // 期望结果：返回默认触发器词汇
        #expect(triggers == VoiceWakePreferences.defaultTriggerWords)
    }

    /// 测试从无效JSON解码网关触发器时是否返回nil
    @Test func decodeGatewayTriggersFromInvalidJSONReturnsNil() {
        // 无效的JSON字符串
        let triggers = VoiceWakePreferences.decodeGatewayTriggers(from: "not json")
        // 期望结果：返回nil
        #expect(triggers == nil)
    }
}

import MoltbotKit
import Foundation
import Testing

/// 深度链接解析器测试套件
@Suite struct DeepLinkParserTests {
    /// 测试解析器拒绝未知主机
    @Test func parseRejectsUnknownHost() {
        let url = URL(string: "moltbot://nope?message=hi")!
        #expect(DeepLinkParser.parse(url) == nil)
    }

    /// 测试主机名大小写不敏感
    @Test func parseHostIsCaseInsensitive() {
        let url = URL(string: "moltbot://AGENT?message=Hello")!
        #expect(DeepLinkParser.parse(url) == .agent(.init(
            message: "Hello",
            sessionKey: nil,
            thinking: nil,
            deliver: false,
            to: nil,
            channel: nil,
            timeoutSeconds: nil,
            key: nil)))
    }

    /// 测试解析器拒绝非moltbot协议
    @Test func parseRejectsNonMoltbotScheme() {
        let url = URL(string: "https://example.com/agent?message=hi")!
        #expect(DeepLinkParser.parse(url) == nil)
    }

    /// 测试解析器拒绝空消息
    @Test func parseRejectsEmptyMessage() {
        let url = URL(string: "moltbot://agent?message=%20%20%0A")!
        #expect(DeepLinkParser.parse(url) == nil)
    }

    /// 测试解析包含常见字段的代理链接
    @Test func parseAgentLinkParsesCommonFields() {
        let url =
            URL(string: "moltbot://agent?message=Hello&deliver=1&sessionKey=node-test&thinking=low&timeoutSeconds=30")!
        #expect(
            DeepLinkParser.parse(url) == .agent(
                .init(
                    message: "Hello",
                    sessionKey: "node-test",
                    thinking: "low",
                    deliver: true,
                    to: nil,
                    channel: nil,
                    timeoutSeconds: 30,
                    key: nil)))
    }

    /// 测试解析包含目标路由字段的代理链接
    @Test func parseAgentLinkParsesTargetRoutingFields() {
        let url =
            URL(
                string: "moltbot://agent?message=Hello%20World&deliver=1&to=%2B15551234567&channel=whatsapp&key=secret")!
        #expect(
            DeepLinkParser.parse(url) == .agent(
                .init(
                    message: "Hello World",
                    sessionKey: nil,
                    thinking: nil,
                    deliver: true,
                    to: "+15551234567",
                    channel: "whatsapp",
                    timeoutSeconds: nil,
                    key: "secret")))
    }

    /// 测试解析器拒绝负超时秒数
    @Test func parseRejectsNegativeTimeoutSeconds() {
        let url = URL(string: "moltbot://agent?message=Hello&timeoutSeconds=-1")!
        #expect(DeepLinkParser.parse(url) == .agent(.init(
            message: "Hello",
            sessionKey: nil,
            thinking: nil,
            deliver: false,
            to: nil,
            channel: nil,
            timeoutSeconds: nil,
            key: nil)))
    }
}

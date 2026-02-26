import MoltbotKit
import Testing
@testable import Moltbot

/// iOS 网关聊天传输测试套件
@Suite struct IOSGatewayChatTransportTests {
    /// 测试当网关未连接时请求是否会快速失败
    @Test func requestsFailFastWhenGatewayNotConnected() async {
        // 创建网关节点会话
        let gateway = GatewayNodeSession()
        // 创建 iOS 网关聊天传输实例
        let transport = IOSGatewayChatTransport(gateway: gateway)

        // 测试 requestHistory 方法在网关未连接时是否会抛出异常
        do {
            _ = try await transport.requestHistory(sessionKey: "node-test")
            Issue.record("期望 requestHistory 在网关未连接时抛出异常")
        } catch {}

        // 测试 sendMessage 方法在网关未连接时是否会抛出异常
        do {
            _ = try await transport.sendMessage(
                sessionKey: "node-test",
                message: "hello",
                thinking: "low",
                idempotencyKey: "idempotency",
                attachments: [])
            Issue.record("期望 sendMessage 在网关未连接时抛出异常")
        } catch {}

        // 测试 requestHealth 方法在网关未连接时是否会抛出异常
        do {
            _ = try await transport.requestHealth(timeoutMs: 250)
            Issue.record("期望 requestHealth 在网关未连接时抛出异常")
        } catch {}
    }
}

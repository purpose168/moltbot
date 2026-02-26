import Foundation
import Testing
@testable import MoltbotKit
import MoltbotProtocol

/// GatewayNodeSession 测试类
/// 测试 GatewayNodeSession 的 invokeWithTimeout 方法的各种场景
struct GatewayNodeSessionTests {
    /// 测试在超时时间之前返回底层响应
    /// 验证当调用在超时前完成时，返回正确的响应结果
    @Test
    func invokeWithTimeoutReturnsUnderlyingResponseBeforeTimeout() async {
        // 创建测试请求
        let request = BridgeInvokeRequest(id: "1", command: "x", paramsJSON: nil)
        // 调用带超时的方法
        let response = await GatewayNodeSession.invokeWithTimeout(
            request: request,
            timeoutMs: 50,  // 设置50毫秒超时
            onInvoke: { req in
                // 验证请求ID正确
                #expect(req.id == "1")
                // 返回成功响应
                return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: "{}", error: nil)
            }
        )

        // 验证响应结果
        #expect(response.ok == true)         // 响应成功
        #expect(response.error == nil)       // 无错误
        #expect(response.payloadJSON == "{}") // 负载正确
    }

    /// 测试超时返回错误
    /// 验证当调用超过超时时间时，返回超时错误
    @Test
    func invokeWithTimeoutReturnsTimeoutError() async {
        // 创建测试请求
        let request = BridgeInvokeRequest(id: "abc", command: "x", paramsJSON: nil)
        // 调用带超时的方法
        let response = await GatewayNodeSession.invokeWithTimeout(
            request: request,
            timeoutMs: 10,  // 设置10毫秒超时
            onInvoke: { _ in
                // 模拟长时间执行（200毫秒）
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                // 尝试返回成功响应（但应该被超时覆盖）
                return BridgeInvokeResponse(id: "abc", ok: true, payloadJSON: "{}", error: nil)
            }
        )

        // 验证超时错误
        #expect(response.ok == false)                  // 响应失败
        #expect(response.error?.code == .unavailable)  // 错误代码为不可用
        #expect(response.error?.message.contains("timed out") == true) // 错误消息包含超时信息
    }

    /// 测试超时设置为0时禁用超时功能
    /// 验证当timeoutMs设置为0时，无论执行多长时间都不会超时
    @Test
    func invokeWithTimeoutZeroDisablesTimeout() async {
        // 创建测试请求
        let request = BridgeInvokeRequest(id: "1", command: "x", paramsJSON: nil)
        // 调用带超时的方法，设置超时为0
        let response = await GatewayNodeSession.invokeWithTimeout(
            request: request,
            timeoutMs: 0,  // 设置超时为0（禁用超时）
            onInvoke: { req in
                // 模拟短暂延迟（5毫秒）
                try? await Task.sleep(nanoseconds: 5_000_000)
                // 返回成功响应
                return BridgeInvokeResponse(id: req.id, ok: true, payloadJSON: nil, error: nil)
            }
        )

        // 验证响应结果
        #expect(response.ok == true)         // 响应成功
        #expect(response.error == nil)       // 无错误
    }
}

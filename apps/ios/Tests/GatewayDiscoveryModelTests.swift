import Testing
@testable import Moltbot

/// 网关发现模型测试
@Suite(.serialized) struct GatewayDiscoveryModelTests {
    /// 测试调试日志是否能捕获生命周期事件并正确重置
    @Test @MainActor func debugLoggingCapturesLifecycleAndResets() {
        // 创建网关发现模型实例
        let model = GatewayDiscoveryModel()

        // 验证初始状态：调试日志为空
        #expect(model.debugLog.isEmpty)
        // 验证初始状态文本为"空闲"
        #expect(model.statusText == "Idle")

        // 启用调试日志
        model.setDebugLoggingEnabled(true)
        // 验证调试日志至少有2条记录
        #expect(model.debugLog.count >= 2)

        // 停止网关发现
        model.stop()
        // 验证状态文本为"已停止"
        #expect(model.statusText == "Stopped")
        // 验证网关列表为空
        #expect(model.gateways.isEmpty)
        // 验证调试日志至少有3条记录
        #expect(model.debugLog.count >= 3)

        // 禁用调试日志
        model.setDebugLoggingEnabled(false)
        // 验证调试日志为空
        #expect(model.debugLog.isEmpty)
    }
}

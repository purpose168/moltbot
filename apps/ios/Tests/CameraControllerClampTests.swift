import Testing
@testable import Moltbot

/// 测试 CameraController 类中的值限制方法
@Suite struct CameraControllerClampTests {
    /// 测试 clampQuality 方法的默认值和边界情况
    @Test func clampQualityDefaultsAndBounds() {
        // 测试默认值（nil 时应返回 0.9）
        #expect(CameraController.clampQuality(nil) == 0.9)
        // 测试最小值边界（小于 0.05 时应返回 0.05）
        #expect(CameraController.clampQuality(0.0) == 0.05)
        #expect(CameraController.clampQuality(0.049) == 0.05)
        #expect(CameraController.clampQuality(0.05) == 0.05)
        // 测试中间值（应保持不变）
        #expect(CameraController.clampQuality(0.5) == 0.5)
        // 测试最大值边界（大于等于 1.0 时应返回 1.0）
        #expect(CameraController.clampQuality(1.0) == 1.0)
        #expect(CameraController.clampQuality(1.1) == 1.0)
    }

    /// 测试 clampDurationMs 方法的默认值和边界情况
    @Test func clampDurationDefaultsAndBounds() {
        // 测试默认值（nil 时应返回 3000）
        #expect(CameraController.clampDurationMs(nil) == 3000)
        // 测试最小值边界（小于 250 时应返回 250）
        #expect(CameraController.clampDurationMs(0) == 250)
        #expect(CameraController.clampDurationMs(249) == 250)
        #expect(CameraController.clampDurationMs(250) == 250)
        // 测试中间值（应保持不变）
        #expect(CameraController.clampDurationMs(1000) == 1000)
        // 测试最大值边界（大于等于 60000 时应返回 60000）
        #expect(CameraController.clampDurationMs(60000) == 60000)
        #expect(CameraController.clampDurationMs(60001) == 60000)
    }
}

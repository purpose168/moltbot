import Testing
@testable import Moltbot

/// 屏幕录制服务测试套件
@Suite(.serialized) struct ScreenRecordServiceTests {
    /// 测试时间和帧率的边界值处理
    @Test func clampDefaultsAndBounds() {
        // 测试时间边界值 - 无值时应返回默认值 10000
        #expect(ScreenRecordService._test_clampDurationMs(nil) == 10000)
        // 测试时间边界值 - 最小值应被限制为 250
        #expect(ScreenRecordService._test_clampDurationMs(0) == 250)
        // 测试时间边界值 - 最大值应被限制为 60000
        #expect(ScreenRecordService._test_clampDurationMs(60001) == 60000)

        // 测试帧率边界值 - 无值时应返回默认值 10
        #expect(ScreenRecordService._test_clampFps(nil) == 10)
        // 测试帧率边界值 - 最小值应被限制为 1
        #expect(ScreenRecordService._test_clampFps(0) == 1)
        // 测试帧率边界值 - 最大值应被限制为 30
        #expect(ScreenRecordService._test_clampFps(120) == 30)
        // 测试帧率边界值 - 无穷大时应返回默认值 10
        #expect(ScreenRecordService._test_clampFps(.infinity) == 10)
    }

    /// 测试录制时拒绝无效的屏幕索引
    @Test @MainActor func recordRejectsInvalidScreenIndex() async {
        let recorder = ScreenRecordService()
        do {
            _ = try await recorder.record(
                screenIndex: 1,
                durationMs: 250,
                fps: 5,
                includeAudio: false,
                outPath: nil)
            // 预期无效屏幕索引应抛出错误
            Issue.record("预期无效屏幕索引应抛出错误")
        } catch let error as ScreenRecordService.ScreenRecordError {
            // 验证错误信息包含"无效屏幕索引"
            #expect(error.localizedDescription.contains("无效屏幕索引") == true)
        } catch {
            // 捕获到意外的错误类型
            Issue.record("意外的错误类型: \(error)")
        }
    }
}

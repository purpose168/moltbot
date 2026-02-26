import Testing
@testable import Moltbot

/// 测试相机控制器错误描述的稳定性
@Suite struct CameraControllerErrorTests {
    /// 测试各种相机错误类型的错误描述是否稳定
    @Test func errorDescriptionsAreStable() {
        // 测试相机不可用错误的描述
        #expect(CameraController.CameraError.cameraUnavailable.errorDescription == "相机不可用")
        // 测试麦克风不可用错误的描述
        #expect(CameraController.CameraError.microphoneUnavailable.errorDescription == "麦克风不可用")
        // 测试相机权限被拒绝错误的描述
        #expect(CameraController.CameraError.permissionDenied(kind: "Camera")
            .errorDescription == "相机权限被拒绝")
        // 测试无效参数错误的描述
        #expect(CameraController.CameraError.invalidParams("bad").errorDescription == "bad")
        // 测试捕获失败错误的描述
        #expect(CameraController.CameraError.captureFailed("nope").errorDescription == "nope")
        // 测试导出失败错误的描述
        #expect(CameraController.CameraError.exportFailed("export").errorDescription == "export")
    }
}

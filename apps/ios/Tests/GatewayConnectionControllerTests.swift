import MoltbotKit
import Foundation
import Testing
import UIKit
@testable import Moltbot

/// 临时修改并在操作后恢复 UserDefaults 的辅助函数
/// - Parameters:
///   - updates: 要更新的键值对，值为 nil 表示移除该键
///   - body: 要执行的操作闭包
/// - Returns: 闭包的返回值
private func withUserDefaults<T>(_ updates: [String: Any?], _ body: () throws -> T) rethrows -> T {
    let defaults = UserDefaults.standard
    var snapshot: [String: Any?] = [:]
    // 保存当前值的快照
    for key in updates.keys {
        snapshot[key] = defaults.object(forKey: key)
    }
    // 应用更新
    for (key, value) in updates {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    // 延迟恢复原始值
    defer {
        for (key, value) in snapshot {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
    return try body()
}

/// GatewayConnectionController 的测试套件
@Suite(.serialized) struct GatewayConnectionControllerTests {
    /// 测试当缺少显示名称时是否会设置默认值
    @Test @MainActor func resolvedDisplayNameSetsDefaultWhenMissing() {
        let defaults = UserDefaults.standard
        let displayKey = "node.displayName"

        withUserDefaults([displayKey: nil, "node.instanceId": "ios-test"]) {
            let appModel = NodeAppModel()
            let controller = GatewayConnectionController(appModel: appModel, startDiscovery: false)

            let resolved = controller._test_resolvedDisplayName(defaults: defaults)
            #expect(!resolved.isEmpty)  // 期望解析出的显示名称不为空
            #expect(defaults.string(forKey: displayKey) == resolved)  // 期望 UserDefaults 中的值被更新为解析出的名称
        }
    }

    /// 测试当前能力是否反映了各种开关状态
    @Test @MainActor func currentCapsReflectToggles() {
        withUserDefaults([
            "node.instanceId": "ios-test",
            "node.displayName": "Test Node",
            "camera.enabled": true,
            "location.enabledMode": MoltbotLocationMode.always.rawValue,
            VoiceWakePreferences.enabledKey: true,
        ]) {
            let appModel = NodeAppModel()
            let controller = GatewayConnectionController(appModel: appModel, startDiscovery: false)
            let caps = Set(controller._test_currentCaps())

            #expect(caps.contains(MoltbotCapability.canvas.rawValue))  // 期望包含画布能力
            #expect(caps.contains(MoltbotCapability.screen.rawValue))  // 期望包含屏幕能力
            #expect(caps.contains(MoltbotCapability.camera.rawValue))  // 期望包含相机能力
            #expect(caps.contains(MoltbotCapability.location.rawValue))  // 期望包含位置能力
            #expect(caps.contains(MoltbotCapability.voiceWake.rawValue))  // 期望包含语音唤醒能力
        }
    }

    /// 测试当位置启用时当前命令是否包含位置命令
    @Test @MainActor func currentCommandsIncludeLocationWhenEnabled() {
        withUserDefaults([
            "node.instanceId": "ios-test",
            "location.enabledMode": MoltbotLocationMode.whileUsing.rawValue,
        ]) {
            let appModel = NodeAppModel()
            let controller = GatewayConnectionController(appModel: appModel, startDiscovery: false)
            let commands = Set(controller._test_currentCommands())

            #expect(commands.contains(MoltbotLocationCommand.get.rawValue))  // 期望包含位置获取命令
        }
    }
}

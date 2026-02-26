import MoltbotKit
import Foundation
import Testing

/// 测试 ToolDisplayRegistry 类的功能
/// 该类负责从配置文件中加载和解析工具显示信息
@Suite struct ToolDisplayRegistryTests {
    /// 测试是否能从资源包中加载工具显示配置文件
    /// 验证 tool-display.json 文件是否存在于资源包中
    @Test func loadsToolDisplayConfigFromBundle() {
        // 尝试从 MoltbotKitResources.bundle 中获取 tool-display.json 文件的 URL
        let url = MoltbotKitResources.bundle.url(forResource: "tool-display", withExtension: "json")
        // 验证 URL 不为 nil，确保配置文件存在
        #expect(url != nil)
    }

    /// 测试是否能从配置中解析已知工具的显示信息
    /// 验证 bash 工具的显示信息是否正确
    @Test func resolvesKnownToolFromConfig() {
        // 解析名称为 "bash" 的工具显示信息，无参数
        let summary = ToolDisplayRegistry.resolve(name: "bash", args: nil)
        // 验证工具的 emoji 是否为 🛠️
        #expect(summary.emoji == "🛠️")
        // 验证工具的标题是否为 "Bash"
        #expect(summary.title == "Bash")
    }
}

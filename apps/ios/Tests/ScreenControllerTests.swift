import Testing
import WebKit
@testable import Moltbot

/// ScreenController 测试套件
@Suite struct ScreenControllerTests {
    /// 测试画布模式是否正确配置 WebView 以支持触摸操作
    @Test @MainActor func canvasModeConfiguresWebViewForTouch() {
        let screen = ScreenController()

        // 验证 WebView 的不透明度和背景色设置
        #expect(screen.webView.isOpaque == true)
        #expect(screen.webView.backgroundColor == .black)

        // 验证滚动视图的配置
        let scrollView = screen.webView.scrollView
        #expect(scrollView.backgroundColor == .black)
        #expect(scrollView.contentInsetAdjustmentBehavior == .never)
        #expect(scrollView.isScrollEnabled == false)
        #expect(scrollView.bounces == false)
    }

    /// 测试导航到网页时是否启用滚动功能
    @Test @MainActor func navigateEnablesScrollForWebPages() {
        let screen = ScreenController()
        screen.navigate(to: "https://example.com")

        // 验证滚动视图的滚动和回弹功能是否启用
        let scrollView = screen.webView.scrollView
        #expect(scrollView.isScrollEnabled == true)
        #expect(scrollView.bounces == true)
    }

    /// 测试导航到 "/" 是否显示默认画布
    @Test @MainActor func navigateSlashShowsDefaultCanvas() {
        let screen = ScreenController()
        screen.navigate(to: "/")

        // 验证 URL 字符串是否为空
        #expect(screen.urlString.isEmpty)
    }

    /// 测试 eval 方法是否能正确执行 JavaScript 代码
    @Test @MainActor func evalExecutesJavaScript() async throws {
        let screen = ScreenController()
        let deadline = ContinuousClock().now.advanced(by: .seconds(3))

        while true {
            do {
                // 执行 JavaScript 代码 "1+1" 并验证结果
                let result = try await screen.eval(javaScript: "1+1")
                #expect(result == "2")
                return
            } catch {
                // 如果超过截止时间则抛出错误
                if ContinuousClock().now >= deadline {
                    throw error
                }
                // 等待 100 毫秒后重试
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    /// 测试本地网络画布 URL 是否被允许
    @Test @MainActor func localNetworkCanvasURLsAreAllowed() {
        let screen = ScreenController()
        // 测试各种本地网络 URL
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://localhost:18789/")!) == true)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://clawd.local:18789/")!) == true)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://peters-mac-studio-1:18789/")!) == true)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "https://peters-mac-studio-1.ts.net:18789/")!) == true)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://192.168.0.10:18789/")!) == true)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://10.0.0.10:18789/")!) == true)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://100.123.224.76:18789/")!) == true) // Tailscale CGNAT
        // 测试非本地网络 URL
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "https://example.com/")!) == false)
        #expect(screen.isLocalNetworkCanvasURL(URL(string: "http://8.8.8.8/")!) == false)
    }

    /// 测试 parseA2UIActionBody 方法是否能正确解析 JSON 字符串
    @Test func parseA2UIActionBodyAcceptsJSONString() throws {
        let body = ScreenController.parseA2UIActionBody("{\"userAction\":{\"name\":\"hello\"}}")
        let userAction = try #require(body?["userAction"] as? [String: Any])
        #expect(userAction["name"] as? String == "hello")
    }
}

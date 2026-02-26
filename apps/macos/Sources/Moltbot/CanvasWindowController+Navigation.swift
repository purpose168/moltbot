import AppKit
import WebKit

extension CanvasWindowController {
    // MARK: - WKNavigationDelegate

    @MainActor
    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void)
    {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased()

        // 深度链接：允许本地 Canvas 内容直接调用代理，无需通过 NSWorkspace 跳转。
        if scheme == "moltbot" {
            if self.webView.url?.scheme == CanvasScheme.scheme {
                Task { await DeepLinkHandler.shared.handle(url: url) }
            } else {
                canvasWindowLogger
                    .debug("忽略来自非画布页面的深度链接 \(url.absoluteString, privacy: .public)")
            }
            decisionHandler(.cancel)
            return
        }

        // 合理情况下将网页内容保持在面板内。
        // `about:blank` 及其相关链接是 WKWebView 的常见内部导航；永远不要将它们发送到 NSWorkspace。
        if scheme == CanvasScheme.scheme
            || scheme == "https"
            || scheme == "http"
            || scheme == "about"
            || scheme == "blob"
            || scheme == "data"
            || scheme == "javascript"
        {
            decisionHandler(.allow)
            return
        }

        // 仅当存在已注册的处理程序时才打开外部 URL，否则 macOS 会显示令人困惑的
        // "没有应用程序设置为打开 URL ..." 警报（例如对于 about:blank）。
        if let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil)
        } else {
            canvasWindowLogger.debug("没有应用程序可以打开 URL \(url.absoluteString, privacy: .public)")
        }
        decisionHandler(.cancel)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation?) {
        self.applyDebugStatusIfNeeded()
    }
}

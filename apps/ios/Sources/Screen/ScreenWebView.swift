import MoltbotKit
import SwiftUI
import WebKit

struct ScreenWebView: UIViewRepresentable {
    var controller: ScreenController

    func makeUIView(context: Context) -> WKWebView {
        self.controller.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 状态变更由 ScreenController 驱动。
    }
}

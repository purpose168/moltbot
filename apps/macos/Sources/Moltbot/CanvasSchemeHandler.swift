import MoltbotKit
import Foundation
import OSLog
import WebKit

private let canvasLogger = Logger(subsystem: "bot.molt", category: "Canvas")

/// Canvas 自定义 URL 方案处理器，用于处理 WebView 中的 Canvas 相关请求
final class CanvasSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    /// 初始化 CanvasSchemeHandler
    /// - Parameter root: 根目录 URL
    init(root: URL) {
        self.root = root
    }

    /// 处理 WebView 的 URL 方案任务
    /// - Parameters:
    ///   - webView: WebView 实例（未使用）
    ///   - urlSchemeTask: URL 方案任务
    func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(NSError(domain: "Canvas", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "缺少 URL",
            ]))
            return
        }

        let response = self.response(for: url)
        let mime = response.mime
        let data = response.data
        let encoding = self.textEncodingName(forMimeType: mime)

        let urlResponse = URLResponse(
            url: url,
            mimeType: mime,
            expectedContentLength: data.count,
            textEncodingName: encoding)
        urlSchemeTask.didReceive(urlResponse)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    /// 停止 URL 方案任务（无操作）
    /// - Parameters:
    ///   - webView: WebView 实例（未使用）
    ///   - urlSchemeTask: URL 方案任务（未使用）
    func webView(_: WKWebView, stop _: WKURLSchemeTask) {
        // 无操作
    }

    /// Canvas 响应结构体
    private struct CanvasResponse {
        let mime: String  // MIME 类型
        let data: Data    // 响应数据
    }

    /// 根据 URL 生成响应
    /// - Parameter url: 请求 URL
    /// - Returns: CanvasResponse 实例
    private func response(for url: URL) -> CanvasResponse {
        guard url.scheme == CanvasScheme.scheme else {
            return self.html("无效的方案。")
        }
        guard let session = url.host, !session.isEmpty else {
            return self.html("缺少会话。")
        }

        // 保持会话组件安全；不允许斜杠或路径遍历
        if session.contains("/") || session.contains("..") {
            return self.html("无效的会话。")
        }

        let sessionRoot = self.root.appendingPathComponent(session, isDirectory: true)

        // 路径映射：请求路径直接映射到会话目录
        var path = url.path
        if let qIdx = path.firstIndex(of: "?") { path = String(path[..<qIdx]) }
        if path.hasPrefix("/") { path.removeFirst() }
        path = path.removingPercentEncoding ?? path

        // 特殊情况：当根索引缺失时显示欢迎页面
        if path.isEmpty {
            let indexA = sessionRoot.appendingPathComponent("index.html", isDirectory: false)
            let indexB = sessionRoot.appendingPathComponent("index.htm", isDirectory: false)
            if !FileManager().fileExists(atPath: indexA.path),
               !FileManager().fileExists(atPath: indexB.path)
            {
                return self.scaffoldPage(sessionRoot: sessionRoot)
            }
        }

        let resolved = self.resolveFileURL(sessionRoot: sessionRoot, requestPath: path)
        guard let fileURL = resolved else {
            return self.html("未找到", title: "Canvas: 404")
        }

        // 目录遍历防护：提供的文件必须位于会话根目录下
        let standardizedRoot = sessionRoot.standardizedFileURL
        let standardizedFile = fileURL.standardizedFileURL
        guard standardizedFile.path.hasPrefix(standardizedRoot.path) else {
            return self.html("禁止访问", title: "Canvas: 403")
        }

        do {
            let data = try Data(contentsOf: standardizedFile)
            let mime = CanvasScheme.mimeType(forExtension: standardizedFile.pathExtension)
            let servedPath = standardizedFile.path
            canvasLogger.debug(
                "已提供 \(session, privacy: .public)/\(path, privacy: .public) -> \(servedPath, privacy: .public)")
            return CanvasResponse(mime: mime, data: data)
        } catch {
            let failedPath = standardizedFile.path
            let errorText = error.localizedDescription
            canvasLogger
                .error(
                    "读取失败 \(failedPath, privacy: .public): \(errorText, privacy: .public)")
            return self.html("读取文件失败。", title: "Canvas 错误")
        }
    }

    /// 解析文件 URL
    /// - Parameters:
    ///   - sessionRoot: 会话根目录 URL
    ///   - requestPath: 请求路径
    /// - Returns: 解析后的文件 URL，若不存在则返回 nil
    private func resolveFileURL(sessionRoot: URL, requestPath: String) -> URL? {
        let fm = FileManager()
        var candidate = sessionRoot.appendingPathComponent(requestPath, isDirectory: false)

        var isDir: ObjCBool = false
        if fm.fileExists(atPath: candidate.path, isDirectory: &isDir) {
            if isDir.boolValue {
                if let idx = self.resolveIndex(in: candidate) { return idx }
                return nil
            }
            return candidate
        }

        // 目录索引行为：
        // - "/yolo" 如果目录存在，则提供 "<yolo>/index.html"
        if !requestPath.isEmpty, !requestPath.hasSuffix("/") {
            candidate = sessionRoot.appendingPathComponent(requestPath, isDirectory: true)
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                if let idx = self.resolveIndex(in: candidate) { return idx }
            }
        }

        // 根目录回退：
        // - "/" 如果存在，则提供 "<sessionRoot>/index.html"
        if requestPath.isEmpty {
            return self.resolveIndex(in: sessionRoot)
        }

        return nil
    }

    /// 解析目录中的索引文件
    /// - Parameter dir: 目录 URL
    /// - Returns: 索引文件 URL，若不存在则返回 nil
    private func resolveIndex(in dir: URL) -> URL? {
        let fm = FileManager()
        let a = dir.appendingPathComponent("index.html", isDirectory: false)
        if fm.fileExists(atPath: a.path) { return a }
        let b = dir.appendingPathComponent("index.htm", isDirectory: false)
        if fm.fileExists(atPath: b.path) { return b }
        return nil
    }

    /// 生成 HTML 响应
    /// - Parameters:
    ///   - body: HTML 正文内容
    ///   - title: 页面标题，默认为 "Canvas"
    /// - Returns: CanvasResponse 实例
    private func html(_ body: String, title: String = "Canvas") -> CanvasResponse {
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width, initial-scale=1" />
            <title>\(title)</title>
            <style>
              :root { color-scheme: light; }
              html,body { height:100%; margin:0; }
              body {
                font: 13px -apple-system, system-ui;
                display:flex;
                align-items:center;
                justify-content:center;
                background: #fff;
                color:#111827;
              }
              .card {
                max-width: 520px;
                padding: 18px 18px;
                border-radius: 12px;
                border: 1px solid rgba(0,0,0,.08);
                box-shadow: 0 10px 30px rgba(0,0,0,.08);
              }
              .muted { color:#6b7280; margin-top:8px; }
              code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
            </style>
          </head>
          <body>
            <div class="card">
              <div>\(body)</div>
            </div>
          </body>
        </html>
        """
        return CanvasResponse(mime: "text/html", data: Data(html.utf8))
    }

    /// 生成欢迎页面响应
    /// - Parameter sessionRoot: 会话根目录 URL
    /// - Returns: CanvasResponse 实例
    private func welcomePage(sessionRoot: URL) -> CanvasResponse {
        let escaped = sessionRoot.path
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let body = """
        <div style="font-weight:600; font-size:14px;">Canvas 已准备就绪。</div>
        <div class="muted">在以下目录中创建 <code>index.html</code>：</div>
        <div style="margin-top:10px;"><code>\(escaped)</code></div>
        """
        return self.html(body, title: "Canvas")
    }

    /// 生成脚手架页面响应
    /// - Parameter sessionRoot: 会话根目录 URL
    /// - Returns: CanvasResponse 实例
    private func scaffoldPage(sessionRoot: URL) -> CanvasResponse {
        // 默认 Canvas 用户体验：当不存在索引时，显示内置脚手架页面
        if let data = self.loadBundledResourceData(relativePath: "CanvasScaffold/scaffold.html") {
            return CanvasResponse(mime: "text/html", data: data)
        }

        // 开发配置错误的回退：显示经典欢迎页面
        return self.welcomePage(sessionRoot: sessionRoot)
    }

    /// 加载捆绑资源数据
    /// - Parameter relativePath: 相对路径
    /// - Returns: 资源数据，若加载失败则返回 nil
    private func loadBundledResourceData(relativePath: String) -> Data? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("..") || trimmed.contains("\\") { return nil }

        let parts = trimmed.split(separator: "/")
        guard let filename = parts.last else { return nil }
        let subdirectory =
            parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
        let fileURL = URL(fileURLWithPath: String(filename))
        let ext = fileURL.pathExtension
        let name = fileURL.deletingPathExtension().lastPathComponent
        guard !name.isEmpty, !ext.isEmpty else { return nil }

        let bundle = MoltbotKitResources.bundle
        let resourceURL =
            bundle.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
            ?? bundle.url(forResource: name, withExtension: ext)
        guard let resourceURL else { return nil }
        return try? Data(contentsOf: resourceURL)
    }

    /// 根据 MIME 类型获取文本编码名称
    /// - Parameter mimeType: MIME 类型
    /// - Returns: 文本编码名称，若不适用则返回 nil
    private func textEncodingName(forMimeType mimeType: String) -> String? {
        if mimeType.hasPrefix("text/") { return "utf-8" }
        switch mimeType {
        case "application/javascript", "application/json", "image/svg+xml":
            return "utf-8"
        default:
            return nil
        }
    }
}

#if DEBUG
/// CanvasSchemeHandler 测试扩展
extension CanvasSchemeHandler {
    /// 测试响应生成
    /// - Parameter url: 请求 URL
    /// - Returns: (MIME 类型, 数据) 元组
    func _testResponse(for url: URL) -> (mime: String, data: Data) {
        let response = self.response(for: url)
        return (response.mime, response.data)
    }

    /// 测试文件 URL 解析
    /// - Parameters:
    ///   - sessionRoot: 会话根目录 URL
    ///   - requestPath: 请求路径
    /// - Returns: 解析后的文件 URL，若不存在则返回 nil
    func _testResolveFileURL(sessionRoot: URL, requestPath: String) -> URL? {
        self.resolveFileURL(sessionRoot: sessionRoot, requestPath: requestPath)
    }

    /// 测试文本编码名称获取
    /// - Parameter mimeType: MIME 类型
    /// - Returns: 文本编码名称，若不适用则返回 nil
    func _testTextEncodingName(for mimeType: String) -> String? {
        self.textEncodingName(forMimeType: mimeType)
    }
}
#endif

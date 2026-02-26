import Foundation

/// CanvasScheme 枚举用于处理 Moltbot 画布相关的 URL 方案和 MIME 类型
enum CanvasScheme {
    /// 定义画布使用的 URL 方案
    static let scheme = "moltbot-canvas"

    /// 为指定会话和路径创建 URL
    /// - Parameters:
    ///   - session: 会话标识符，用作 URL 的主机部分
    ///   - path: 可选的路径部分，默认为 nil
    /// - Returns: 构建的 URL 对象，或 nil 如果构建失败
    static func makeURL(session: String, path: String? = nil) -> URL? {
        var comps = URLComponents()
        comps.scheme = Self.scheme
        comps.host = session
        // 处理路径，确保格式正确
        let p = (path ?? "/").trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty || p == "/" {
            comps.path = "/"
        } else if p.hasPrefix("/") {
            comps.path = p
        } else {
            comps.path = "/" + p
        }
        return comps.url
    }

    /// 根据文件扩展名返回对应的 MIME 类型
    /// - Parameter ext: 文件扩展名
    /// - Returns: 对应的 MIME 类型字符串
    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        // 注意：WKURLSchemeHandler 使用 URLResponse(mimeType:)，它期望一个纯 MIME 类型
        // （没有 `; charset=...`）。编码通过 URLResponse(textEncodingName:) 提供。
        case "html", "htm": "text/html"
        case "js", "mjs": "application/javascript"
        case "css": "text/css"
        case "json", "map": "application/json"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "ico": "image/x-icon"
        case "woff2": "font/woff2"
        case "woff": "font/woff"
        case "ttf": "font/ttf"
        case "wasm": "application/wasm"
        default: "application/octet-stream"
        }
    }
}

import AppKit
import MoltbotIPC
import MoltbotKit
import Foundation
import WebKit

/// Canvas A2UIAction 消息处理器，用于处理来自 WebView 的 Canvas 相关 UI 操作消息
final class CanvasA2UIActionMessageHandler: NSObject, WKScriptMessageHandler {
    /// 消息名称
    static let messageName = "moltbotCanvasA2UIAction"

    /// 会话密钥
    private let sessionKey: String

    /// 初始化方法
    /// - Parameter sessionKey: 会话密钥
    init(sessionKey: String) {
        self.sessionKey = sessionKey
        super.init()
    }

    /// 处理接收到的脚本消息
    /// - Parameters:
    ///   - userContentController: 用户内容控制器
    ///   - message: 接收到的消息
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        // 验证消息名称是否匹配
        guard message.name == Self.messageName else { return }

        // 只接受来自本地 Canvas 内容的操作（不接受任意网页）
        guard let webView = message.webView, let url = webView.url else { return }
        if url.scheme == CanvasScheme.scheme {
            // 合法的 Canvas scheme
        } else if Self.isLocalNetworkCanvasURL(url) {
            // 合法的本地网络 Canvas URL
        } else {
            return
        }

        // 解析消息体
        let body: [String: Any] = {
            if let dict = message.body as? [String: Any] { return dict }
            if let dict = message.body as? [AnyHashable: Any] {
                return dict.reduce(into: [String: Any]()) { acc, pair in
                    guard let key = pair.key as? String else { return }
                    acc[key] = pair.value
                }
            }
            return [:]
        }()
        guard !body.isEmpty else { return }

        // 提取用户操作
        let userActionAny = body["userAction"] ?? body
        let userAction: [String: Any] = {
            if let dict = userActionAny as? [String: Any] { return dict }
            if let dict = userActionAny as? [AnyHashable: Any] {
                return dict.reduce(into: [String: Any]()) { acc, pair in
                    guard let key = pair.key as? String else { return }
                    acc[key] = pair.value
                }
            }
            return [:]
        }()
        guard !userAction.isEmpty else { return }

        // 提取操作名称
        guard let name = MoltbotCanvasA2UIAction.extractActionName(userAction) else { return }
        // 生成或使用现有的操作 ID
        let actionId =
            (userAction["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? UUID().uuidString

        // 记录操作信息
        canvasWindowLogger.info("A2UI 操作 \(name, privacy: .public) 会话=\(self.sessionKey, privacy: .public)")

        // 提取相关信息
        let surfaceId = (userAction["surfaceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "main"
        let sourceComponentId = (userAction["sourceComponentId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "-"
        let instanceId = InstanceIdentity.instanceId.lowercased()
        let contextJSON = MoltbotCanvasA2UIAction.compactJSON(userAction["context"])

        // 构造代理消息上下文（高效且明确）
        // 代理应将此视为 UI 事件并（默认）更新 Canvas
        let messageContext = MoltbotCanvasA2UIAction.AgentMessageContext(
            actionName: name,
            session: .init(key: self.sessionKey, surfaceId: surfaceId),
            component: .init(id: sourceComponentId, host: InstanceIdentity.displayName, instanceId: instanceId),
            contextJSON: contextJSON)
        // 格式化代理消息
        let text = MoltbotCanvasA2UIAction.formatAgentMessage(messageContext)

        // 异步处理
        Task { [weak webView] in
            // 如果是本地连接模式，激活网关进程
            if AppStateStore.shared.connectionMode == .local {
                GatewayProcessManager.shared.setActive(true)
            }

            // 发送消息到网关
            let result = await GatewayConnection.shared.sendAgent(
                GatewayAgentInvocation(
                    message: text,
                    sessionKey: self.sessionKey,
                    thinking: "low",
                    deliver: false,
                    to: nil,
                    channel: .last,
                    idempotencyKey: actionId))

            // 在主线程更新 WebView
            await MainActor.run { [weak webView] in
                guard let webView else { return }
                // 生成 JavaScript 代码以更新操作状态
                let js = MoltbotCanvasA2UIAction.jsDispatchA2UIActionStatus(
                    actionId: actionId,
                    ok: result.ok,
                    error: result.error)
                // 执行 JavaScript
                webView.evaluateJavaScript(js) { _, _ in }
            }
            
            // 记录错误信息
            if !result.ok {
                canvasWindowLogger.error(
                    """
                    A2UI 操作发送失败 名称=\(name, privacy: .public) \
                    错误=\(result.error ?? "未知", privacy: .public)
                    """)
            }
        }
    }

    /// 检查 URL 是否为本地网络 Canvas URL
    /// - Parameter url: 要检查的 URL
    /// - Returns: 如果是本地网络 Canvas URL 返回 true，否则返回 false
    static func isLocalNetworkCanvasURL(_ url: URL) -> Bool {
        // 检查协议是否为 http 或 https
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        // 检查主机是否存在且非空
        guard let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return false
        }
        // 检查是否为 localhost
        if host == "localhost" { return true }
        // 检查是否为 .local 后缀
        if host.hasSuffix(".local") { return true }
        // 检查是否为 .ts.net 后缀
        if host.hasSuffix(".ts.net") { return true }
        // 检查是否为 .tailscale.net 后缀
        if host.hasSuffix(".tailscale.net") { return true }
        // 检查是否为无点无冒号的主机名
        if !host.contains("."), !host.contains(":") { return true }
        // 检查是否为本地网络 IPv4 地址
        if let ipv4 = Self.parseIPv4(host) {
            return Self.isLocalNetworkIPv4(ipv4)
        }
        return false
    }

    /// 解析 IPv4 地址
    /// - Parameter host: 主机名
    /// - Returns: 解析后的 IPv4 地址元组，格式为 (a, b, c, d)
    static func parseIPv4(_ host: String) -> (UInt8, UInt8, UInt8, UInt8)? {
        // 按点分割主机名
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        // 确保有 4 个部分
        guard parts.count == 4 else { return nil }
        // 尝试将每个部分转换为 UInt8
        let bytes: [UInt8] = parts.compactMap { UInt8($0) }
        // 确保所有部分都成功转换
        guard bytes.count == 4 else { return nil }
        // 返回解析后的地址
        return (bytes[0], bytes[1], bytes[2], bytes[3])
    }

    /// 检查 IPv4 地址是否为本地网络地址
    /// - Parameter ip: IPv4 地址元组
    /// - Returns: 如果是本地网络地址返回 true，否则返回 false
    static func isLocalNetworkIPv4(_ ip: (UInt8, UInt8, UInt8, UInt8)) -> Bool {
        let (a, b, _, _) = ip
        // 检查 10.0.0.0/8
        if a == 10 { return true }
        // 检查 172.16.0.0/12
        if a == 172, (16...31).contains(Int(b)) { return true }
        // 检查 192.168.0.0/16
        if a == 192, b == 168 { return true }
        // 检查 127.0.0.0/8 (环回地址)
        if a == 127 { return true }
        // 检查 169.254.0.0/16 (链路本地地址)
        if a == 169, b == 254 { return true }
        // 检查 100.64.0.0/10 (共享地址空间)
        if a == 100, (64...127).contains(Int(b)) { return true }
        return false
    }

    /// 格式化助手方法位于 MoltbotKit 中的 `MoltbotCanvasA2UIAction` 类。
}
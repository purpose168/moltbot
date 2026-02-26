import AppKit
import MoltbotIPC
import MoltbotKit
import Foundation
import OSLog

@MainActor
final class CanvasManager {
    /// 单例实例
    static let shared = CanvasManager()

    /// 日志记录器
    private static let logger = Logger(subsystem: "bot.molt", category: "CanvasManager")

    /// 面板控制器
    private var panelController: CanvasWindowController?
    /// 面板会话键
    private var panelSessionKey: String?
    /// 上次自动导航的 A2UI URL
    private var lastAutoA2UIUrl: String?
    /// 网关监听任务
    private var gatewayWatchTask: Task<Void, Never>?

    /// 私有初始化方法
    private init() {
        self.startGatewayObserver()
    }

    /// 面板可见性变化回调
    var onPanelVisibilityChanged: ((Bool) -> Void)?

    /// 可选的锚点提供者（例如菜单栏状态项）。如果为 nil，Canvas 会锚定到鼠标光标。
    var defaultAnchorProvider: (() -> NSRect?)?

    /// Canvas 根目录
    private nonisolated static let canvasRoot: URL = {
        let base = FileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Moltbot/canvas", isDirectory: true)
    }()

    /// 显示 Canvas 面板
    /// - Parameters:
    ///   - sessionKey: 会话键
    ///   - path: 路径
    ///   - placement: 放置位置
    /// - Returns: 目录路径
    func show(sessionKey: String, path: String? = nil, placement: CanvasPlacement? = nil) throws -> String {
        try self.showDetailed(sessionKey: sessionKey, target: path, placement: placement).directory
    }

    /// 详细显示 Canvas 面板
    /// - Parameters:
    ///   - sessionKey: 会话键
    ///   - target: 目标路径
    ///   - placement: 放置位置
    /// - Returns: Canvas 显示结果
    func showDetailed(
        sessionKey: String,
        target: String? = nil,
        placement: CanvasPlacement? = nil) throws -> CanvasShowResult
    {
        Self.logger.debug(
            """
            showDetailed 开始 session=\(sessionKey, privacy: .public) \
            target=\(target ?? "", privacy: .public) \
            placement=\(placement != nil)
            """)
        // 获取锚点提供者，优先使用默认锚点提供者，否则使用鼠标锚点提供者
        let anchorProvider = self.defaultAnchorProvider ?? Self.mouseAnchorProvider
        // 清理会话键
        let session = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // 规范化目标路径
        let normalizedTarget = target?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty

        // 如果存在相同会话的控制器，重用它
        if let controller = self.panelController, self.panelSessionKey == session {
            Self.logger.debug("showDetailed 重用现有会话=\(session, privacy: .public)")
            controller.onVisibilityChanged = { [weak self] visible in
                self?.onPanelVisibilityChanged?(visible)
            }
            // 展示锚定面板
            controller.presentAnchoredPanel(anchorProvider: anchorProvider)
            // 应用首选放置位置
            controller.applyPreferredPlacement(placement)
            // 刷新调试状态
            self.refreshDebugStatus()

            // 现有会话：仅当提供了明确目标时才导航
            if let normalizedTarget {
                controller.load(target: normalizedTarget)
                return self.makeShowResult(
                    directory: controller.directoryPath,
                    target: target,
                    effectiveTarget: normalizedTarget)
            }

            // 自动导航到 A2UI
            self.maybeAutoNavigateToA2UIAsync(controller: controller)
            return CanvasShowResult(
                directory: controller.directoryPath,
                target: target,
                effectiveTarget: nil,
                status: .shown,
                url: nil)
        }

        // 创建新会话
        Self.logger.debug("showDetailed 创建新会话=\(session, privacy: .public)")
        self.panelController?.close()
        self.panelController = nil
        self.panelSessionKey = nil

        // 确保 Canvas 根目录存在
        Self.logger.debug("showDetailed 确保 canvas 根目录存在")
        try FileManager().createDirectory(at: Self.canvasRoot, withIntermediateDirectories: true)
        // 初始化 CanvasWindowController
        Self.logger.debug("showDetailed 初始化 CanvasWindowController")
        let controller = try CanvasWindowController(
            sessionKey: session,
            root: Self.canvasRoot,
            presentation: .panel(anchorProvider: anchorProvider))
        Self.logger.debug("showDetailed CanvasWindowController 初始化完成")
        controller.onVisibilityChanged = { [weak self] visible in
            self?.onPanelVisibilityChanged?(visible)
        }
        self.panelController = controller
        self.panelSessionKey = session
        controller.applyPreferredPlacement(placement)

        // 新会话：默认为 "/"，以便用户看到欢迎页面或 `index.html`
        let effectiveTarget = normalizedTarget ?? "/"
        Self.logger.debug("showDetailed 显示 Canvas effectiveTarget=\(effectiveTarget, privacy: .public)")
        controller.showCanvas(path: effectiveTarget)
        Self.logger.debug("showDetailed 显示 Canvas 完成")
        if normalizedTarget == nil {
            self.maybeAutoNavigateToA2UIAsync(controller: controller)
        }
        self.refreshDebugStatus()

        return self.makeShowResult(
            directory: controller.directoryPath,
            target: target,
            effectiveTarget: effectiveTarget)
    }

    /// 隐藏指定会话的 Canvas 面板
    /// - Parameter sessionKey: 会话键
    func hide(sessionKey: String) {
        let session = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.panelSessionKey == session else { return }
        self.panelController?.hideCanvas()
    }

    /// 隐藏所有 Canvas 面板
    func hideAll() {
        self.panelController?.hideCanvas()
    }

    /// 在 Canvas 中执行 JavaScript
    /// - Parameters:
    ///   - sessionKey: 会话键
    ///   - javaScript: JavaScript 代码
    /// - Returns: 执行结果
    func eval(sessionKey: String, javaScript: String) async throws -> String {
        _ = try self.show(sessionKey: sessionKey, path: nil)
        guard let controller = self.panelController else { return "" }
        return try await controller.eval(javaScript: javaScript)
    }

    /// 获取 Canvas 面板的快照
    /// - Parameters:
    ///   - sessionKey: 会话键
    ///   - outPath: 输出路径
    /// - Returns: 快照路径
    func snapshot(sessionKey: String, outPath: String?) async throws -> String {
        _ = try self.show(sessionKey: sessionKey, path: nil)
        guard let controller = self.panelController else {
            throw NSError(domain: "Canvas", code: 21, userInfo: [NSLocalizedDescriptionKey: "canvas not available"])
        }
        return try await controller.snapshot(to: outPath)
    }

    // MARK: - Gateway A2UI 自动导航

    /// 开始网关观察者
    private func startGatewayObserver() {
        self.gatewayWatchTask?.cancel()
        self.gatewayWatchTask = Task { [weak self] in
            guard let self else { return }
            let stream = await GatewayConnection.shared.subscribe(bufferingNewest: 1)
            for await push in stream {
                self.handleGatewayPush(push)
            }
        }
    }

    /// 处理网关推送
    /// - Parameter push: 网关推送数据
    private func handleGatewayPush(_ push: GatewayPush) {
        guard case let .snapshot(snapshot) = push else { return }
        let raw = snapshot.canvashosturl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty {
            Self.logger.debug("网关快照中缺少 canvas 主机 URL")
        } else {
            Self.logger.debug("canvas 主机 URL 快照=\(raw, privacy: .public)")
        }
        let a2uiUrl = Self.resolveA2UIHostUrl(from: raw)
        if a2uiUrl == nil, !raw.isEmpty {
            Self.logger.debug("canvas 主机 URL 无效；无法解析 A2UI")
        }
        guard let controller = self.panelController else {
            if a2uiUrl != nil {
                Self.logger.debug("canvas 面板不可见；跳过自动导航")
            }
            return
        }
        self.maybeAutoNavigateToA2UI(controller: controller, a2uiUrl: a2uiUrl)
    }

    /// 异步尝试自动导航到 A2UI
    /// - Parameter controller: Canvas 窗口控制器
    private func maybeAutoNavigateToA2UIAsync(controller: CanvasWindowController) {
        Task { [weak self] in
            guard let self else { return }
            let a2uiUrl = await self.resolveA2UIHostUrl()
            await MainActor.run {
                guard self.panelController === controller else { return }
                self.maybeAutoNavigateToA2UI(controller: controller, a2uiUrl: a2uiUrl)
            }
        }
    }

    /// 尝试自动导航到 A2UI
    /// - Parameters:
    ///   - controller: Canvas 窗口控制器
    ///   - a2uiUrl: A2UI URL
    private func maybeAutoNavigateToA2UI(controller: CanvasWindowController, a2uiUrl: String?) {
        guard let a2uiUrl else { return }
        let shouldNavigate = controller.shouldAutoNavigateToA2UI(lastAutoTarget: self.lastAutoA2UIUrl)
        guard shouldNavigate else {
            Self.logger.debug("canvas 自动导航跳过；目标未更改")
            return
        }
        Self.logger.debug("canvas 自动导航 -> \(a2uiUrl, privacy: .public)")
        controller.load(target: a2uiUrl)
        self.lastAutoA2UIUrl = a2uiUrl
    }

    /// 解析 A2UI 主机 URL
    /// - Returns: A2UI URL
    private func resolveA2UIHostUrl() async -> String? {
        let raw = await GatewayConnection.shared.canvasHostUrl()
        return Self.resolveA2UIHostUrl(from: raw)
    }

    /// 刷新调试状态
    func refreshDebugStatus() {
        guard let controller = self.panelController else { return }
        let enabled = AppStateStore.shared.debugPaneEnabled
        let mode = AppStateStore.shared.connectionMode
        let title: String?
        let subtitle: String?
        switch mode {
        case .remote:
            title = "远程控制"
            switch ControlChannel.shared.state {
            case .connected:
                subtitle = "已连接"
            case .connecting:
                subtitle = "连接中…"
            case .disconnected:
                subtitle = "已断开"
            case let .degraded(message):
                subtitle = message.isEmpty ? "性能下降" : message
            }
        case .local:
            title = GatewayProcessManager.shared.status.label
            subtitle = mode.rawValue
        case .unconfigured:
            title = "未配置"
            subtitle = mode.rawValue
        }
        controller.updateDebugStatus(enabled: enabled, title: title, subtitle: subtitle)
    }

    /// 从原始 URL 解析 A2UI 主机 URL
    /// - Parameter raw: 原始 URL
    /// - Returns: A2UI URL
    private static func resolveA2UIHostUrl(from raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let base = URL(string: trimmed) else { return nil }
        return base.appendingPathComponent("__moltbot__/a2ui/").absoluteString + "?platform=macos"
    }

    // MARK: - 锚定

    /// 鼠标锚点提供者
    /// - Returns: 鼠标位置的矩形
    private static func mouseAnchorProvider() -> NSRect? {
        let pt = NSEvent.mouseLocation
        return NSRect(x: pt.x, y: pt.y, width: 1, height: 1)
    }

    // 放置位置的解释由窗口控制器处理。

    // MARK: - 辅助方法

    /// 获取直接 URL
    /// - Parameter target: 目标路径
    /// - Returns: URL
    private static func directURL(for target: String?) -> URL? {
        guard let target else { return nil }
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 检查是否为 HTTP、HTTPS 或文件 URL
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "https" || scheme == "http" || scheme == "file" { return url }
        }

        // 便捷方法：现有的绝对文件路径解析为本地文件
        // （避免将 Canvas 路由如 "/" 视为文件系统路径）
        if trimmed.hasPrefix("/") {
            var isDir: ObjCBool = false
            if FileManager().fileExists(atPath: trimmed, isDirectory: &isDir), !isDir.boolValue {
                return URL(fileURLWithPath: trimmed)
            }
        }

        return nil
    }

    /// 创建显示结果
    /// - Parameters:
    ///   - directory: 目录
    ///   - target: 目标路径
    ///   - effectiveTarget: 有效目标路径
    /// - Returns: Canvas 显示结果
    private func makeShowResult(
        directory: String,
        target: String?,
        effectiveTarget: String) -> CanvasShowResult
    {
        // 如果是直接 URL，返回 Web 状态
        if let url = Self.directURL(for: effectiveTarget) {
            return CanvasShowResult(
                directory: directory,
                target: target,
                effectiveTarget: effectiveTarget,
                status: .web,
                url: url.absoluteString)
        }

        // 否则，返回本地状态
        let sessionDir = URL(fileURLWithPath: directory)
        let status = Self.localStatus(sessionDir: sessionDir, target: effectiveTarget)
        let host = sessionDir.lastPathComponent
        let canvasURL = CanvasScheme.makeURL(session: host, path: effectiveTarget)?.absoluteString
        return CanvasShowResult(
            directory: directory,
            target: target,
            effectiveTarget: effectiveTarget,
            status: status,
            url: canvasURL)
    }

    /// 获取本地状态
    /// - Parameters:
    ///   - sessionDir: 会话目录
    ///   - target: 目标路径
    /// - Returns: Canvas 显示状态
    private static func localStatus(sessionDir: URL, target: String) -> CanvasShowStatus {
        let fm = FileManager()
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutQuery = trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? trimmed
        var path = withoutQuery
        if path.hasPrefix("/") { path.removeFirst() }
        path = path.removingPercentEncoding ?? path

        // 根目录特殊情况：当不存在 index 时使用内置脚手架页面
        if path.isEmpty {
            let a = sessionDir.appendingPathComponent("index.html", isDirectory: false)
            let b = sessionDir.appendingPathComponent("index.htm", isDirectory: false)
            if fm.fileExists(atPath: a.path) || fm.fileExists(atPath: b.path) { return .ok }
            return .welcome
        }

        // 直接文件或目录
        var candidate = sessionDir.appendingPathComponent(path, isDirectory: false)
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: candidate.path, isDirectory: &isDir) {
            if isDir.boolValue {
                return Self.indexExists(in: candidate) ? .ok : .notFound
            }
            return .ok
        }

        // 目录索引行为（"/yolo" -> "yolo/index.html"）如果目录存在
        if !path.isEmpty, !path.hasSuffix("/") {
            candidate = sessionDir.appendingPathComponent(path, isDirectory: true)
            if fm.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue {
                return Self.indexExists(in: candidate) ? .ok : .notFound
            }
        }

        return .notFound
    }

    /// 检查目录中是否存在索引文件
    /// - Parameter dir: 目录
    /// - Returns: 是否存在索引文件
    private static func indexExists(in dir: URL) -> Bool {
        let fm = FileManager()
        let a = dir.appendingPathComponent("index.html", isDirectory: false)
        if fm.fileExists(atPath: a.path) { return true }
        let b = dir.appendingPathComponent("index.htm", isDirectory: false)
        return fm.fileExists(atPath: b.path)
    }

    // 没有捆绑的 A2UI shell；脚手架回退纯粹是视觉上的
}

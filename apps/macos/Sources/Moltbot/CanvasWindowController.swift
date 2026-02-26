import AppKit
import MoltbotIPC
import MoltbotKit
import Foundation
import WebKit

/// 画布窗口控制器，负责管理画布窗口的生命周期和交互
@MainActor
final class CanvasWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {
    /// 会话密钥
    let sessionKey: String
    /// 根目录URL
    private let root: URL
    /// 会话目录URL
    private let sessionDir: URL
    /// 方案处理器
    private let schemeHandler: CanvasSchemeHandler
    /// Web视图
    let webView: WKWebView
    /// A2UI动作消息处理器
    private var a2uiActionMessageHandler: CanvasA2UIActionMessageHandler?
    /// 文件监视器
    private let watcher: CanvasFileWatcher
    /// 悬停容器视图
    private let container: HoverChromeContainerView
    /// 画布呈现方式
    let presentation: CanvasPresentation
    /// 首选放置位置
    var preferredPlacement: CanvasPlacement?
    /// 当前目标路径
    private(set) var currentTarget: String?
    /// 是否启用调试状态
    private var debugStatusEnabled = false
    /// 调试状态标题
    private var debugStatusTitle: String?
    /// 调试状态副标题
    private var debugStatusSubtitle: String?

    /// 可见性变化回调
    var onVisibilityChanged: ((Bool) -> Void)?

    /// 初始化画布窗口控制器
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - root: 根目录URL
    ///   - presentation: 画布呈现方式
    /// - Throws: 初始化过程中可能抛出的错误
    init(sessionKey: String, root: URL, presentation: CanvasPresentation) throws {
        self.sessionKey = sessionKey
        self.root = root
        self.presentation = presentation

        canvasWindowLogger.debug("CanvasWindowController 初始化开始 session=\(sessionKey, privacy: .public)")
        let safeSessionKey = CanvasWindowController.sanitizeSessionKey(sessionKey)
        canvasWindowLogger.debug("CanvasWindowController 初始化 已清理会话密钥=\(safeSessionKey, privacy: .public)")
        self.sessionDir = root.appendingPathComponent(safeSessionKey, isDirectory: true)
        try FileManager().createDirectory(at: self.sessionDir, withIntermediateDirectories: true)
        canvasWindowLogger.debug("CanvasWindowController 初始化 会话目录已准备就绪")

        self.schemeHandler = CanvasSchemeHandler(root: root)
        canvasWindowLogger.debug("CanvasWindowController 初始化 方案处理器已准备就绪")

        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        canvasWindowLogger.debug("CanvasWindowController 初始化 配置已准备就绪")
        config.setURLSchemeHandler(self.schemeHandler, forURLScheme: CanvasScheme.scheme)
        canvasWindowLogger.debug("CanvasWindowController 初始化 方案处理器已安装")

        // 将A2UI "a2uiaction" DOM事件桥接到原生代理循环中
        //
        // 优先使用WKScriptMessageHandler（当WebKit暴露它时），否则回退到无人值守的深度链接
        // （包含应用生成的密钥，因此不会提示）
        canvasWindowLogger.debug("CanvasWindowController 初始化 构建A2UI桥接脚本")
        let deepLinkKey = DeepLinkHandler.currentCanvasKey()
        let injectedSessionKey = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "main"
        let bridgeScript = """
        (() => {
          try {
            if (location.protocol !== '\(CanvasScheme.scheme):') return;
            if (globalThis.__moltbotA2UIBridgeInstalled) return;
            globalThis.__moltbotA2UIBridgeInstalled = true;

            const deepLinkKey = \(Self.jsStringLiteral(deepLinkKey));
            const sessionKey = \(Self.jsStringLiteral(injectedSessionKey));
            const machineName = \(Self.jsStringLiteral(InstanceIdentity.displayName));
            const instanceId = \(Self.jsStringLiteral(InstanceIdentity.instanceId));

            globalThis.addEventListener('a2uiaction', (evt) => {
              try {
                const payload = evt?.detail ?? evt?.payload ?? null;
                if (!payload || payload.eventType !== 'a2ui.action') return;

                const action = payload.action ?? null;
                const name = action?.name ?? '';
                if (!name) return;

                const context = Array.isArray(action?.context) ? action.context : [];
                const userAction = {
                  id: (globalThis.crypto?.randomUUID?.() ?? String(Date.now())),
                  name,
                  surfaceId: payload.surfaceId ?? 'main',
                  sourceComponentId: payload.sourceComponentId ?? '',
                  dataContextPath: payload.dataContextPath ?? '',
                  timestamp: new Date().toISOString(),
                  ...(context.length ? { context } : {}),
                };

                const handler = globalThis.webkit?.messageHandlers?.clawdbotCanvasA2UIAction;

                // 如果捆绑的A2UI外壳存在，让它转发动作，以便我们保留其更丰富的
                // 上下文解析（数据模型路径查找、表面检测等）
                const hasBundledA2UIHost = !!globalThis.clawdbotA2UI || !!document.querySelector('moltbot-a2ui-host');
                if (hasBundledA2UIHost && handler?.postMessage) return;

                // 否则，在可能的情况下直接转发
                if (!hasBundledA2UIHost && handler?.postMessage) {
                  handler.postMessage({ userAction });
                  return;
                }

                const ctx = userAction.context ? (' ctx=' + JSON.stringify(userAction.context)) : '';
                const message =
                  'CANVAS_A2UI action=' + userAction.name +
                  ' session=' + sessionKey +
                  ' surface=' + userAction.surfaceId +
                  ' component=' + (userAction.sourceComponentId || '-') +
                  ' host=' + machineName.replace(/\\s+/g, '_') +
                  ' instance=' + instanceId +
                  ctx +
                  ' default=update_canvas';
                const params = new URLSearchParams();
                params.set('message', message);
                params.set('sessionKey', sessionKey);
                params.set('thinking', 'low');
                params.set('deliver', 'false');
                params.set('channel', 'last');
                params.set('key', deepLinkKey);
                location.href = 'moltbot://agent?' + params.toString();
              } catch {}
            }, true);
          } catch {}
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        canvasWindowLogger.debug("CanvasWindowController 初始化 A2UI桥接已安装")

        canvasWindowLogger.debug("CanvasWindowController 初始化 创建WKWebView")
        self.webView = WKWebView(frame: .zero, configuration: config)
        // 画布脚手架是一个完全自包含的HTML页面；避免依赖透明度底层
        self.webView.setValue(true, forKey: "drawsBackground")

        let sessionDir = self.sessionDir
        let webView = self.webView
        self.watcher = CanvasFileWatcher(url: sessionDir) { [weak webView] in
            Task { @MainActor in
                guard let webView else { return }

                // 仅当我们显示本地画布内容时才自动重新加载
                guard webView.url?.scheme == CanvasScheme.scheme else { return }

                let path = webView.url?.path ?? ""
                if path == "/" || path.isEmpty {
                    let indexA = sessionDir.appendingPathComponent("index.html", isDirectory: false)
                    let indexB = sessionDir.appendingPathComponent("index.htm", isDirectory: false)
                    if !FileManager().fileExists(atPath: indexA.path),
                       !FileManager().fileExists(atPath: indexB.path)
                    {
                        return
                    }
                }

                webView.reload()
            }
        }

        self.container = HoverChromeContainerView(containing: self.webView)
        let window = Self.makeWindow(for: presentation, contentView: self.container)
        canvasWindowLogger.debug("CanvasWindowController 初始化 makeWindow完成")
        super.init(window: window)

        let handler = CanvasA2UIActionMessageHandler(sessionKey: sessionKey)
        self.a2uiActionMessageHandler = handler
        self.webView.configuration.userContentController.add(handler, name: CanvasA2UIActionMessageHandler.messageName)

        self.webView.navigationDelegate = self
        self.window?.delegate = self
        self.container.onClose = { [weak self] in
            self?.hideCanvas()
        }

        self.watcher.start()
        canvasWindowLogger.debug("CanvasWindowController 初始化完成")
    }

    /// 不可用的初始化方法
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 析构方法
    @MainActor deinit {
        self.webView.configuration.userContentController
            .removeScriptMessageHandler(forName: CanvasA2UIActionMessageHandler.messageName)
        self.watcher.stop()
    }

    /// 应用首选放置位置
    /// - Parameter placement: 放置位置
    func applyPreferredPlacement(_ placement: CanvasPlacement?) {
        self.preferredPlacement = placement
    }

    /// 显示画布
    /// - Parameter path: 要加载的路径（可选）
    func showCanvas(path: String? = nil) {
        if case let .panel(anchorProvider) = self.presentation {
            self.presentAnchoredPanel(anchorProvider: anchorProvider)
            if let path {
                self.load(target: path)
            }
            return
        }

        self.showWindow(nil)
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let path {
            self.load(target: path)
        }
        self.onVisibilityChanged?(true)
    }

    /// 隐藏画布
    func hideCanvas() {
        if case .panel = self.presentation {
            self.persistFrameIfPanel()
        }
        self.window?.orderOut(nil)
        self.onVisibilityChanged?(false)
    }

    /// 加载目标内容
    /// - Parameter target: 目标路径或URL
    func load(target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        self.currentTarget = trimmed

        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            if scheme == "https" || scheme == "http" {
                canvasWindowLogger.debug("canvas 加载 url \(url.absoluteString, privacy: .public)")
                self.webView.load(URLRequest(url: url))
                return
            }
            if scheme == "file" {
                canvasWindowLogger.debug("canvas 加载 file \(url.absoluteString, privacy: .public)")
                self.loadFile(url)
                return
            }
        }

        // 便利功能：当绝对文件路径存在时，将其解析为本地文件
        // （避免将Canvas路由如"/"视为文件系统路径）
        if trimmed.hasPrefix("/") {
            var isDir: ObjCBool = false
            if FileManager().fileExists(atPath: trimmed, isDirectory: &isDir), !isDir.boolValue {
                let url = URL(fileURLWithPath: trimmed)
                canvasWindowLogger.debug("canvas 加载 file \(url.absoluteString, privacy: .public)")
                self.loadFile(url)
                return
            }
        }

        guard let url = CanvasScheme.makeURL(
            session: CanvasWindowController.sanitizeSessionKey(self.sessionKey),
            path: trimmed)
        else {
            canvasWindowLogger
                .error(
                    "invalid canvas url session=\(self.sessionKey, privacy: .public) path=\(trimmed, privacy: .public)")
            return
        }
        canvasWindowLogger.debug("canvas 加载 canvas \(url.absoluteString, privacy: .public)")
        self.webView.load(URLRequest(url: url))
    }

    /// 更新调试状态
    /// - Parameters:
    ///   - enabled: 是否启用
    ///   - title: 标题
    ///   - subtitle: 副标题
    func updateDebugStatus(enabled: Bool, title: String?, subtitle: String?) {
        self.debugStatusEnabled = enabled
        self.debugStatusTitle = title
        self.debugStatusSubtitle = subtitle
        self.applyDebugStatusIfNeeded()
    }

    /// 必要时应用调试状态
    func applyDebugStatusIfNeeded() {
        let enabled = self.debugStatusEnabled
        let title = Self.jsOptionalStringLiteral(self.debugStatusTitle)
        let subtitle = Self.jsOptionalStringLiteral(self.debugStatusSubtitle)
        let js = """
        (() => {
          try {
            const api = globalThis.__moltbot;
            if (!api) return;
            if (typeof api.setDebugStatusEnabled === 'function') {
              api.setDebugStatusEnabled(\(enabled ? "true" : "false"));
            }
            if (!\(enabled ? "true" : "false")) return;
            if (typeof api.setStatus === 'function') {
              api.setStatus(\(title), \(subtitle));
            }
          } catch (_) {}
        })();
        """
        self.webView.evaluateJavaScript(js) { _, _ in }
    }

    /// 加载文件
    /// - Parameter url: 文件URL
    private func loadFile(_ url: URL) {
        let fileURL = url.isFileURL ? url : URL(fileURLWithPath: url.path)
        let accessDir = fileURL.deletingLastPathComponent()
        self.webView.loadFileURL(fileURL, allowingReadAccessTo: accessDir)
    }

    /// 执行JavaScript代码
    /// - Parameter javaScript: JavaScript代码
    /// - Returns: 执行结果
    func eval(javaScript: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            self.webView.evaluateJavaScript(javaScript) { result, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let result {
                    cont.resume(returning: String(describing: result))
                } else {
                    cont.resume(returning: "")
                }
            }
        }
    }

    /// 截取画布快照
    /// - Parameter outPath: 输出路径（可选）
    /// - Returns: 快照文件路径
    func snapshot(to outPath: String?) async throws -> String {
        let image: NSImage = try await withCheckedThrowingContinuation { cont in
            self.webView.takeSnapshot(with: nil) { image, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let image else {
                    cont.resume(throwing: NSError(domain: "Canvas", code: 11, userInfo: [
                        NSLocalizedDescriptionKey: "snapshot returned nil image",
                    ]))
                    return
                }
                cont.resume(returning: image)
            }
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            throw NSError(domain: "Canvas", code: 12, userInfo: [
                NSLocalizedDescriptionKey: "failed to encode png",
            ])
        }

        let path: String
        if let outPath, !outPath.isEmpty {
            path = outPath
        } else {
            let ts = Int(Date().timeIntervalSince1970)
            path = "/tmp/moltbot-canvas-\(CanvasWindowController.sanitizeSessionKey(self.sessionKey))-\(ts).png"
        }

        try png.write(to: URL(fileURLWithPath: path), options: [.atomic])
        return path
    }

    /// 目录路径
    var directoryPath: String {
        self.sessionDir.path
    }

    /// 是否应该自动导航到A2UI
    /// - Parameter lastAutoTarget: 上次自动目标
    /// - Returns: 是否应该自动导航
    func shouldAutoNavigateToA2UI(lastAutoTarget: String?) -> Bool {
        let trimmed = (self.currentTarget ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" { return true }
        if let lastAuto = lastAutoTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastAuto.isEmpty,
           trimmed == lastAuto
        {
            return true
        }
        return false
    }
}

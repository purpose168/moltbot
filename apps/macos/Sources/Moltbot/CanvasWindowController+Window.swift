import AppKit
import MoltbotIPC

// MARK: - 窗口管理扩展
extension CanvasWindowController {
    // MARK: - 窗口创建与管理

    /// 根据展示模式创建窗口
    /// - Parameters:
    ///   - presentation: 展示模式（窗口或面板）
    ///   - contentView: 内容视图
    /// - Returns: 创建的NSWindow实例
    static func makeWindow(for presentation: CanvasPresentation, contentView: NSView) -> NSWindow {
        switch presentation {
        case .window:
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: CanvasLayout.windowSize),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false)
            window.title = "Moltbot Canvas"
            window.isReleasedWhenClosed = false
            window.contentView = contentView
            window.center()
            window.minSize = NSSize(width: 880, height: 680)
            return window

        case .panel:
            let panel = CanvasPanel(
                contentRect: NSRect(origin: .zero, size: CanvasLayout.panelSize),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false)
            // 保持Canvas在Voice Wake覆盖面板下方
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
            panel.hasShadow = true
            panel.isMovable = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.contentView = contentView
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.minSize = CanvasLayout.minPanelSize
            return panel
        }
    }

    /// 展示锚定的面板
    /// - Parameter anchorProvider: 提供锚点位置的闭包
    func presentAnchoredPanel(anchorProvider: @escaping () -> NSRect?) {
        guard case .panel = self.presentation, let window else { return }
        self.repositionPanel(using: anchorProvider)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(self.webView)
        VoiceWakeOverlayController.shared.bringToFrontIfVisible()
        self.onVisibilityChanged?(true)
    }

    /// 重新定位面板
    /// - Parameter anchorProvider: 提供锚点位置的闭包
    func repositionPanel(using anchorProvider: () -> NSRect?) {
        guard let panel = self.window else { return }
        let anchor = anchorProvider()
        // 确定目标屏幕：优先使用锚点所在屏幕，其次是鼠标光标所在屏幕，最后使用当前屏幕或主屏幕
        let targetScreen = Self.screen(forAnchor: anchor)
            ?? Self.screenContainingMouseCursor()
            ?? panel.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first

        // 尝试加载之前保存的窗口框架
        let restored = Self.loadRestoredFrame(sessionKey: self.sessionKey)
        // 检查恢复的框架是否有效
        let restoredIsValid = if let restored, let targetScreen {
            Self.isFrameMeaningfullyVisible(restored, on: targetScreen)
        } else {
            restored != nil
        }

        // 确定最终使用的框架
        var frame = if let restored, restoredIsValid {
            restored
        } else {
            Self.defaultTopRightFrame(panel: panel, screen: targetScreen)
        }

        // 应用代理提供的位置作为部分覆盖：
        // - 如果代理提供了x/y坐标，覆盖原点
        // - 如果代理提供了宽度/高度，覆盖尺寸
        // - 如果代理只提供了尺寸，保持记住的原点
        if let placement = self.preferredPlacement {
            if let x = placement.x { frame.origin.x = x }
            if let y = placement.y { frame.origin.y = y }
            if let w = placement.width { frame.size.width = max(CanvasLayout.minPanelSize.width, CGFloat(w)) }
            if let h = placement.height { frame.size.height = max(CanvasLayout.minPanelSize.height, CGFloat(h)) }
        }

        self.setPanelFrame(frame, on: targetScreen)
    }

    /// 获取默认的右上角框架
    /// - Parameters:
    ///   - panel: 面板窗口
    ///   - screen: 目标屏幕
    /// - Returns: 计算后的NSRect框架
    static func defaultTopRightFrame(panel: NSWindow, screen: NSScreen?) -> NSRect {
        let w = max(CanvasLayout.minPanelSize.width, panel.frame.width)
        let h = max(CanvasLayout.minPanelSize.height, panel.frame.height)
        return WindowPlacement.topRightFrame(
            size: NSSize(width: w, height: h),
            padding: CanvasLayout.defaultPadding,
            on: screen)
    }

    /// 设置面板框架
    /// - Parameters:
    ///   - frame: 目标框架
    ///   - screen: 目标屏幕
    func setPanelFrame(_ frame: NSRect, on screen: NSScreen?) {
        guard let panel = self.window else { return }
        guard let s = screen ?? panel.screen ?? NSScreen.main ?? NSScreen.screens.first else {
            panel.setFrame(frame, display: false)
            self.persistFrameIfPanel()
            return
        }

        // 约束框架到屏幕可见区域
        let constrained = Self.constrainFrame(frame, toVisibleFrame: s.visibleFrame)
        panel.setFrame(constrained, display: false)
        self.persistFrameIfPanel()
    }

    /// 根据锚点获取屏幕
    /// - Parameter anchor: 锚点矩形
    /// - Returns: 包含锚点的屏幕
    static func screen(forAnchor anchor: NSRect?) -> NSScreen? {
        guard let anchor else { return nil }
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        return NSScreen.screens.first { screen in
            screen.frame.contains(anchor.origin) || screen.frame.contains(center)
        }
    }

    /// 获取包含鼠标光标的屏幕
    /// - Returns: 包含鼠标光标的屏幕
    static func screenContainingMouseCursor() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// 判断框架是否有意义地可见
    /// - Parameters:
    ///   - frame: 要检查的框架
    ///   - screen: 目标屏幕
    /// - Returns: 是否可见
    static func isFrameMeaningfullyVisible(_ frame: NSRect, on screen: NSScreen) -> Bool {
        frame.intersects(screen.visibleFrame.insetBy(dx: 12, dy: 12))
    }

    /// 约束框架到可见框架
    /// - Parameters:
    ///   - frame: 原始框架
    ///   - bounds: 可见边界
    /// - Returns: 约束后的框架
    static func constrainFrame(_ frame: NSRect, toVisibleFrame bounds: NSRect) -> NSRect {
        if bounds == .zero { return frame }

        var next = frame
        // 约束宽度和高度在最小面板尺寸和边界宽度之间
        next.size.width = min(max(CanvasLayout.minPanelSize.width, next.size.width), bounds.width)
        next.size.height = min(max(CanvasLayout.minPanelSize.height, next.size.height), bounds.height)

        // 计算最大允许的x和y坐标
        let maxX = bounds.maxX - next.size.width
        let maxY = bounds.maxY - next.size.height

        // 约束原点坐标
        next.origin.x = maxX >= bounds.minX ? min(max(next.origin.x, bounds.minX), maxX) : bounds.minX
        next.origin.y = maxY >= bounds.minY ? min(max(next.origin.y, bounds.minY), maxY) : bounds.minY

        // 四舍五入坐标值以避免模糊
        next.origin.x = round(next.origin.x)
        next.origin.y = round(next.origin.y)
        return next
    }

    // MARK: - NSWindowDelegate

    /// 窗口即将关闭时的回调
    /// - Parameter: 通知对象
    func windowWillClose(_: Notification) {
        self.onVisibilityChanged?(false)
    }

    /// 窗口移动完成后的回调
    /// - Parameter: 通知对象
    func windowDidMove(_: Notification) {
        self.persistFrameIfPanel()
    }

    /// 窗口调整大小完成后的回调
    /// - Parameter: 通知对象
    func windowDidEndLiveResize(_: Notification) {
        self.persistFrameIfPanel()
    }

    /// 如果是面板则持久化框架
    func persistFrameIfPanel() {
        guard case .panel = self.presentation, let window else { return }
        Self.storeRestoredFrame(window.frame, sessionKey: self.sessionKey)
    }
}

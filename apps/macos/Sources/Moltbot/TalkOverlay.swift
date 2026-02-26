import AppKit
import Observation
import OSLog
import SwiftUI

/// 对话模式覆盖层控制器
/// 管理对话模式覆盖层的显示、隐藏和状态更新
@MainActor
@Observable
final class TalkOverlayController {
    static let shared = TalkOverlayController()
    static let overlaySize: CGFloat = 440      // 覆盖层大小
    static let orbSize: CGFloat = 96          // 音频球大小
    static let orbPadding: CGFloat = 12       // 音频球内边距
    static let orbHitSlop: CGFloat = 10       // 音频球点击区域扩展

    private let logger = Logger(subsystem: "bot.molt", category: "talk.overlay")

    /// 覆盖层模型数据
    struct Model {
        var isVisible: Bool = false           // 是否可见
        var phase: TalkModePhase = .idle      // 当前阶段
        var isPaused: Bool = false            // 是否暂停
        var level: Double = 0                 // 音频级别
    }

    var model = Model()
    private var window: NSPanel?              // 面板窗口
    private var hostingView: NSHostingView<TalkOverlayView>?  // 托管视图
    private let screenInset: CGFloat = 0       // 屏幕边距

    /// 显示覆盖层
    func present() {
        self.ensureWindow()
        self.hostingView?.rootView = TalkOverlayView(controller: self)
        let target = self.targetFrame()

        guard let window else { return }
        if !self.model.isVisible {
            self.model.isVisible = true
            let start = target.offsetBy(dx: 0, dy: -6)
            window.setFrame(start, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(target, display: true)
                window.animator().alphaValue = 1
            }
        } else {
            window.setFrame(target, display: true)
            window.orderFrontRegardless()
        }
    }

    /// 隐藏覆盖层
    func dismiss() {
        guard let window else {
            self.model.isVisible = false
            return
        }

        let target = window.frame.offsetBy(dx: 6, dy: 6)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                window.orderOut(nil)
                self.model.isVisible = false
            }
        }
    }

    /// 更新对话阶段
    func updatePhase(_ phase: TalkModePhase) {
        guard self.model.phase != phase else { return }
        self.logger.info("talk overlay phase=\(phase.rawValue, privacy: .public)")
        self.model.phase = phase
    }

    /// 更新暂停状态
    func updatePaused(_ paused: Bool) {
        guard self.model.isPaused != paused else { return }
        self.logger.info("talk overlay paused=\(paused)")
        self.model.isPaused = paused
    }

    /// 更新音频级别
    func updateLevel(_ level: Double) {
        guard self.model.isVisible else { return }
        self.model.level = max(0, min(1, level))
    }

    /// 获取当前窗口原点
    func currentWindowOrigin() -> CGPoint? {
        self.window?.frame.origin
    }

    /// 设置窗口原点
    func setWindowOrigin(_ origin: CGPoint) {
        guard let window else { return }
        window.setFrameOrigin(origin)
    }

    // MARK: - Private

    /// 确保窗口已创建
    private func ensureWindow() {
        if self.window != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.overlaySize, height: Self.overlaySize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        let host = TalkOverlayHostingView(rootView: TalkOverlayView(controller: self))
        host.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = host
        self.hostingView = host
        self.window = panel
    }

    /// 计算目标窗口框架
    private func targetFrame() -> NSRect {
        let screen = self.window?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return .zero }
        let size = NSSize(width: Self.overlaySize, height: Self.overlaySize)
        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.maxX - size.width - self.screenInset,
            y: visible.maxY - size.height - self.screenInset)
        return NSRect(origin: origin, size: size)
    }
}

/// 对话模式覆盖层托管视图
/// 允许首次鼠标点击事件
private final class TalkOverlayHostingView: NSHostingView<TalkOverlayView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

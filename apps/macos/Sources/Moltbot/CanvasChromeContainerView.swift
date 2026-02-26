import AppKit
import QuartzCore

/// 悬停时显示控制界面的容器视图
/// 当鼠标进入视图时显示关闭按钮、拖动区域和调整大小的句柄
final class HoverChromeContainerView: NSView {
    private let content: NSView                 // 内容视图
    private let chrome: CanvasChromeOverlayView  // 控制界面覆盖视图
    private var tracking: NSTrackingArea?        // 鼠标跟踪区域
    var onClose: (() -> Void)?                   // 关闭回调

    /// 初始化方法，包含指定的内容视图
    init(containing content: NSView) {
        self.content = content
        self.chrome = CanvasChromeOverlayView(frame: .zero)
        super.init(frame: .zero)

        self.wantsLayer = true
        self.layer?.cornerRadius = 12
        self.layer?.masksToBounds = true
        self.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        self.content.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(self.content)

        self.chrome.translatesAutoresizingMaskIntoConstraints = false
        self.chrome.alphaValue = 0  // 初始状态下隐藏控制界面
        self.chrome.onClose = { [weak self] in self?.onClose?() }
        self.addSubview(self.chrome)

        NSLayoutConstraint.activate([
            self.content.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.content.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.content.topAnchor.constraint(equalTo: self.topAnchor),
            self.content.bottomAnchor.constraint(equalTo: self.bottomAnchor),

            self.chrome.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.chrome.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.chrome.topAnchor.constraint(equalTo: self.topAnchor),
            self.chrome.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 更新鼠标跟踪区域，用于检测鼠标进入和退出事件
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            self.removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: self.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil)
        self.addTrackingArea(area)
        self.tracking = area
    }

    /// 画布拖动句柄视图，用于实现窗口拖动功能
    private final class CanvasDragHandleView: NSView {
        override func mouseDown(with event: NSEvent) {
            self.window?.performDrag(with: event)  // 执行窗口拖动
        }

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    }

    /// 画布调整大小句柄视图，用于实现窗口大小调整功能
    private final class CanvasResizeHandleView: NSView {
        private var startPoint: NSPoint = .zero  // 开始拖动的鼠标位置
        private var startFrame: NSRect = .zero   // 开始拖动时的窗口框架

        override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            _ = window.makeFirstResponder(self)
            self.startPoint = NSEvent.mouseLocation
            self.startFrame = window.frame
            super.mouseDown(with: event)
        }

        override func mouseDragged(with _: NSEvent) {
            guard let window else { return }
            let current = NSEvent.mouseLocation
            let dx = current.x - self.startPoint.x  // 水平移动距离
            let dy = current.y - self.startPoint.y  // 垂直移动距离

            var frame = self.startFrame
            // 调整宽度，确保不小于最小宽度
            frame.size.width = max(CanvasLayout.minPanelSize.width, frame.size.width + dx)
            frame.origin.y += dy  // 调整垂直位置
            // 调整高度，确保不小于最小高度
            frame.size.height = max(CanvasLayout.minPanelSize.height, frame.size.height - dy)

            // 约束窗口框架在屏幕可见区域内
            if let screen = window.screen {
                frame = CanvasWindowController.constrainFrame(frame, toVisibleFrame: screen.visibleFrame)
            }
            window.setFrame(frame, display: true)
        }
    }

    /// 画布控制界面覆盖视图，包含关闭按钮、拖动和调整大小的句柄
    private final class CanvasChromeOverlayView: NSView {
        var onClose: (() -> Void)?  // 关闭回调

        private let dragHandle = CanvasDragHandleView(frame: .zero)    // 拖动句柄
        private let resizeHandle = CanvasResizeHandleView(frame: .zero)  // 调整大小句柄

        /// 穿透视觉效果视图，不拦截鼠标事件
        private final class PassthroughVisualEffectView: NSVisualEffectView {
            override func hitTest(_: NSPoint) -> NSView? { nil }
        }

        /// 关闭按钮背景视图
        private let closeBackground: NSVisualEffectView = {
            let v = PassthroughVisualEffectView(frame: .zero)
            v.material = .hudWindow
            v.blendingMode = .withinWindow
            v.state = .active
            v.appearance = NSAppearance(named: .vibrantDark)
            v.wantsLayer = true
            v.layer?.cornerRadius = 10
            v.layer?.masksToBounds = true
            v.layer?.borderWidth = 1
            v.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
            v.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
            v.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
            v.layer?.shadowOpacity = 0.35
            v.layer?.shadowRadius = 8
            v.layer?.shadowOffset = .zero
            return v
        }()

        /// 关闭按钮
        private let closeButton: NSButton = {
            let cfg = NSImage.SymbolConfiguration(pointSize: 8, weight: .semibold)
            let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")?
                .withSymbolConfiguration(cfg)
                ?? NSImage(size: NSSize(width: 18, height: 18))
            let btn = NSButton(image: img, target: nil, action: nil)
            btn.isBordered = false
            btn.bezelStyle = .regularSquare
            btn.imageScaling = .scaleProportionallyDown
            btn.contentTintColor = NSColor.white.withAlphaComponent(0.92)
            btn.toolTip = "Close"
            return btn
        }()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            self.wantsLayer = true
            self.layer?.cornerRadius = 12
            self.layer?.masksToBounds = true
            self.layer?.borderWidth = 1
            self.layer?.borderColor = NSColor.black.withAlphaComponent(0.18).cgColor
            self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.02).cgColor

            // 配置拖动句柄
            self.dragHandle.translatesAutoresizingMaskIntoConstraints = false
            self.dragHandle.wantsLayer = true
            self.dragHandle.layer?.backgroundColor = NSColor.clear.cgColor
            self.addSubview(self.dragHandle)

            // 配置调整大小句柄
            self.resizeHandle.translatesAutoresizingMaskIntoConstraints = false
            self.resizeHandle.wantsLayer = true
            self.resizeHandle.layer?.backgroundColor = NSColor.clear.cgColor
            self.addSubview(self.resizeHandle)

            // 配置关闭按钮背景
            self.closeBackground.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(self.closeBackground)

            // 配置关闭按钮
            self.closeButton.translatesAutoresizingMaskIntoConstraints = false
            self.closeButton.target = self
            self.closeButton.action = #selector(self.handleClose)
            self.addSubview(self.closeButton)

            // 设置布局约束
            NSLayoutConstraint.activate([
                // 拖动句柄约束
                self.dragHandle.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                self.dragHandle.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.dragHandle.topAnchor.constraint(equalTo: self.topAnchor),
                self.dragHandle.heightAnchor.constraint(equalToConstant: 30),

                // 关闭按钮背景约束
                self.closeBackground.centerXAnchor.constraint(equalTo: self.closeButton.centerXAnchor),
                self.closeBackground.centerYAnchor.constraint(equalTo: self.closeButton.centerYAnchor),
                self.closeBackground.widthAnchor.constraint(equalToConstant: 20),
                self.closeBackground.heightAnchor.constraint(equalToConstant: 20),

                // 关闭按钮约束
                self.closeButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -8),
                self.closeButton.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                self.closeButton.widthAnchor.constraint(equalToConstant: 16),
                self.closeButton.heightAnchor.constraint(equalToConstant: 16),

                // 调整大小句柄约束
                self.resizeHandle.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                self.resizeHandle.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                self.resizeHandle.widthAnchor.constraint(equalToConstant: 18),
                self.resizeHandle.heightAnchor.constraint(equalToConstant: 18),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        /// 命中测试，当控制界面隐藏时不拦截鼠标事件
        override func hitTest(_ point: NSPoint) -> NSView? {
            // 当控制界面隐藏时，不拦截任何鼠标事件（让 WKWebView 接收它们）
            guard self.alphaValue > 0.02 else { return nil }

            if self.closeButton.frame.contains(point) { return self.closeButton }
            if self.dragHandle.frame.contains(point) { return self.dragHandle }
            if self.resizeHandle.frame.contains(point) { return self.resizeHandle }
            return nil
        }

        /// 处理关闭按钮点击事件
        @objc private func handleClose() {
            self.onClose?()
        }
    }

    /// 鼠标进入视图时显示控制界面
    override func mouseEntered(with _: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.chrome.animator().alphaValue = 1  // 显示控制界面
        }
    }

    /// 鼠标退出视图时隐藏控制界面
    override func mouseExited(with _: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.chrome.animator().alphaValue = 0  // 隐藏控制界面
        }
    }
}

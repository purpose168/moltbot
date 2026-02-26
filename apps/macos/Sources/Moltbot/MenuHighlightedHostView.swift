import AppKit
import SwiftUI

/// 高亮菜单项主机视图
/// 当鼠标悬停时显示高亮效果的菜单项容器
final class HighlightedMenuItemHostView: NSView {
    private var baseView: AnyView                    // 基础视图
    private let hosting: NSHostingView<AnyView>      // 托管视图
    private var targetWidth: CGFloat                 // 目标宽度
    private var tracking: NSTrackingArea?           // 跟踪区域
    private var hovered = false {                    // 是否悬停
        didSet { self.updateHighlight() }
    }

    /// 初始化方法
    /// - Parameters:
    ///   - rootView: 根视图
    ///   - width: 目标宽度
    init(rootView: AnyView, width: CGFloat) {
        self.baseView = rootView
        self.hosting = NSHostingView(rootView: AnyView(rootView.environment(\.menuItemHighlighted, false)))
        self.targetWidth = max(1, width)
        super.init(frame: .zero)

        self.addSubview(self.hosting)
        self.hosting.autoresizingMask = [.width, .height]
        self.updateSizing()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 返回内容大小
    override var intrinsicContentSize: NSSize {
        let size = self.hosting.fittingSize
        return NSSize(width: self.targetWidth, height: size.height)
    }

    /// 更新跟踪区域
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            self.removeTrackingArea(tracking)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect,
        ]
        let area = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(area)
        self.tracking = area
    }

    /// 鼠标进入事件
    override func mouseEntered(with event: NSEvent) {
        _ = event
        self.hovered = true
    }

    /// 鼠标退出事件
    override func mouseExited(with event: NSEvent) {
        _ = event
        self.hovered = false
    }

    /// 布局更新
    override func layout() {
        super.layout()
        self.hosting.frame = self.bounds
    }

    /// 绘制视图
    override func draw(_ dirtyRect: NSRect) {
        if self.hovered {
            NSColor.selectedContentBackgroundColor.setFill()
            self.bounds.fill()
        }
        super.draw(dirtyRect)
    }

    /// 更新根视图
    /// - Parameters:
    ///   - rootView: 新的根视图
    ///   - width: 新的目标宽度
    func update(rootView: AnyView, width: CGFloat) {
        self.baseView = rootView
        self.targetWidth = max(1, width)
        self.updateHighlight()
    }

    /// 更新高亮状态
    private func updateHighlight() {
        self.hosting.rootView = AnyView(self.baseView.environment(\.menuItemHighlighted, self.hovered))
        self.updateSizing()
        self.needsDisplay = true
    }

    /// 更新尺寸
    private func updateSizing() {
        let width = max(1, self.targetWidth)
        self.hosting.frame.size.width = width
        let size = self.hosting.fittingSize
        self.frame = NSRect(origin: .zero, size: NSSize(width: width, height: size.height))
        self.invalidateIntrinsicContentSize()
    }
}

/// 菜单托管高亮项
/// 用于在菜单中显示带高亮效果的视图
struct MenuHostedHighlightedItem: NSViewRepresentable {
    let width: CGFloat        // 宽度
    let rootView: AnyView     // 根视图

    /// 创建 NSView
    func makeNSView(context _: Context) -> HighlightedMenuItemHostView {
        HighlightedMenuItemHostView(rootView: self.rootView, width: self.width)
    }

    /// 更新 NSView
    func updateNSView(_ nsView: HighlightedMenuItemHostView, context _: Context) {
        nsView.update(rootView: self.rootView, width: self.width)
    }
}

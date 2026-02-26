import AppKit

/// 窗口位置管理器
/// 提供各种窗口定位方法，包括居中、右上角、锚定下方等
@MainActor
enum WindowPlacement {
    /// 在指定屏幕上创建居中的窗口框架
    /// - Parameters:
    ///   - size: 窗口大小
    ///   - screen: 目标屏幕，默认为主屏幕
    /// - Returns: 居中的窗口框架
    static func centeredFrame(size: NSSize, on screen: NSScreen? = NSScreen.main) -> NSRect {
        let bounds = (screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero)
        return self.centeredFrame(size: size, in: bounds)
    }

    /// 在指定屏幕上创建右上角的窗口框架
    /// - Parameters:
    ///   - size: 窗口大小
    ///   - padding: 边距
    ///   - screen: 目标屏幕，默认为主屏幕
    /// - Returns: 右上角的窗口框架
    static func topRightFrame(
        size: NSSize,
        padding: CGFloat,
        on screen: NSScreen? = NSScreen.main) -> NSRect
    {
        let bounds = (screen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero)
        return self.topRightFrame(size: size, padding: padding, in: bounds)
    }

    /// 在指定边界内创建居中的窗口框架
    /// - Parameters:
    ///   - size: 窗口大小
    ///   - bounds: 边界矩形
    /// - Returns: 居中的窗口框架
    static func centeredFrame(size: NSSize, in bounds: NSRect) -> NSRect {
        if bounds == .zero {
            return NSRect(origin: .zero, size: size)
        }

        let clampedWidth = min(size.width, bounds.width)
        let clampedHeight = min(size.height, bounds.height)

        let x = round(bounds.minX + (bounds.width - clampedWidth) / 2)
        let y = round(bounds.minY + (bounds.height - clampedHeight) / 2)
        return NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    /// 在指定边界内创建右上角的窗口框架
    /// - Parameters:
    ///   - size: 窗口大小
    ///   - padding: 边距
    ///   - bounds: 边界矩形
    /// - Returns: 右上角的窗口框架
    static func topRightFrame(size: NSSize, padding: CGFloat, in bounds: NSRect) -> NSRect {
        if bounds == .zero {
            return NSRect(origin: .zero, size: size)
        }

        let clampedWidth = min(size.width, bounds.width)
        let clampedHeight = min(size.height, bounds.height)

        let x = round(bounds.maxX - clampedWidth - padding)
        let y = round(bounds.maxY - clampedHeight - padding)
        return NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    /// 创建锚定在指定框架下方的窗口框架
    /// - Parameters:
    ///   - size: 窗口大小
    ///   - anchor: 锚点框架
    ///   - padding: 边距
    ///   - bounds: 边界矩形
    /// - Returns: 锚定在锚点下方的窗口框架
    static func anchoredBelowFrame(size: NSSize, anchor: NSRect, padding: CGFloat, in bounds: NSRect) -> NSRect {
        if bounds == .zero {
            let x = round(anchor.midX - size.width / 2)
            let y = round(anchor.minY - size.height - padding)
            return NSRect(x: x, y: y, width: size.width, height: size.height)
        }

        let clampedWidth = min(size.width, bounds.width)
        let clampedHeight = min(size.height, bounds.height)

        let desiredX = round(anchor.midX - clampedWidth / 2)
        let desiredY = round(anchor.minY - clampedHeight - padding)

        let maxX = bounds.maxX - clampedWidth
        let maxY = bounds.maxY - clampedHeight

        let x = maxX >= bounds.minX ? min(max(desiredX, bounds.minX), maxX) : bounds.minX
        let y = maxY >= bounds.minY ? min(max(desiredY, bounds.minY), maxY) : bounds.minY

        return NSRect(x: x, y: y, width: clampedWidth, height: clampedHeight)
    }

    /// 确保窗口在屏幕可见区域内
    /// - Parameters:
    ///   - window: 要检查的窗口
    ///   - defaultSize: 默认窗口大小
    ///   - fallback: 备用位置计算函数
    static func ensureOnScreen(
        window: NSWindow,
        defaultSize: NSSize,
        fallback: ((NSScreen?) -> NSRect)? = nil)
    {
        let frame = window.frame
        let targetScreens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap(\.self) : NSScreen.screens
        let isVisibleSomewhere = targetScreens.contains { screen in
            frame.intersects(screen.visibleFrame.insetBy(dx: 12, dy: 12))
        }

        if isVisibleSomewhere { return }

        let screen = NSScreen.main ?? targetScreens.first
        let next = fallback?(screen) ?? self.centeredFrame(size: defaultSize, on: screen)
        window.setFrame(next, display: false)
    }
}

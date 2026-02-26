import AppKit

/// Canvas窗口相关的日志记录器
let canvasWindowLogger = Logger(subsystem: "bot.molt", category: "Canvas")

/// Canvas布局常量枚举
/// 定义了Canvas窗口和面板的各种尺寸和间距常量
enum CanvasLayout {
    /// 面板默认尺寸
    static let panelSize = NSSize(width: 520, height: 680)
    /// 窗口默认尺寸
    static let windowSize = NSSize(width: 1120, height: 840)
    /// 锚点padding
    static let anchorPadding: CGFloat = 8
    /// 默认padding
    static let defaultPadding: CGFloat = 10
    /// 面板最小尺寸
    static let minPanelSize = NSSize(width: 360, height: 360)
}

/// Canvas面板类
/// 继承自NSPanel，重写了相关属性以确保面板可以成为key和main窗口
final class CanvasPanel: NSPanel {
    /// 允许面板成为key窗口
    override var canBecomeKey: Bool { true }
    /// 允许面板成为main窗口
    override var canBecomeMain: Bool { true }
}

/// Canvas展示方式枚举
/// 定义了Canvas的两种展示形式：窗口和面板
enum CanvasPresentation {
    /// 窗口模式
    case window
    /// 面板模式，带有锚点提供者
    case panel(anchorProvider: () -> NSRect?)

    /// 判断是否为面板模式
    var isPanel: Bool {
        if case .panel = self {
            return true
        }
        return false
    }
}

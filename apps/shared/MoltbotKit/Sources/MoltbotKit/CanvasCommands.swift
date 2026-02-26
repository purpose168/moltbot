import Foundation

/// Moltbot 画布命令枚举
///
/// 定义了与画布交互的各种命令类型，用于控制画布的显示、隐藏、导航等操作
/// 遵循 String、Codable 和 Sendable 协议，支持编码解码和并发安全
public enum MoltbotCanvasCommand: String, Codable, Sendable {
    /// 显示画布
    /// 对应命令字符串: "canvas.present"
    case present = "canvas.present"
    
    /// 隐藏画布
    /// 对应命令字符串: "canvas.hide"
    case hide = "canvas.hide"
    
    /// 导航到指定 URL
    /// 对应命令字符串: "canvas.navigate"
    case navigate = "canvas.navigate"
    
    /// 执行 JavaScript 代码
    /// 对应命令字符串: "canvas.eval"
    case evalJS = "canvas.eval"
    
    /// 捕获画布快照
    /// 对应命令字符串: "canvas.snapshot"
    case snapshot = "canvas.snapshot"
}

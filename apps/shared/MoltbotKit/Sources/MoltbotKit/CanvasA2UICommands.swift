import Foundation

/// Canvas A2UI 命令枚举，定义了与设备画布交互的命令类型
/// A2UI (Adaptive Adaptive User Interface) 是一种自适应用户界面技术
public enum MoltbotCanvasA2UICommand: String, Codable, Sendable {
    /// 在设备画布上渲染 A2UI 内容
    case push = "canvas.a2ui.push"
    /// 发送 JSONL 时 `push` 的旧别名
    case pushJSONL = "canvas.a2ui.pushJSONL"
    /// 重置 A2UI 渲染器状态
    case reset = "canvas.a2ui.reset"
}

/// `push` 命令的参数结构体
/// 用于向设备画布推送 A2UI 内容的消息数组
public struct MoltbotCanvasA2UIPushParams: Codable, Sendable, Equatable {
    /// A2UI 消息数组，使用 AnyCodable 类型以支持多种数据结构
    public var messages: [AnyCodable]

    /// 初始化方法
    /// - Parameter messages: A2UI 消息数组
    public init(messages: [AnyCodable]) {
        self.messages = messages
    }
}

/// `pushJSONL` 命令的参数结构体
/// 用于以 JSONL 格式向设备画布推送 A2UI 内容
public struct MoltbotCanvasA2UIPushJSONLParams: Codable, Sendable, Equatable {
    /// JSONL 格式的 A2UI 内容字符串
    /// JSONL (JSON Lines) 是一种每行一个 JSON 对象的格式
    public var jsonl: String

    /// 初始化方法
    /// - Parameter jsonl: JSONL 格式的 A2UI 内容字符串
    public init(jsonl: String) {
        self.jsonl = jsonl
    }
}

import Foundation

/// 位置权限模式枚举
/// 
/// 定义了Moltbot应用的位置权限使用模式，对应iOS/macOS的位置权限设置选项
/// 
/// - off: 不使用位置权限
/// - whileUsing: 仅在使用应用时使用位置权限
/// - always: 始终使用位置权限（包括后台）
public enum MoltbotLocationMode: String, Codable, Sendable, CaseIterable {
    case off          // 关闭位置权限
    case whileUsing   // 仅在使用时
    case always       // 始终允许
}

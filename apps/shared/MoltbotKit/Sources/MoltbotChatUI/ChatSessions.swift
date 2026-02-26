import Foundation

/// Moltbot 聊天会话默认设置结构体
/// 包含模型和上下文令牌等默认配置
public struct MoltbotChatSessionsDefaults: Codable, Sendable {
    /// 模型名称
    public let model: String?
    /// 上下文令牌数量
    public let contextTokens: Int?
}

/// Moltbot 聊天会话条目结构体
/// 表示单个聊天会话的详细信息
public struct MoltbotChatSessionEntry: Codable, Identifiable, Sendable, Hashable {
    /// 会话唯一标识符，使用 key 作为 id
    public var id: String { self.key }

    /// 会话唯一键值
    public let key: String
    /// 会话类型
    public let kind: String?
    /// 会话显示名称
    public let displayName: String?
    /// 会话界面类型
    public let surface: String?
    /// 会话主题
    public let subject: String?
    /// 会话房间
    public let room: String?
    /// 会话空间
    public let space: String?
    /// 会话最后更新时间戳
    public let updatedAt: Double?
    /// 会话 ID
    public let sessionId: String?

    /// 是否为系统发送
    public let systemSent: Bool?
    /// 上次运行是否被中止
    public let abortedLastRun: Bool?
    /// 思考级别
    public let thinkingLevel: String?
    /// 详细级别
    public let verboseLevel: String?

    /// 输入令牌数量
    public let inputTokens: Int?
    /// 输出令牌数量
    public let outputTokens: Int?
    /// 总令牌数量
    public let totalTokens: Int?

    /// 使用的模型名称
    public let model: String?
    /// 上下文令牌数量
    public let contextTokens: Int?
}

/// Moltbot 聊天会话列表响应结构体
/// 包含会话列表及其相关信息
public struct MoltbotChatSessionsListResponse: Codable, Sendable {
    /// 响应时间戳
    public let ts: Double?
    /// 路径
    public let path: String?
    /// 会话数量
    public let count: Int?
    /// 默认设置
    public let defaults: MoltbotChatSessionsDefaults?
    /// 会话列表
    public let sessions: [MoltbotChatSessionEntry]
}

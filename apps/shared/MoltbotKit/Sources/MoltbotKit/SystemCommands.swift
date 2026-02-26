import Foundation

/// 系统命令枚举，定义了Moltbot可执行的系统级命令
public enum MoltbotSystemCommand: String, Codable, Sendable {
    /// 运行系统命令
    case run = "system.run"
    /// 查找可执行文件路径
    case which = "system.which"
    /// 发送系统通知
    case notify = "system.notify"
    /// 获取执行权限设置
    case execApprovalsGet = "system.execApprovals.get"
    /// 设置执行权限
    case execApprovalsSet = "system.execApprovals.set"
}

/// 通知优先级枚举
public enum MoltbotNotificationPriority: String, Codable, Sendable {
    /// 被动通知，不会打断用户
    case passive
    /// 主动通知，会显示在屏幕上
    case active
    /// 时间敏感通知，会立即显示并可能带有声音
    case timeSensitive
}

/// 通知传递方式枚举
public enum MoltbotNotificationDelivery: String, Codable, Sendable {
    /// 系统默认方式
    case system
    /// 覆盖显示
    case overlay
    /// 自动选择最佳方式
    case auto
}

/// 运行系统命令的参数结构体
public struct MoltbotSystemRunParams: Codable, Sendable, Equatable {
    /// 命令参数数组，例如 ["ls", "-la"]
    public var command: [String]
    /// 原始命令字符串，保留用户输入的完整命令
    public var rawCommand: String?
    /// 工作目录路径
    public var cwd: String?
    /// 环境变量字典
    public var env: [String: String]?
    /// 命令执行超时时间（毫秒）
    public var timeoutMs: Int?
    /// 是否需要屏幕录制
    public var needsScreenRecording: Bool?
    /// 代理ID
    public var agentId: String?
    /// 会话密钥
    public var sessionKey: String?
    /// 是否已批准执行
    public var approved: Bool?
    /// 批准决策信息
    public var approvalDecision: String?

    /// 初始化函数
    /// - Parameters:
    ///   - command: 命令参数数组
    ///   - rawCommand: 原始命令字符串
    ///   - cwd: 工作目录路径
    ///   - env: 环境变量字典
    ///   - timeoutMs: 执行超时时间（毫秒）
    ///   - needsScreenRecording: 是否需要屏幕录制
    ///   - agentId: 代理ID
    ///   - sessionKey: 会话密钥
    ///   - approved: 是否已批准执行
    ///   - approvalDecision: 批准决策信息
    public init(
        command: [String],
        rawCommand: String? = nil,
        cwd: String? = nil,
        env: [String: String]? = nil,
        timeoutMs: Int? = nil,
        needsScreenRecording: Bool? = nil,
        agentId: String? = nil,
        sessionKey: String? = nil,
        approved: Bool? = nil,
        approvalDecision: String? = nil)
    {
        self.command = command
        self.rawCommand = rawCommand
        self.cwd = cwd
        self.env = env
        self.timeoutMs = timeoutMs
        self.needsScreenRecording = needsScreenRecording
        self.agentId = agentId
        self.sessionKey = sessionKey
        self.approved = approved
        self.approvalDecision = approvalDecision
    }
}

/// 查找可执行文件路径的参数结构体
public struct MoltbotSystemWhichParams: Codable, Sendable, Equatable {
    /// 要查找的可执行文件名数组
    public var bins: [String]

    /// 初始化函数
    /// - Parameter bins: 要查找的可执行文件名数组
    public init(bins: [String]) {
        self.bins = bins
    }
}

/// 发送系统通知的参数结构体
public struct MoltbotSystemNotifyParams: Codable, Sendable, Equatable {
    /// 通知标题
    public var title: String
    /// 通知正文
    public var body: String
    /// 通知声音
    public var sound: String?
    /// 通知优先级
    public var priority: MoltbotNotificationPriority?
    /// 通知传递方式
    public var delivery: MoltbotNotificationDelivery?

    /// 初始化函数
    /// - Parameters:
    ///   - title: 通知标题
    ///   - body: 通知正文
    ///   - sound: 通知声音
    ///   - priority: 通知优先级
    ///   - delivery: 通知传递方式
    public init(
        title: String,
        body: String,
        sound: String? = nil,
        priority: MoltbotNotificationPriority? = nil,
        delivery: MoltbotNotificationDelivery? = nil)
    {
        self.title = title
        self.body = body
        self.sound = sound
        self.priority = priority
        self.delivery = delivery
    }
}

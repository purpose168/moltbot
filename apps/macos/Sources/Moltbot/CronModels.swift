import Foundation

/// Cron 会话目标
/// 
/// 表示 Cron 作业的会话目标
enum CronSessionTarget: String, CaseIterable, Identifiable, Codable {
    /// 主会话
    case main
    /// 隔离会话
    case isolated

    /// 标识符
    var id: String { self.rawValue }
}

/// Cron 唤醒模式
/// 
/// 表示 Cron 作业的唤醒模式
enum CronWakeMode: String, CaseIterable, Identifiable, Codable {
    /// 立即
    case now
    /// 下次心跳
    case nextHeartbeat = "next-heartbeat"

    /// 标识符
    var id: String { self.rawValue }
}

/// Cron 调度
/// 
/// 表示 Cron 作业的调度方式
enum CronSchedule: Codable, Equatable {
    /// 在特定时间运行
    case at(atMs: Int)
    /// 按间隔重复运行
    case every(everyMs: Int, anchorMs: Int?)
    /// 使用 Cron 表达式运行
    case cron(expr: String, tz: String?)

    /// 编码键
    enum CodingKeys: String, CodingKey { case kind, atMs, everyMs, anchorMs, expr, tz }

    /// 调度类型
    var kind: String {
        switch self {
        case .at: "at"
        case .every: "every"
        case .cron: "cron"
        }
    }

    /// 从解码器初始化
    /// - Parameter decoder: 解码器
    /// - Throws: 解码错误
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "at":
            self = try .at(atMs: container.decode(Int.self, forKey: .atMs))
        case "every":
            self = try .every(
                everyMs: container.decode(Int.self, forKey: .everyMs),
                anchorMs: container.decodeIfPresent(Int.self, forKey: .anchorMs))
        case "cron":
            self = try .cron(
                expr: container.decode(String.self, forKey: .expr),
                tz: container.decodeIfPresent(String.self, forKey: .tz))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "未知的调度类型: \(kind)")
        }
    }

    /// 编码到编码器
    /// - Parameter encoder: 编码器
    /// - Throws: 编码错误
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.kind, forKey: .kind)
        switch self {
        case let .at(atMs):
            try container.encode(atMs, forKey: .atMs)
        case let .every(everyMs, anchorMs):
            try container.encode(everyMs, forKey: .everyMs)
            try container.encodeIfPresent(anchorMs, forKey: .anchorMs)
        case let .cron(expr, tz):
            try container.encode(expr, forKey: .expr)
            try container.encodeIfPresent(tz, forKey: .tz)
        }
    }
}

/// Cron 有效载荷
/// 
/// 表示 Cron 作业的有效载荷
enum CronPayload: Codable, Equatable {
    /// 系统事件
    case systemEvent(text: String)
    /// 代理回合
    case agentTurn(
        message: String,
        thinking: String?,
        timeoutSeconds: Int?,
        deliver: Bool?,
        channel: String?,
        to: String?,
        bestEffortDeliver: Bool?)

    /// 编码键
    enum CodingKeys: String, CodingKey {
        case kind, text, message, thinking, timeoutSeconds, deliver, channel, provider, to, bestEffortDeliver
    }

    /// 有效载荷类型
    var kind: String {
        switch self {
        case .systemEvent: "systemEvent"
        case .agentTurn: "agentTurn"
        }
    }

    /// 从解码器初始化
    /// - Parameter decoder: 解码器
    /// - Throws: 解码错误
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "systemEvent":
            self = try .systemEvent(text: container.decode(String.self, forKey: .text))
        case "agentTurn":
            self = try .agentTurn(
                message: container.decode(String.self, forKey: .message),
                thinking: container.decodeIfPresent(String.self, forKey: .thinking),
                timeoutSeconds: container.decodeIfPresent(Int.self, forKey: .timeoutSeconds),
                deliver: container.decodeIfPresent(Bool.self, forKey: .deliver),
                channel: container.decodeIfPresent(String.self, forKey: .channel)
                    ?? container.decodeIfPresent(String.self, forKey: .provider),
                to: container.decodeIfPresent(String.self, forKey: .to),
                bestEffortDeliver: container.decodeIfPresent(Bool.self, forKey: .bestEffortDeliver))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "未知的有效载荷类型: \(kind)")
        }
    }

    /// 编码到编码器
    /// - Parameter encoder: 编码器
    /// - Throws: 编码错误
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.kind, forKey: .kind)
        switch self {
        case let .systemEvent(text):
            try container.encode(text, forKey: .text)
        case let .agentTurn(message, thinking, timeoutSeconds, deliver, channel, to, bestEffortDeliver):
            try container.encode(message, forKey: .message)
            try container.encodeIfPresent(thinking, forKey: .thinking)
            try container.encodeIfPresent(timeoutSeconds, forKey: .timeoutSeconds)
            try container.encodeIfPresent(deliver, forKey: .deliver)
            try container.encodeIfPresent(channel, forKey: .channel)
            try container.encodeIfPresent(to, forKey: .to)
            try container.encodeIfPresent(bestEffortDeliver, forKey: .bestEffortDeliver)
        }
    }
}

/// Cron 隔离设置
/// 
/// 表示 Cron 作业的隔离设置
struct CronIsolation: Codable, Equatable {
    /// 发布到主会话的前缀
    var postToMainPrefix: String?
}

/// Cron 作业状态
/// 
/// 表示 Cron 作业的状态
struct CronJobState: Codable, Equatable {
    /// 下次运行时间（毫秒）
    var nextRunAtMs: Int?
    /// 运行中时间（毫秒）
    var runningAtMs: Int?
    /// 上次运行时间（毫秒）
    var lastRunAtMs: Int?
    /// 上次状态
    var lastStatus: String?
    /// 上次错误
    var lastError: String?
    /// 上次持续时间（毫秒）
    var lastDurationMs: Int?
}

/// Cron 作业
/// 
/// 表示一个 Cron 作业
struct CronJob: Identifiable, Codable, Equatable {
    /// 作业 ID
    let id: String
    /// 代理 ID
    let agentId: String?
    /// 作业名称
    var name: String
    /// 作业描述
    var description: String?
    /// 是否启用
    var enabled: Bool
    /// 运行后是否删除
    var deleteAfterRun: Bool?
    /// 创建时间（毫秒）
    let createdAtMs: Int
    /// 更新时间（毫秒）
    let updatedAtMs: Int
    /// 调度
    let schedule: CronSchedule
    /// 会话目标
    let sessionTarget: CronSessionTarget
    /// 唤醒模式
    let wakeMode: CronWakeMode
    /// 有效载荷
    let payload: CronPayload
    /// 隔离设置
    let isolation: CronIsolation?
    /// 状态
    let state: CronJobState

    /// 显示名称
    var displayName: String {
        let trimmed = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名作业" : trimmed
    }

    /// 下次运行日期
    var nextRunDate: Date? {
        guard let ms = self.state.nextRunAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }

    /// 上次运行日期
    var lastRunDate: Date? {
        guard let ms = self.state.lastRunAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
    }
}

/// Cron 事件
/// 
/// 表示 Cron 相关的事件
struct CronEvent: Codable, Sendable {
    /// 作业 ID
    let jobId: String
    /// 操作
    let action: String
    /// 运行时间（毫秒）
    let runAtMs: Int?
    /// 持续时间（毫秒）
    let durationMs: Int?
    /// 状态
    let status: String?
    /// 错误
    let error: String?
    /// 摘要
    let summary: String?
    /// 下次运行时间（毫秒）
    let nextRunAtMs: Int?
}

/// Cron 运行日志条目
/// 
/// 表示 Cron 作业的运行日志条目
struct CronRunLogEntry: Codable, Identifiable, Sendable {
    /// 标识符
    var id: String { "\(self.jobId)-\(self.ts)" }

    /// 时间戳
    let ts: Int
    /// 作业 ID
    let jobId: String
    /// 操作
    let action: String
    /// 状态
    let status: String?
    /// 错误
    let error: String?
    /// 摘要
    let summary: String?
    /// 运行时间（毫秒）
    let runAtMs: Int?
    /// 持续时间（毫秒）
    let durationMs: Int?
    /// 下次运行时间（毫秒）
    let nextRunAtMs: Int?

    /// 日期
    var date: Date { Date(timeIntervalSince1970: TimeInterval(self.ts) / 1000) }
    /// 运行日期
    var runDate: Date? {
        guard let runAtMs else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(runAtMs) / 1000)
    }
}

/// Cron 列表响应
/// 
/// 表示 Cron 作业列表的响应
struct CronListResponse: Codable {
    /// 作业列表
    let jobs: [CronJob]
}

/// Cron 运行响应
/// 
/// 表示 Cron 运行记录的响应
struct CronRunsResponse: Codable {
    /// 日志条目列表
    let entries: [CronRunLogEntry]
}

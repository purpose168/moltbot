import MoltbotProtocol
import Foundation
import Observation

/// 渠道状态快照结构体，用于存储所有聊天渠道的状态信息
struct ChannelsStatusSnapshot: Codable {
    /// WhatsApp 自身信息结构体
    struct WhatsAppSelf: Codable {
        let e164: String? // 国际电话号码格式
        let jid: String? // WhatsApp 唯一标识符
    }

    /// WhatsApp 断开连接信息结构体
    struct WhatsAppDisconnect: Codable {
        let at: Double // 断开时间戳
        let status: Int? // 状态码
        let error: String? // 错误信息
        let loggedOut: Bool? // 是否已登出
    }

    /// WhatsApp 状态结构体
    struct WhatsAppStatus: Codable {
        let configured: Bool // 是否已配置
        let linked: Bool // 是否已关联
        let authAgeMs: Double? // 认证年龄（毫秒）
        let `self`: WhatsAppSelf? // 自身信息
        let running: Bool // 是否运行中
        let connected: Bool // 是否已连接
        let lastConnectedAt: Double? // 最后连接时间
        let lastDisconnect: WhatsAppDisconnect? // 最后断开信息
        let reconnectAttempts: Int // 重连尝试次数
        let lastMessageAt: Double? // 最后消息时间
        let lastEventAt: Double? // 最后事件时间
        let lastError: String? // 最后错误信息
    }

    /// Telegram 机器人信息结构体
    struct TelegramBot: Codable {
        let id: Int? // 机器人ID
        let username: String? // 机器人用户名
    }

    /// Telegram Webhook 信息结构体
    struct TelegramWebhook: Codable {
        let url: String? // Webhook URL
        let hasCustomCert: Bool? // 是否有自定义证书
    }

    /// Telegram 探测信息结构体
    struct TelegramProbe: Codable {
        let ok: Bool // 是否成功
        let status: Int? // 状态码
        let error: String? // 错误信息
        let elapsedMs: Double? // 耗时（毫秒）
        let bot: TelegramBot? // 机器人信息
        let webhook: TelegramWebhook? // Webhook 信息
    }

    /// Telegram 状态结构体
    struct TelegramStatus: Codable {
        let configured: Bool // 是否已配置
        let tokenSource: String? // token 来源
        let running: Bool // 是否运行中
        let mode: String? // 模式
        let lastStartAt: Double? // 最后启动时间
        let lastStopAt: Double? // 最后停止时间
        let lastError: String? // 最后错误信息
        let probe: TelegramProbe? // 探测信息
        let lastProbeAt: Double? // 最后探测时间
    }

    /// Discord 机器人信息结构体
    struct DiscordBot: Codable {
        let id: String? // 机器人ID
        let username: String? // 机器人用户名
    }

    /// Discord 探测信息结构体
    struct DiscordProbe: Codable {
        let ok: Bool // 是否成功
        let status: Int? // 状态码
        let error: String? // 错误信息
        let elapsedMs: Double? // 耗时（毫秒）
        let bot: DiscordBot? // 机器人信息
    }

    /// Discord 状态结构体
    struct DiscordStatus: Codable {
        let configured: Bool // 是否已配置
        let tokenSource: String? // token 来源
        let running: Bool // 是否运行中
        let lastStartAt: Double? // 最后启动时间
        let lastStopAt: Double? // 最后停止时间
        let lastError: String? // 最后错误信息
        let probe: DiscordProbe? // 探测信息
        let lastProbeAt: Double? // 最后探测时间
    }

    /// Google Chat 探测信息结构体
    struct GoogleChatProbe: Codable {
        let ok: Bool // 是否成功
        let status: Int? // 状态码
        let error: String? // 错误信息
        let elapsedMs: Double? // 耗时（毫秒）
    }

    /// Google Chat 状态结构体
    struct GoogleChatStatus: Codable {
        let configured: Bool // 是否已配置
        let credentialSource: String? // 凭证来源
        let audienceType: String? // 受众类型
        let audience: String? // 受众
        let webhookPath: String? // Webhook 路径
        let webhookUrl: String? // Webhook URL
        let running: Bool // 是否运行中
        let lastStartAt: Double? // 最后启动时间
        let lastStopAt: Double? // 最后停止时间
        let lastError: String? // 最后错误信息
        let probe: GoogleChatProbe? // 探测信息
        let lastProbeAt: Double? // 最后探测时间
    }

    /// Signal 探测信息结构体
    struct SignalProbe: Codable {
        let ok: Bool // 是否成功
        let status: Int? // 状态码
        let error: String? // 错误信息
        let elapsedMs: Double? // 耗时（毫秒）
        let version: String? // 版本信息
    }

    /// Signal 状态结构体
    struct SignalStatus: Codable {
        let configured: Bool // 是否已配置
        let baseUrl: String // 基础 URL
        let running: Bool // 是否运行中
        let lastStartAt: Double? // 最后启动时间
        let lastStopAt: Double? // 最后停止时间
        let lastError: String? // 最后错误信息
        let probe: SignalProbe? // 探测信息
        let lastProbeAt: Double? // 最后探测时间
    }

    /// iMessage 探测信息结构体
    struct IMessageProbe: Codable {
        let ok: Bool // 是否成功
        let error: String? // 错误信息
    }

    /// iMessage 状态结构体
    struct IMessageStatus: Codable {
        let configured: Bool // 是否已配置
        let running: Bool // 是否运行中
        let lastStartAt: Double? // 最后启动时间
        let lastStopAt: Double? // 最后停止时间
        let lastError: String? // 最后错误信息
        let cliPath: String? // 命令行工具路径
        let dbPath: String? // 数据库路径
        let probe: IMessageProbe? // 探测信息
        let lastProbeAt: Double? // 最后探测时间
    }

    /// 渠道账户快照结构体
    struct ChannelAccountSnapshot: Codable {
        let accountId: String // 账户ID
        let name: String? // 账户名称
        let enabled: Bool? // 是否启用
        let configured: Bool? // 是否已配置
        let linked: Bool? // 是否已关联
        let running: Bool? // 是否运行中
        let connected: Bool? // 是否已连接
        let reconnectAttempts: Int? // 重连尝试次数
        let lastConnectedAt: Double? // 最后连接时间
        let lastError: String? // 最后错误信息
        let lastStartAt: Double? // 最后启动时间
        let lastStopAt: Double? // 最后停止时间
        let lastInboundAt: Double? // 最后接收消息时间
        let lastOutboundAt: Double? // 最后发送消息时间
        let lastProbeAt: Double? // 最后探测时间
        let mode: String? // 模式
        let dmPolicy: String? // 私聊策略
        let allowFrom: [String]? // 允许来源列表
        let tokenSource: String? // token 来源
        let botTokenSource: String? // 机器人 token 来源
        let appTokenSource: String? // 应用 token 来源
        let baseUrl: String? // 基础 URL
        let allowUnmentionedGroups: Bool? // 是否允许未提及的群组
        let cliPath: String? // 命令行工具路径
        let dbPath: String? // 数据库路径
        let port: Int? // 端口
        let probe: AnyCodable? // 探测信息
        let audit: AnyCodable? // 审计信息
        let application: AnyCodable? // 应用信息
    }

    /// 渠道 UI 元数据条目结构体
    struct ChannelUiMetaEntry: Codable {
        let id: String // 渠道ID
        let label: String // 渠道标签
        let detailLabel: String // 渠道详细标签
        let systemImage: String? // 系统图标
    }

    let ts: Double // 时间戳
    let channelOrder: [String] // 渠道顺序
    let channelLabels: [String: String] // 渠道标签映射
    let channelDetailLabels: [String: String]? // 渠道详细标签映射
    let channelSystemImages: [String: String]? // 渠道系统图标映射
    let channelMeta: [ChannelUiMetaEntry]? // 渠道元数据
    let channels: [String: AnyCodable] // 渠道状态映射
    let channelAccounts: [String: [ChannelAccountSnapshot]] // 渠道账户映射
    let channelDefaultAccountId: [String: String] // 渠道默认账户ID映射

    /// 解码指定渠道的状态信息
    /// - Parameters:
    ///   - id: 渠道ID
    ///   - type: 要解码的类型
    /// - Returns: 解码后的渠道状态信息，解码失败返回nil
    func decodeChannel<T: Decodable>(_ id: String, as type: T.Type) -> T? {
        guard let value = self.channels[id] else { return nil }
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            return nil
        }
    }
}

/// 配置快照结构体，用于存储配置信息和问题
struct ConfigSnapshot: Codable {
    /// 配置问题结构体
    struct Issue: Codable {
        let path: String // 问题路径
        let message: String // 问题消息
    }

    let path: String? // 配置文件路径
    let exists: Bool? // 配置文件是否存在
    let raw: String? // 原始配置内容
    let hash: String? // 配置哈希值
    let parsed: AnyCodable? // 解析后的配置
    let valid: Bool? // 配置是否有效
    let config: [String: AnyCodable]? // 配置映射
    let issues: [Issue]? // 配置问题列表
}

/// 渠道存储类，用于管理所有聊天渠道的状态和配置
@MainActor
@Observable
final class ChannelsStore {
    static let shared = ChannelsStore() // 单例实例

    var snapshot: ChannelsStatusSnapshot? // 渠道状态快照
    var lastError: String? // 最后错误信息
    var lastSuccess: Date? // 最后成功时间
    var isRefreshing = false // 是否正在刷新

    var whatsappLoginMessage: String? // WhatsApp 登录消息
    var whatsappLoginQrDataUrl: String? // WhatsApp 登录二维码数据URL
    var whatsappLoginConnected: Bool? // WhatsApp 登录是否已连接
    var whatsappBusy = false // WhatsApp 是否繁忙
    var telegramBusy = false // Telegram 是否繁忙

    var configStatus: String? // 配置状态
    var isSavingConfig = false // 是否正在保存配置
    var configSchemaLoading = false // 配置 schema 是否正在加载
    var configSchema: ConfigSchemaNode? // 配置 schema
    var configUiHints: [String: ConfigUiHint] = [:] // 配置 UI 提示
    var configDraft: [String: Any] = [:] // 配置草稿
    var configDirty = false // 配置是否已修改

    let interval: TimeInterval = 45 // 刷新间隔（秒）
    let isPreview: Bool // 是否为预览模式
    var pollTask: Task<Void, Never>? // 轮询任务
    var configRoot: [String: Any] = [:] // 配置根节点
    var configLoaded = false // 配置是否已加载

    /// 获取指定渠道的元数据条目
    /// - Parameter id: 渠道ID
    /// - Returns: 渠道元数据条目，不存在返回nil
    func channelMetaEntry(_ id: String) -> ChannelsStatusSnapshot.ChannelUiMetaEntry? {
        self.snapshot?.channelMeta?.first(where: { $0.id == id })
    }

    /// 解析渠道标签
    /// - Parameter id: 渠道ID
    /// - Returns: 渠道标签，如果没有则返回渠道ID
    func resolveChannelLabel(_ id: String) -> String {
        if let meta = self.channelMetaEntry(id), !meta.label.isEmpty {
            return meta.label
        }
        if let label = self.snapshot?.channelLabels[id], !label.isEmpty {
            return label
        }
        return id
    }

    /// 解析渠道详细标签
    /// - Parameter id: 渠道ID
    /// - Returns: 渠道详细标签，如果没有则返回渠道标签
    func resolveChannelDetailLabel(_ id: String) -> String {
        if let meta = self.channelMetaEntry(id), !meta.detailLabel.isEmpty {
            return meta.detailLabel
        }
        if let detail = self.snapshot?.channelDetailLabels?[id], !detail.isEmpty {
            return detail
        }
        return self.resolveChannelLabel(id)
    }

    /// 解析渠道系统图标
    /// - Parameter id: 渠道ID
    /// - Returns: 渠道系统图标，如果没有则返回默认图标
    func resolveChannelSystemImage(_ id: String) -> String {
        if let meta = self.channelMetaEntry(id), let symbol = meta.systemImage, !symbol.isEmpty {
            return symbol
        }
        if let symbol = self.snapshot?.channelSystemImages?[id], !symbol.isEmpty {
            return symbol
        }
        return "message"
    }

    /// 获取有序的渠道ID列表
    /// - Returns: 有序的渠道ID列表
    func orderedChannelIds() -> [String] {
        if let meta = self.snapshot?.channelMeta, !meta.isEmpty {
            return meta.map(\.id)
        }
        return self.snapshot?.channelOrder ?? []
    }

    /// 初始化渠道存储
    /// - Parameter isPreview: 是否为预览模式
    init(isPreview: Bool = ProcessInfo.processInfo.isPreview) {
        self.isPreview = isPreview
    }
}
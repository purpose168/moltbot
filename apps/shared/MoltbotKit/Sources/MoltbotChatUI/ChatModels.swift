import MoltbotKit
import Foundation

// 注意：保持此文件轻量化；解码必须能够适应不同的转录格式。

#if canImport(AppKit)
import AppKit

/// 平台图像类型别名（macOS）
public typealias MoltbotPlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit

/// 平台图像类型别名（iOS）
public typealias MoltbotPlatformImage = UIImage
#endif

/// 聊天使用成本信息
public struct MoltbotChatUsageCost: Codable, Hashable, Sendable {
    /// 输入成本
    public let input: Double?
    /// 输出成本
    public let output: Double?
    /// 缓存读取成本
    public let cacheRead: Double?
    /// 缓存写入成本
    public let cacheWrite: Double?
    /// 总成本
    public let total: Double?
}

/// 聊天使用统计信息
public struct MoltbotChatUsage: Codable, Hashable, Sendable {
    /// 输入 token 数
    public let input: Int?
    /// 输出 token 数
    public let output: Int?
    /// 缓存读取 token 数
    public let cacheRead: Int?
    /// 缓存写入 token 数
    public let cacheWrite: Int?
    /// 使用成本
    public let cost: MoltbotChatUsageCost?
    /// 总 token 数
    public let total: Int?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead
        case cacheWrite
        case cost
        case total
        case totalTokens
    }

    /// 从解码器初始化
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.input = try container.decodeIfPresent(Int.self, forKey: .input)
        self.output = try container.decodeIfPresent(Int.self, forKey: .output)
        self.cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead)
        self.cacheWrite = try container.decodeIfPresent(Int.self, forKey: .cacheWrite)
        self.cost = try container.decodeIfPresent(MoltbotChatUsageCost.self, forKey: .cost)
        self.total =
            try container.decodeIfPresent(Int.self, forKey: .total) ??
            container.decodeIfPresent(Int.self, forKey: .totalTokens)
    }

    /// 编码到编码器
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(self.input, forKey: .input)
        try container.encodeIfPresent(self.output, forKey: .output)
        try container.encodeIfPresent(self.cacheRead, forKey: .cacheRead)
        try container.encodeIfPresent(self.cacheWrite, forKey: .cacheWrite)
        try container.encodeIfPresent(self.cost, forKey: .cost)
        try container.encodeIfPresent(self.total, forKey: .total)
    }
}

/// 聊天消息内容
public struct MoltbotChatMessageContent: Codable, Hashable, Sendable {
    /// 内容类型
    public let type: String?
    /// 文本内容
    public let text: String?
    /// 思考内容
    public let thinking: String?
    /// 思考签名
    public let thinkingSignature: String?
    /// MIME 类型
    public let mimeType: String?
    /// 文件名
    public let fileName: String?
    /// 内容数据
    public let content: AnyCodable?

    // 工具调用字段（当 `type == "toolCall"` 或类似情况时）
    /// 工具调用 ID
    public let id: String?
    /// 工具名称
    public let name: String?
    /// 工具参数
    public let arguments: AnyCodable?

    /// 初始化方法
    public init(
        type: String?,
        text: String?,
        thinking: String? = nil,
        thinkingSignature: String? = nil,
        mimeType: String?,
        fileName: String?,
        content: AnyCodable?,
        id: String? = nil,
        name: String? = nil,
        arguments: AnyCodable? = nil)
    {
        self.type = type
        self.text = text
        self.thinking = thinking
        self.thinkingSignature = thinkingSignature
        self.mimeType = mimeType
        self.fileName = fileName
        self.content = content
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case thinking
        case thinkingSignature
        case mimeType
        case fileName
        case content
        case id
        case name
        case arguments
    }

    /// 从解码器初始化
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        self.thinkingSignature = try container.decodeIfPresent(String.self, forKey: .thinkingSignature)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        self.fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.arguments = try container.decodeIfPresent(AnyCodable.self, forKey: .arguments)

        if let any = try container.decodeIfPresent(AnyCodable.self, forKey: .content) {
            self.content = any
        } else if let str = try container.decodeIfPresent(String.self, forKey: .content) {
            self.content = AnyCodable(str)
        } else {
            self.content = nil
        }
    }
}

/// 聊天消息
public struct MoltbotChatMessage: Codable, Identifiable, Sendable {
    /// 消息 ID
    public var id: UUID = .init()
    /// 角色（用户/助手等）
    public let role: String
    /// 消息内容
    public let content: [MoltbotChatMessageContent]
    /// 时间戳
    public let timestamp: Double?
    /// 工具调用 ID
    public let toolCallId: String?
    /// 工具名称
    public let toolName: String?
    /// 使用统计
    public let usage: MoltbotChatUsage?
    /// 停止原因
    public let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case timestamp
        case toolCallId
        case tool_call_id
        case toolName
        case tool_name
        case usage
        case stopReason
    }

    /// 初始化方法
    public init(
        id: UUID = .init(),
        role: String,
        content: [MoltbotChatMessageContent],
        timestamp: Double?,
        toolCallId: String? = nil,
        toolName: String? = nil,
        usage: MoltbotChatUsage? = nil,
        stopReason: String? = nil)
    {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.usage = usage
        self.stopReason = stopReason
    }

    /// 从解码器初始化
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try container.decode(String.self, forKey: .role)
        self.timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp)
        self.toolCallId =
            try container.decodeIfPresent(String.self, forKey: .toolCallId) ??
            container.decodeIfPresent(String.self, forKey: .tool_call_id)
        self.toolName =
            try container.decodeIfPresent(String.self, forKey: .toolName) ??
            container.decodeIfPresent(String.self, forKey: .tool_name)
        self.usage = try container.decodeIfPresent(MoltbotChatUsage.self, forKey: .usage)
        self.stopReason = try container.decodeIfPresent(String.self, forKey: .stopReason)

        if let decoded = try? container.decode([MoltbotChatMessageContent].self, forKey: .content) {
            self.content = decoded
            return
        }

        // 某些会话日志格式将 `content` 存储为纯字符串。
        if let text = try? container.decode(String.self, forKey: .content) {
            self.content = [
                MoltbotChatMessageContent(
                    type: "text",
                    text: text,
                    thinking: nil,
                    thinkingSignature: nil,
                    mimeType: nil,
                    fileName: nil,
                    content: nil,
                    id: nil,
                    name: nil,
                    arguments: nil),
            ]
            return
        }

        self.content = []
    }

    /// 编码到编码器
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.role, forKey: .role)
        try container.encodeIfPresent(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(self.toolName, forKey: .toolName)
        try container.encodeIfPresent(self.usage, forKey: .usage)
        try container.encodeIfPresent(self.stopReason, forKey: .stopReason)
        try container.encode(self.content, forKey: .content)
    }
}

/// 聊天历史负载
public struct MoltbotChatHistoryPayload: Codable, Sendable {
    /// 会话密钥
    public let sessionKey: String
    /// 会话 ID
    public let sessionId: String?
    /// 消息列表
    public let messages: [AnyCodable]?
    /// 思考级别
    public let thinkingLevel: String?
}

/// 会话预览项
public struct MoltbotSessionPreviewItem: Codable, Hashable, Sendable {
    /// 角色
    public let role: String
    /// 文本
    public let text: String
}

/// 会话预览条目
public struct MoltbotSessionPreviewEntry: Codable, Sendable {
    /// 密钥
    public let key: String
    /// 状态
    public let status: String
    /// 预览项列表
    public let items: [MoltbotSessionPreviewItem]
}

/// 会话预览负载
public struct MoltbotSessionsPreviewPayload: Codable, Sendable {
    /// 时间戳
    public let ts: Int
    /// 预览列表
    public let previews: [MoltbotSessionPreviewEntry]

    /// 初始化方法
    public init(ts: Int, previews: [MoltbotSessionPreviewEntry]) {
        self.ts = ts
        self.previews = previews
    }
}

/// 聊天发送响应
public struct MoltbotChatSendResponse: Codable, Sendable {
    /// 运行 ID
    public let runId: String
    /// 状态
    public let status: String
}

/// 聊天事件负载
public struct MoltbotChatEventPayload: Codable, Sendable {
    /// 运行 ID
    public let runId: String?
    /// 会话密钥
    public let sessionKey: String?
    /// 状态
    public let state: String?
    /// 消息
    public let message: AnyCodable?
    /// 错误消息
    public let errorMessage: String?
}

/// 代理事件负载
public struct MoltbotAgentEventPayload: Codable, Sendable, Identifiable {
    /// 事件 ID
    public var id: String { "\(self.runId)-\(self.seq ?? -1)" }
    /// 运行 ID
    public let runId: String
    /// 序列号
    public let seq: Int?
    /// 流
    public let stream: String
    /// 时间戳
    public let ts: Int?
    /// 数据
    public let data: [String: AnyCodable]
}

/// 待处理的工具调用
public struct MoltbotChatPendingToolCall: Identifiable, Hashable, Sendable {
    /// 工具调用 ID
    public var id: String { self.toolCallId }
    /// 工具调用 ID
    public let toolCallId: String
    /// 工具名称
    public let name: String
    /// 工具参数
    public let args: AnyCodable?
    /// 开始时间
    public let startedAt: Double?
    /// 是否错误
    public let isError: Bool?
}

/// 网关健康状态
public struct MoltbotGatewayHealthOK: Codable, Sendable {
    /// 是否正常
    public let ok: Bool?
}

/// 待处理的附件
public struct MoltbotPendingAttachment: Identifiable {
    /// 附件 ID
    public let id = UUID()
    /// 附件 URL
    public let url: URL?
    /// 附件数据
    public let data: Data
    /// 文件名
    public let fileName: String
    /// MIME 类型
    public let mimeType: String
    /// 类型
    public let type: String
    /// 预览图像
    public let preview: MoltbotPlatformImage?

    /// 初始化方法
    public init(
        url: URL?,
        data: Data,
        fileName: String,
        mimeType: String,
        type: String = "file",
        preview: MoltbotPlatformImage?)
    {
        self.url = url
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
        self.type = type
        self.preview = preview
    }
}

/// 聊天附件负载
public struct MoltbotChatAttachmentPayload: Codable, Sendable, Hashable {
    /// 类型
    public let type: String
    /// MIME 类型
    public let mimeType: String
    /// 文件名
    public let fileName: String
    /// 内容
    public let content: String

    /// 初始化方法
    public init(type: String, mimeType: String, fileName: String, content: String) {
        self.type = type
        self.mimeType = mimeType
        self.fileName = fileName
        self.content = content
    }
}

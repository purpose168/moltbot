import MoltbotKit
import Foundation
import Observation
import OSLog
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// 聊天UI相关的日志记录器
private let chatUILogger = Logger(subsystem: "bot.molt", category: "MoltbotChatUI")

/// 聊天界面的视图模型，管理聊天状态和逻辑
@MainActor
@Observable
public final class MoltbotChatViewModel {
    /// 聊天消息列表
    public private(set) var messages: [MoltbotChatMessage] = []
    /// 用户输入文本
    public var input: String = ""
    /// 思考级别设置
    public var thinkingLevel: String = "off"
    /// 是否正在加载
    public private(set) var isLoading = false
    /// 是否正在发送消息
    public private(set) var isSending = false
    /// 是否正在中止操作
    public private(set) var isAborting = false
    /// 错误文本
    public var errorText: String?
    /// 待发送的附件
    public var attachments: [MoltbotPendingAttachment] = []
    /// 服务健康状态
    public private(set) var healthOK: Bool = false
    /// 待处理的运行数量
    public private(set) var pendingRunCount: Int = 0

    /// 会话密钥
    public private(set) var sessionKey: String
    /// 会话ID
    public private(set) var sessionId: String?
    /// 流式助手文本
    public private(set) var streamingAssistantText: String?
    /// 待处理的工具调用
    public private(set) var pendingToolCalls: [MoltbotChatPendingToolCall] = []
    /// 会话列表
    public private(set) var sessions: [MoltbotChatSessionEntry] = []
    /// 传输层实现
    private let transport: any MoltbotChatTransport

    /// 事件处理任务
    @ObservationIgnored
    private nonisolated(unsafe) var eventTask: Task<Void, Never>?
    /// 待处理的运行ID集合
    private var pendingRuns = Set<String>() {
        didSet { self.pendingRunCount = self.pendingRuns.count }
    }

    /// 待处理运行的超时任务
    @ObservationIgnored
    private nonisolated(unsafe) var pendingRunTimeoutTasks: [String: Task<Void, Never>] = [:]
    /// 待处理运行的超时时间（毫秒）
    private let pendingRunTimeoutMs: UInt64 = 120_000

    /// 按ID存储的待处理工具调用
    private var pendingToolCallsById: [String: MoltbotChatPendingToolCall] = [:] {
        didSet {
            self.pendingToolCalls = self.pendingToolCallsById.values
                .sorted { ($0.startedAt ?? 0) < ($1.startedAt ?? 0) }
        }
    }

    /// 上次健康检查的时间
    private var lastHealthPollAt: Date?

    /// 初始化聊天视图模型
    /// - Parameters:
    ///   - sessionKey: 会话密钥
    ///   - transport: 聊天传输层实现
    public init(sessionKey: String, transport: any MoltbotChatTransport) {
        self.sessionKey = sessionKey
        self.transport = transport

        // 启动事件处理任务
        self.eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.transport.events()
            for await evt in stream {
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    self?.handleTransportEvent(evt)
                }
            }
        }
    }

    /// 析构函数，清理资源
    deinit {
        // 取消事件处理任务
        self.eventTask?.cancel()
        // 取消所有超时任务
        for (_, task) in self.pendingRunTimeoutTasks {
            task.cancel()
        }
    }

    /// 加载聊天数据
    public func load() {
        Task { await self.bootstrap() }
    }

    /// 刷新聊天数据
    public func refresh() {
        Task { await self.bootstrap() }
    }

    /// 发送消息
    public func send() {
        Task { await self.performSend() }
    }

    /// 中止当前操作
    public func abort() {
        Task { await self.performAbort() }
    }

    /// 刷新会话列表
    /// - Parameter limit: 限制返回的会话数量
    public func refreshSessions(limit: Int? = nil) {
        Task { await self.fetchSessions(limit: limit) }
    }

    /// 切换到指定会话
    /// - Parameter sessionKey: 目标会话密钥
    public func switchSession(to sessionKey: String) {
        Task { await self.performSwitchSession(to: sessionKey) }
    }

    /// 获取会话选择列表
    /// - Returns: 排序后的会话列表
    public var sessionChoices: [MoltbotChatSessionEntry] {
        let now = Date().timeIntervalSince1970 * 1000
        let cutoff = now - (24 * 60 * 60 * 1000) // 24小时前
        let sorted = self.sessions.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
        var seen = Set<String>()
        var recent: [MoltbotChatSessionEntry] = []
        
        // 筛选最近24小时的会话
        for entry in sorted {
            guard !seen.contains(entry.key) else { continue }
            seen.insert(entry.key)
            guard (entry.updatedAt ?? 0) >= cutoff else { continue }
            recent.append(entry)
        }

        var result: [MoltbotChatSessionEntry] = []
        var included = Set<String>()
        
        // 去重并添加到结果
        for entry in recent where !included.contains(entry.key) {
            result.append(entry)
            included.insert(entry.key)
        }

        // 如果当前会话不在结果中，添加它
        if !included.contains(self.sessionKey) {
            if let current = sorted.first(where: { $0.key == self.sessionKey }) {
                result.append(current)
            } else {
                result.append(self.placeholderSession(key: self.sessionKey))
            }
        }

        return result
    }

    /// 添加附件
    /// - Parameter urls: 附件文件URL数组
    public func addAttachments(urls: [URL]) {
        Task { await self.loadAttachments(urls: urls) }
    }

    /// 添加图片附件
    /// - Parameters:
    ///   - data: 图片数据
    ///   - fileName: 文件名
    ///   - mimeType: MIME类型
    public func addImageAttachment(data: Data, fileName: String, mimeType: String) {
        Task { await self.addImageAttachment(url: nil, data: data, fileName: fileName, mimeType: mimeType) }
    }

    /// 移除附件
    /// - Parameter id: 附件ID
    public func removeAttachment(_ id: MoltbotPendingAttachment.ID) {
        self.attachments.removeAll { $0.id == id }
    }

    /// 是否可以发送消息
    public var canSend: Bool {
        let trimmed = self.input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !self.isSending && self.pendingRunCount == 0 && (!trimmed.isEmpty || !self.attachments.isEmpty)
    }

    // MARK: - 内部方法

    /// 初始化并加载聊天数据
    private func bootstrap() async {
        self.isLoading = true
        self.errorText = nil
        self.healthOK = false
        self.clearPendingRuns(reason: nil)
        self.pendingToolCallsById = [:]
        self.streamingAssistantText = nil
        self.sessionId = nil
        defer { self.isLoading = false }
        
        do {
            // 设置活跃会话密钥
            do {
                try await self.transport.setActiveSessionKey(self.sessionKey)
            } catch {
                // 尽力而为；即使没有推送事件，历史记录/发送/健康检查仍然有效
            }

            // 请求聊天历史
            let payload = try await self.transport.requestHistory(sessionKey: self.sessionKey)
            self.messages = Self.decodeMessages(payload.messages ?? [])
            self.sessionId = payload.sessionId
            
            // 设置思考级别
            if let level = payload.thinkingLevel, !level.isEmpty {
                self.thinkingLevel = level
            }
            
            // 检查服务健康状态
            await self.pollHealthIfNeeded(force: true)
            // 获取会话列表
            await self.fetchSessions(limit: 50)
            self.errorText = nil
        } catch {
            self.errorText = error.localizedDescription
            chatUILogger.error("bootstrap failed \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 解码消息
    /// - Parameter raw: 原始消息数据
    /// - Returns: 解码后的消息数组
    private static func decodeMessages(_ raw: [AnyCodable]) -> [MoltbotChatMessage] {
        let decoded = raw.compactMap { item in
            (try? ChatPayloadDecoding.decode(item, as: MoltbotChatMessage.self))
        }
        return Self.dedupeMessages(decoded)
    }

    /// 去重消息
    /// - Parameter messages: 消息数组
    /// - Returns: 去重后的消息数组
    private static func dedupeMessages(_ messages: [MoltbotChatMessage]) -> [MoltbotChatMessage] {
        var result: [MoltbotChatMessage] = []
        result.reserveCapacity(messages.count)
        var seen = Set<String>()

        for message in messages {
            guard let key = Self.dedupeKey(for: message) else {
                result.append(message)
                continue
            }
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(message)
        }

        return result
    }

    /// 生成消息去重键
    /// - Parameter message: 消息
    /// - Returns: 去重键
    private static func dedupeKey(for message: MoltbotChatMessage) -> String? {
        guard let timestamp = message.timestamp else { return nil }
        let text = message.content.compactMap(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return "\(message.role)|\(timestamp)|\(text)"
    }

    /// 执行发送消息操作
    private func performSend() async {
        guard !self.isSending else { return }
        let trimmed = self.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !self.attachments.isEmpty else { return }

        // 检查服务健康状态
        guard self.healthOK else {
            self.errorText = "网关健康状态不正常，无法发送消息"
            return
        }

        self.isSending = true
        self.errorText = nil
        let runId = UUID().uuidString
        let messageText = trimmed.isEmpty && !self.attachments.isEmpty ? "See attached." : trimmed
        self.pendingRuns.insert(runId)
        self.armPendingRunTimeout(runId: runId)
        self.pendingToolCallsById = [:]
        self.streamingAssistantText = nil

        // 乐观地将用户消息添加到UI
        var userContent: [MoltbotChatMessageContent] = [
            MoltbotChatMessageContent(
                type: "text",
                text: messageText,
                thinking: nil,
                thinkingSignature: nil,
                mimeType: nil,
                fileName: nil,
                content: nil,
                id: nil,
                name: nil,
                arguments: nil),
        ]
        
        // 编码附件
        let encodedAttachments = self.attachments.map { att -> MoltbotChatAttachmentPayload in
            MoltbotChatAttachmentPayload(
                type: att.type,
                mimeType: att.mimeType,
                fileName: att.fileName,
                content: att.data.base64EncodedString())
        }
        
        // 添加附件到消息内容
        for att in encodedAttachments {
            userContent.append(
                MoltbotChatMessageContent(
                    type: att.type,
                    text: nil,
                    thinking: nil,
                    thinkingSignature: nil,
                    mimeType: att.mimeType,
                    fileName: att.fileName,
                    content: AnyCodable(att.content),
                    id: nil,
                    name: nil,
                    arguments: nil))
        }
        
        // 添加用户消息到UI
        self.messages.append(
            MoltbotChatMessage(
                id: UUID(),
                role: "user",
                content: userContent,
                timestamp: Date().timeIntervalSince1970 * 1000))

        // 立即清空输入，提高用户体验（在网络请求之前）
        self.input = ""
        self.attachments = []

        do {
            // 发送消息
            let response = try await self.transport.sendMessage(
                sessionKey: self.sessionKey,
                message: messageText,
                thinking: self.thinkingLevel,
                idempotencyKey: runId,
                attachments: encodedAttachments)
            
            // 如果返回的runId与我们生成的不同，更新
            if response.runId != runId {
                self.clearPendingRun(runId)
                self.pendingRuns.insert(response.runId)
                self.armPendingRunTimeout(runId: response.runId)
            }
        } catch {
            self.clearPendingRun(runId)
            self.errorText = error.localizedDescription
            chatUILogger.error("chat.send failed \(error.localizedDescription, privacy: .public)")
        }

        self.isSending = false
    }

    /// 执行中止操作
    private func performAbort() async {
        guard !self.pendingRuns.isEmpty else { return }
        guard !self.isAborting else { return }
        self.isAborting = true
        defer { self.isAborting = false }

        let runIds = Array(self.pendingRuns)
        for runId in runIds {
            do {
                try await self.transport.abortRun(sessionKey: self.sessionKey, runId: runId)
            } catch {
                // 尽力而为
            }
        }
    }

    /// 获取会话列表
    /// - Parameter limit: 限制返回的会话数量
    private func fetchSessions(limit: Int?) async {
        do {
            let res = try await self.transport.listSessions(limit: limit)
            self.sessions = res.sessions
        } catch {
            // 尽力而为
        }
    }

    /// 执行会话切换
    /// - Parameter sessionKey: 目标会话密钥
    private func performSwitchSession(to sessionKey: String) async {
        let next = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !next.isEmpty else { return }
        guard next != self.sessionKey else { return }
        self.sessionKey = next
        await self.bootstrap()
    }

    /// 创建会话占位符
    /// - Parameter key: 会话密钥
    /// - Returns: 会话占位符
    private func placeholderSession(key: String) -> MoltbotChatSessionEntry {
        MoltbotChatSessionEntry(
            key: key,
            kind: nil,
            displayName: nil,
            surface: nil,
            subject: nil,
            room: nil,
            space: nil,
            updatedAt: nil,
            sessionId: nil,
            systemSent: nil,
            abortedLastRun: nil,
            thinkingLevel: nil,
            verboseLevel: nil,
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            model: nil,
            contextTokens: nil)
    }

    /// 处理传输层事件
    /// - Parameter evt: 传输层事件
    private func handleTransportEvent(_ evt: MoltbotChatTransportEvent) {
        switch evt {
        case let .health(ok):
            self.healthOK = ok
        case .tick:
            Task { await self.pollHealthIfNeeded(force: false) }
        case let .chat(chat):
            self.handleChatEvent(chat)
        case let .agent(agent):
            self.handleAgentEvent(agent)
        case .seqGap:
            self.errorText = "事件流中断，请尝试刷新"
            self.clearPendingRuns(reason: nil)
        }
    }

    /// 处理聊天事件
    /// - Parameter chat: 聊天事件数据
    private func handleChatEvent(_ chat: MoltbotChatEventPayload) {
        // 检查会话密钥是否匹配
        if let sessionKey = chat.sessionKey, sessionKey != self.sessionKey {
            return
        }

        let isOurRun = chat.runId.flatMap { self.pendingRuns.contains($0) } ?? false
        if !isOurRun {
            // 保持多个客户端同步：如果另一个客户端完成了我们会话的运行，刷新历史记录
            switch chat.state {
            case "final", "aborted", "error":
                self.streamingAssistantText = nil
                self.pendingToolCallsById = [:]
                Task { await self.refreshHistoryAfterRun() }
            default:
                break
            }
            return
        }

        switch chat.state {
        case "final", "aborted", "error":
            if chat.state == "error" {
                self.errorText = chat.errorMessage ?? "聊天失败"
            }
            if let runId = chat.runId {
                self.clearPendingRun(runId)
            } else if self.pendingRuns.count <= 1 {
                self.clearPendingRuns(reason: nil)
            }
            self.pendingToolCallsById = [:]
            self.streamingAssistantText = nil
            Task { await self.refreshHistoryAfterRun() }
        default:
            break
        }
    }

    /// 处理代理事件
    /// - Parameter evt: 代理事件数据
    private func handleAgentEvent(_ evt: MoltbotAgentEventPayload) {
        if let sessionId, evt.runId != sessionId {
            return
        }

        switch evt.stream {
        case "assistant":
            if let text = evt.data["text"]?.value as? String {
                self.streamingAssistantText = text
            }
        case "tool":
            guard let phase = evt.data["phase"]?.value as? String else { return }
            guard let name = evt.data["name"]?.value as? String else { return }
            guard let toolCallId = evt.data["toolCallId"]?.value as? String else { return }
            if phase == "start" {
                let args = evt.data["args"]
                self.pendingToolCallsById[toolCallId] = MoltbotChatPendingToolCall(
                    toolCallId: toolCallId,
                    name: name,
                    args: args,
                    startedAt: evt.ts.map(Double.init) ?? Date().timeIntervalSince1970 * 1000,
                    isError: nil)
            } else if phase == "result" {
                self.pendingToolCallsById[toolCallId] = nil
            }
        default:
            break
        }
    }

    /// 运行完成后刷新历史记录
    private func refreshHistoryAfterRun() async {
        do {
            let payload = try await self.transport.requestHistory(sessionKey: self.sessionKey)
            self.messages = Self.decodeMessages(payload.messages ?? [])
            self.sessionId = payload.sessionId
            if let level = payload.thinkingLevel, !level.isEmpty {
                self.thinkingLevel = level
            }
        } catch {
            chatUILogger.error("refresh history failed \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 为待处理运行设置超时
    /// - Parameter runId: 运行ID
    private func armPendingRunTimeout(runId: String) {
        self.pendingRunTimeoutTasks[runId]?.cancel()
        self.pendingRunTimeoutTasks[runId] = Task { [weak self] in
            let timeoutMs = await MainActor.run { self?.pendingRunTimeoutMs ?? 0 }
            try? await Task.sleep(nanoseconds: timeoutMs * 1_000_000)
            await MainActor.run { [weak self] in
                guard let self else { return }
                guard self.pendingRuns.contains(runId) else { return }
                self.clearPendingRun(runId)
                self.errorText = "等待回复超时，请重试或刷新"
            }
        }
    }

    /// 清除待处理运行
    /// - Parameter runId: 运行ID
    private func clearPendingRun(_ runId: String) {
        self.pendingRuns.remove(runId)
        self.pendingRunTimeoutTasks[runId]?.cancel()
        self.pendingRunTimeoutTasks[runId] = nil
    }

    /// 清除所有待处理运行
    /// - Parameter reason: 清除原因
    private func clearPendingRuns(reason: String?) {
        for runId in self.pendingRuns {
            self.pendingRunTimeoutTasks[runId]?.cancel()
        }
        self.pendingRunTimeoutTasks.removeAll()
        self.pendingRuns.removeAll()
        if let reason, !reason.isEmpty {
            self.errorText = reason
        }
    }

    /// 检查服务健康状态（如果需要）
    /// - Parameter force: 是否强制检查
    private func pollHealthIfNeeded(force: Bool) async {
        // 如果不是强制检查，且上次检查时间不到10秒，则跳过
        if !force, let last = self.lastHealthPollAt, Date().timeIntervalSince(last) < 10 {
            return
        }
        self.lastHealthPollAt = Date()
        do {
            let ok = try await self.transport.requestHealth(timeoutMs: 5000)
            self.healthOK = ok
        } catch {
            self.healthOK = false
        }
    }

    /// 加载附件
    /// - Parameter urls: 附件URL数组
    private func loadAttachments(urls: [URL]) async {
        for url in urls {
            do {
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                await self.addImageAttachment(
                    url: url,
                    data: data,
                    fileName: url.lastPathComponent,
                    mimeType: Self.mimeType(for: url) ?? "application/octet-stream")
            } catch {
                await MainActor.run { self.errorText = error.localizedDescription }
            }
        }
    }

    /// 获取URL的MIME类型
    /// - Parameter url: 文件URL
    /// - Returns: MIME类型
    private static func mimeType(for url: URL) -> String? {
        let ext = url.pathExtension
        guard !ext.isEmpty else { return nil }
        return (UTType(filenameExtension: ext) ?? .data).preferredMIMEType
    }

    /// 添加图片附件
    /// - Parameters:
    ///   - url: 文件URL
    ///   - data: 图片数据
    ///   - fileName: 文件名
    ///   - mimeType: MIME类型
    private func addImageAttachment(url: URL?, data: Data, fileName: String, mimeType: String) async {
        // 检查文件大小（限制5MB）
        if data.count > 5_000_000 {
            self.errorText = "附件 \(fileName) 超过5MB限制"
            return
        }

        // 确定文件类型
        let uti: UTType = {
            if let url {
                return UTType(filenameExtension: url.pathExtension) ?? .data
            }
            return UTType(mimeType: mimeType) ?? .data
        }()
        
        // 检查是否为图片类型
        guard uti.conforms(to: .image) else { 
            self.errorText = "目前仅支持图片附件"
            return
        }

        // 生成预览图片
        let preview = Self.previewImage(data: data)
        
        // 添加到附件列表
        self.attachments.append(
            MoltbotPendingAttachment(
                url: url,
                data: data,
                fileName: fileName,
                mimeType: mimeType,
                preview: preview))
    }

    /// 生成预览图片
    /// - Parameter data: 图片数据
    /// - Returns: 平台特定的图片对象
    private static func previewImage(data: Data) -> MoltbotPlatformImage? {
        #if canImport(AppKit)
        NSImage(data: data)
        #elseif canImport(UIKit)
        UIImage(data: data)
        #else
        nil
        #endif
    }
}
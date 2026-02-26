import MoltbotKit
import Foundation
import Testing
@testable import MoltbotChatUI

/// 超时错误，用于测试中的等待条件
private struct TimeoutError: Error, CustomStringConvertible {
    let label: String
    var description: String { "等待超时: \(self.label)" }
}

/// 等待条件满足的辅助函数
/// - Parameters:
///   - label: 等待条件的描述标签
///   - timeoutSeconds: 超时时间（秒），默认2.0
///   - pollMs: 轮询间隔（毫秒），默认10
///   - condition: 等待的条件闭包
private func waitUntil(
    _ label: String,
    timeoutSeconds: Double = 2.0,
    pollMs: UInt64 = 10,
    _ condition: @escaping @Sendable () async -> Bool) async throws
{
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollMs * 1_000_000)
    }
    throw TimeoutError(label: label)
}

/// 测试聊天传输状态的actor
private actor TestChatTransportState {
    var historyCallCount: Int = 0        // 请求历史的调用次数
    var sessionsCallCount: Int = 0       // 请求会话列表的调用次数
    var sentRunIds: [String] = []        // 已发送的运行ID
    var abortedRunIds: [String] = []     // 已中止的运行ID
}

/// 测试用的聊天传输实现
private final class TestChatTransport: @unchecked Sendable, MoltbotChatTransport {
    private let state = TestChatTransportState()
    private let historyResponses: [MoltbotChatHistoryPayload]     // 预定义的历史响应
    private let sessionsResponses: [MoltbotChatSessionsListResponse] // 预定义的会话列表响应

    private let stream: AsyncStream<MoltbotChatTransportEvent>
    private let continuation: AsyncStream<MoltbotChatTransportEvent>.Continuation

    /// 初始化测试传输
    /// - Parameters:
    ///   - historyResponses: 历史响应数组
    ///   - sessionsResponses: 会话列表响应数组
    init(
        historyResponses: [MoltbotChatHistoryPayload],
        sessionsResponses: [MoltbotChatSessionsListResponse] = [])
    {
        self.historyResponses = historyResponses
        self.sessionsResponses = sessionsResponses
        var cont: AsyncStream<MoltbotChatTransportEvent>.Continuation!
        self.stream = AsyncStream { c in
            cont = c
        }
        self.continuation = cont
    }

    /// 获取事件流
    func events() -> AsyncStream<MoltbotChatTransportEvent> {
        self.stream
    }

    /// 设置活动会话密钥
    func setActiveSessionKey(_: String) async throws {}

    /// 请求历史记录
    func requestHistory(sessionKey: String) async throws -> MoltbotChatHistoryPayload {
        let idx = await self.state.historyCallCount
        await self.state.setHistoryCallCount(idx + 1)
        if idx < self.historyResponses.count {
            return self.historyResponses[idx]
        }
        return self.historyResponses.last ?? MoltbotChatHistoryPayload(
            sessionKey: sessionKey,
            sessionId: nil,
            messages: [],
            thinkingLevel: "off")
    }

    /// 发送消息
    func sendMessage(
        sessionKey _: String,
        message _: String,
        thinking _: String,
        idempotencyKey: String,
        attachments _: [MoltbotChatAttachmentPayload]) async throws -> MoltbotChatSendResponse
    {
        await self.state.sentRunIdsAppend(idempotencyKey)
        return MoltbotChatSendResponse(runId: idempotencyKey, status: "ok")
    }

    /// 中止运行
    func abortRun(sessionKey _: String, runId: String) async throws {
        await self.state.abortedRunIdsAppend(runId)
    }

    /// 列出会话
    func listSessions(limit _: Int?) async throws -> MoltbotChatSessionsListResponse {
        let idx = await self.state.sessionsCallCount
        await self.state.setSessionsCallCount(idx + 1)
        if idx < self.sessionsResponses.count {
            return self.sessionsResponses[idx]
        }
        return self.sessionsResponses.last ?? MoltbotChatSessionsListResponse(
            ts: nil,
            path: nil,
            count: 0,
            defaults: nil,
            sessions: [])
    }

    /// 请求健康状态
    func requestHealth(timeoutMs _: Int) async throws -> Bool {
        true
    }

    /// 发送事件
    func emit(_ evt: MoltbotChatTransportEvent) {
        self.continuation.yield(evt)
    }

    /// 获取最后发送的运行ID
    func lastSentRunId() async -> String? {
        let ids = await self.state.sentRunIds
        return ids.last
    }

    /// 获取已中止的运行ID列表
    func abortedRunIds() async -> [String] {
        await self.state.abortedRunIds
    }
}

/// TestChatTransportState的扩展方法
fileprivate extension TestChatTransportState {
    func setHistoryCallCount(_ v: Int) {
        self.historyCallCount = v
    }

    func setSessionsCallCount(_ v: Int) {
        self.sessionsCallCount = v
    }

    func sentRunIdsAppend(_ v: String) {
        self.sentRunIds.append(v)
    }

    func abortedRunIdsAppend(_ v: String) {
        self.abortedRunIds.append(v)
    }
}

/// 聊天视图模型测试套件
@Suite struct ChatViewModelTests {
    /// 测试助手消息流式传输和最终清除
    @Test func streamsAssistantAndClearsOnFinal() async throws {
        let sessionId = "sess-main"
        let history1 = MoltbotChatHistoryPayload(
            sessionKey: "main",
            sessionId: sessionId,
            messages: [],
            thinkingLevel: "off")
        let history2 = MoltbotChatHistoryPayload(
            sessionKey: "main",
            sessionId: sessionId,
            messages: [
                AnyCodable([
                    "role": "assistant",
                    "content": [["type": "text", "text": "final answer"]],
                    "timestamp": Date().timeIntervalSince1970 * 1000,
                ]),
            ],
            thinkingLevel: "off")

        let transport = TestChatTransport(historyResponses: [history1, history2])
        let vm = await MainActor.run { MoltbotChatViewModel(sessionKey: "main", transport: transport) }

        await MainActor.run { vm.load() }
        try await waitUntil("初始化完成") { await MainActor.run { vm.healthOK && vm.sessionId == sessionId } }

        await MainActor.run {
            vm.input = "hi"
            vm.send()
        }
        try await waitUntil("待处理运行开始") { await MainActor.run { vm.pendingRunCount == 1 } }

        transport.emit(
            .agent(
                MoltbotAgentEventPayload(
                    runId: sessionId,
                    seq: 1,
                    stream: "assistant",
                    ts: Int(Date().timeIntervalSince1970 * 1000),
                    data: ["text": AnyCodable("streaming…")])))

        try await waitUntil("助手消息流可见") { 
            await MainActor.run { vm.streamingAssistantText == "streaming…" }
        }

        transport.emit(
            .agent(
                MoltbotAgentEventPayload(
                    runId: sessionId,
                    seq: 2,
                    stream: "tool",
                    ts: Int(Date().timeIntervalSince1970 * 1000),
                    data: [
                        "phase": AnyCodable("start"),
                        "name": AnyCodable("demo"),
                        "toolCallId": AnyCodable("t1"),
                        "args": AnyCodable(["x": 1]),
                    ])))

        try await waitUntil("工具调用待处理") { await MainActor.run { vm.pendingToolCalls.count == 1 } }

        let runId = try #require(await transport.lastSentRunId())
        transport.emit(
            .chat(
                MoltbotChatEventPayload(
                    runId: runId,
                    sessionKey: "main",
                    state: "final",
                    message: nil,
                    errorMessage: nil)))

        try await waitUntil("待处理运行清除") { await MainActor.run { vm.pendingRunCount == 0 } }
        try await waitUntil("历史记录刷新") { 
            await MainActor.run { vm.messages.contains(where: { $0.role == "assistant" }) }
        }
        #expect(await MainActor.run { vm.streamingAssistantText } == nil)
        #expect(await MainActor.run { vm.pendingToolCalls.isEmpty })
    }

    /// 测试外部最终事件清除流式传输
    @Test func clearsStreamingOnExternalFinalEvent() async throws {
        let sessionId = "sess-main"
        let history = MoltbotChatHistoryPayload(
            sessionKey: "main",
            sessionId: sessionId,
            messages: [],
            thinkingLevel: "off")
        let transport = TestChatTransport(historyResponses: [history, history])
        let vm = await MainActor.run { MoltbotChatViewModel(sessionKey: "main", transport: transport) }

        await MainActor.run { vm.load() }
        try await waitUntil("初始化完成") { await MainActor.run { vm.healthOK && vm.sessionId == sessionId } }

        transport.emit(
            .agent(
                MoltbotAgentEventPayload(
                    runId: sessionId,
                    seq: 1,
                    stream: "assistant",
                    ts: Int(Date().timeIntervalSince1970 * 1000),
                    data: ["text": AnyCodable("external stream")])))

        transport.emit(
            .agent(
                MoltbotAgentEventPayload(
                    runId: sessionId,
                    seq: 2,
                    stream: "tool",
                    ts: Int(Date().timeIntervalSince1970 * 1000),
                    data: [
                        "phase": AnyCodable("start"),
                        "name": AnyCodable("demo"),
                        "toolCallId": AnyCodable("t1"),
                        "args": AnyCodable(["x": 1]),
                    ])))

        try await waitUntil("流式传输激活") { 
            await MainActor.run { vm.streamingAssistantText == "external stream" }
        }
        try await waitUntil("工具调用待处理") { await MainActor.run { vm.pendingToolCalls.count == 1 } }

        transport.emit(
            .chat(
                MoltbotChatEventPayload(
                    runId: "other-run",
                    sessionKey: "main",
                    state: "final",
                    message: nil,
                    errorMessage: nil)))

        try await waitUntil("流式传输清除") { await MainActor.run { vm.streamingAssistantText == nil } }
        #expect(await MainActor.run { vm.pendingToolCalls.isEmpty })
    }

    /// 测试会话选择优先主会话和最近会话
    @Test func sessionChoicesPreferMainAndRecent() async throws {
        let now = Date().timeIntervalSince1970 * 1000
        let recent = now - (2 * 60 * 60 * 1000)      // 2小时前
        let recentOlder = now - (5 * 60 * 60 * 1000) // 5小时前
        let stale = now - (26 * 60 * 60 * 1000)      // 26小时前
        let history = MoltbotChatHistoryPayload(
            sessionKey: "main",
            sessionId: "sess-main",
            messages: [],
            thinkingLevel: "off")
        let sessions = MoltbotChatSessionsListResponse(
            ts: now,
            path: nil,
            count: 4,
            defaults: nil,
            sessions: [
                MoltbotChatSessionEntry(
                    key: "recent-1",
                    kind: nil,
                    displayName: nil,
                    surface: nil,
                    subject: nil,
                    room: nil,
                    space: nil,
                    updatedAt: recent,
                    sessionId: nil,
                    systemSent: nil,
                    abortedLastRun: nil,
                    thinkingLevel: nil,
                    verboseLevel: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    model: nil,
                    contextTokens: nil),
                MoltbotChatSessionEntry(
                    key: "main",
                    kind: nil,
                    displayName: nil,
                    surface: nil,
                    subject: nil,
                    room: nil,
                    space: nil,
                    updatedAt: stale,
                    sessionId: nil,
                    systemSent: nil,
                    abortedLastRun: nil,
                    thinkingLevel: nil,
                    verboseLevel: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    model: nil,
                    contextTokens: nil),
                MoltbotChatSessionEntry(
                    key: "recent-2",
                    kind: nil,
                    displayName: nil,
                    surface: nil,
                    subject: nil,
                    room: nil,
                    space: nil,
                    updatedAt: recentOlder,
                    sessionId: nil,
                    systemSent: nil,
                    abortedLastRun: nil,
                    thinkingLevel: nil,
                    verboseLevel: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    model: nil,
                    contextTokens: nil),
                MoltbotChatSessionEntry(
                    key: "old-1",
                    kind: nil,
                    displayName: nil,
                    surface: nil,
                    subject: nil,
                    room: nil,
                    space: nil,
                    updatedAt: stale,
                    sessionId: nil,
                    systemSent: nil,
                    abortedLastRun: nil,
                    thinkingLevel: nil,
                    verboseLevel: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    model: nil,
                    contextTokens: nil),
            ])

        let transport = TestChatTransport(
            historyResponses: [history],
            sessionsResponses: [sessions])
        let vm = await MainActor.run { MoltbotChatViewModel(sessionKey: "main", transport: transport) }
        await MainActor.run { vm.load() }
        try await waitUntil("会话加载完成") { await MainActor.run { !vm.sessions.isEmpty } }

        let keys = await MainActor.run { vm.sessionChoices.map(\.key) }
        #expect(keys == ["main", "recent-1", "recent-2"])
    }

    /// 测试会话选择在缺失时包含当前会话
    @Test func sessionChoicesIncludeCurrentWhenMissing() async throws {
        let now = Date().timeIntervalSince1970 * 1000
        let recent = now - (30 * 60 * 1000)  // 30分钟前
        let history = MoltbotChatHistoryPayload(
            sessionKey: "custom",
            sessionId: "sess-custom",
            messages: [],
            thinkingLevel: "off")
        let sessions = MoltbotChatSessionsListResponse(
            ts: now,
            path: nil,
            count: 1,
            defaults: nil,
            sessions: [
                MoltbotChatSessionEntry(
                    key: "main",
                    kind: nil,
                    displayName: nil,
                    surface: nil,
                    subject: nil,
                    room: nil,
                    space: nil,
                    updatedAt: recent,
                    sessionId: nil,
                    systemSent: nil,
                    abortedLastRun: nil,
                    thinkingLevel: nil,
                    verboseLevel: nil,
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    model: nil,
                    contextTokens: nil),
            ])

        let transport = TestChatTransport(
            historyResponses: [history],
            sessionsResponses: [sessions])
        let vm = await MainActor.run { MoltbotChatViewModel(sessionKey: "custom", transport: transport) }
        await MainActor.run { vm.load() }
        try await waitUntil("会话加载完成") { await MainActor.run { !vm.sessions.isEmpty } }

        let keys = await MainActor.run { vm.sessionChoices.map(\.key) }
        #expect(keys == ["main", "custom"])
    }

    /// 测试外部错误事件清除流式传输
    @Test func clearsStreamingOnExternalErrorEvent() async throws {
        let sessionId = "sess-main"
        let history = MoltbotChatHistoryPayload(
            sessionKey: "main",
            sessionId: sessionId,
            messages: [],
            thinkingLevel: "off")
        let transport = TestChatTransport(historyResponses: [history, history])
        let vm = await MainActor.run { MoltbotChatViewModel(sessionKey: "main", transport: transport) }

        await MainActor.run { vm.load() }
        try await waitUntil("初始化完成") { await MainActor.run { vm.healthOK && vm.sessionId == sessionId } }

        transport.emit(
            .agent(
                MoltbotAgentEventPayload(
                    runId: sessionId,
                    seq: 1,
                    stream: "assistant",
                    ts: Int(Date().timeIntervalSince1970 * 1000),
                    data: ["text": AnyCodable("external stream")])))

        try await waitUntil("流式传输激活") { 
            await MainActor.run { vm.streamingAssistantText == "external stream" }
        }

        transport.emit(
            .chat(
                MoltbotChatEventPayload(
                    runId: "other-run",
                    sessionKey: "main",
                    state: "error",
                    message: nil,
                    errorMessage: "boom")))

        try await waitUntil("流式传输清除") { await MainActor.run { vm.streamingAssistantText == nil } }
    }

    /// 测试中止请求在收到中止事件前不会清除待处理状态
    @Test func abortRequestsDoNotClearPendingUntilAbortedEvent() async throws {
        let sessionId = "sess-main"
        let history = MoltbotChatHistoryPayload(
            sessionKey: "main",
            sessionId: sessionId,
            messages: [],
            thinkingLevel: "off")
        let transport = TestChatTransport(historyResponses: [history, history])
        let vm = await MainActor.run { MoltbotChatViewModel(sessionKey: "main", transport: transport) }

        await MainActor.run { vm.load() }
        try await waitUntil("初始化完成") { await MainActor.run { vm.healthOK && vm.sessionId == sessionId } }

        await MainActor.run {
            vm.input = "hi"
            vm.send()
        }
        try await waitUntil("待处理运行开始") { await MainActor.run { vm.pendingRunCount == 1 } }

        let runId = try #require(await transport.lastSentRunId())
        await MainActor.run { vm.abort() }

        try await waitUntil("abortRun被调用") { 
            let ids = await transport.abortedRunIds()
            return ids == [runId]
        }

        // 待处理状态会保持，直到网关广播中止/最终聊天事件
        #expect(await MainActor.run { vm.pendingRunCount } == 1)

        transport.emit(
            .chat(
                MoltbotChatEventPayload(
                    runId: runId,
                    sessionKey: "main",
                    state: "aborted",
                    message: nil,
                    errorMessage: nil)))

        try await waitUntil("待处理运行清除") { await MainActor.run { vm.pendingRunCount == 0 } }
    }
}
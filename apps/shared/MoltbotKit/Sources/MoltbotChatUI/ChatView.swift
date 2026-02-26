import SwiftUI

/// Moltbot 聊天视图主结构
/// 提供完整的聊天界面，包括消息列表、输入框和各种状态显示
@MainActor
public struct MoltbotChatView: View {
    /// 聊天视图样式枚举
    public enum Style {
        case standard  // 标准样式
        case onboarding  // 引导样式
    }

    // 状态变量
    @State private var viewModel: MoltbotChatViewModel  // 聊天视图模型
    @State private var scrollerBottomID = UUID()  // 滚动到底部的标识符
    @State private var scrollPosition: UUID?  // 当前滚动位置
    @State private var showSessions = false  // 是否显示会话切换器
    @State private var hasPerformedInitialScroll = false  // 是否已执行初始滚动
    @State private var isPinnedToBottom = true  // 是否固定在底部
    @State private var lastUserMessageID: UUID?  // 最后一条用户消息的ID
    private let showsSessionSwitcher: Bool  // 是否显示会话切换器
    private let style: Style  // 聊天视图样式
    private let markdownVariant: ChatMarkdownVariant  // Markdown 变体
    private let userAccent: Color?  // 用户强调色

    /// 布局常量枚举
    /// 根据不同平台提供不同的布局值
    private enum Layout {
        #if os(macOS)
        static let outerPaddingHorizontal: CGFloat = 6  // 外部水平边距
        static let outerPaddingVertical: CGFloat = 0  // 外部垂直边距
        static let composerPaddingHorizontal: CGFloat = 0  // 输入框水平边距
        static let stackSpacing: CGFloat = 0  // 栈间距
        static let messageSpacing: CGFloat = 6  // 消息间距
        static let messageListPaddingTop: CGFloat = 12  // 消息列表顶部边距
        static let messageListPaddingBottom: CGFloat = 16  // 消息列表底部边距
        static let messageListPaddingHorizontal: CGFloat = 6  // 消息列表水平边距
        #else
        static let outerPaddingHorizontal: CGFloat = 6  // 外部水平边距
        static let outerPaddingVertical: CGFloat = 6  // 外部垂直边距
        static let composerPaddingHorizontal: CGFloat = 6  // 输入框水平边距
        static let stackSpacing: CGFloat = 6  // 栈间距
        static let messageSpacing: CGFloat = 12  // 消息间距
        static let messageListPaddingTop: CGFloat = 10  // 消息列表顶部边距
        static let messageListPaddingBottom: CGFloat = 6  // 消息列表底部边距
        static let messageListPaddingHorizontal: CGFloat = 8  // 消息列表水平边距
        #endif
    }

    /// 初始化方法
    /// - Parameters:
    ///   - viewModel: 聊天视图模型
    ///   - showsSessionSwitcher: 是否显示会话切换器
    ///   - style: 聊天视图样式
    ///   - markdownVariant: Markdown 变体
    ///   - userAccent: 用户强调色
    public init(
        viewModel: MoltbotChatViewModel,
        showsSessionSwitcher: Bool = false,
        style: Style = .standard,
        markdownVariant: ChatMarkdownVariant = .standard,
        userAccent: Color? = nil)
    {
        self._viewModel = State(initialValue: viewModel)
        self.showsSessionSwitcher = showsSessionSwitcher
        self.style = style
        self.markdownVariant = markdownVariant
        self.userAccent = userAccent
    }

    /// 视图主体
    public var body: some View {
        ZStack {
            // 背景设置
            if self.style == .standard {
                MoltbotChatTheme.background
                    .ignoresSafeArea()
            }

            // 垂直布局：消息列表 + 输入框
            VStack(spacing: Layout.stackSpacing) {
                self.messageList
                    .padding(.horizontal, Layout.outerPaddingHorizontal)
                MoltbotChatComposer(
                    viewModel: self.viewModel,
                    style: self.style,
                    showsSessionSwitcher: self.showsSessionSwitcher)
                    .padding(.horizontal, Layout.composerPaddingHorizontal)
            }
            .padding(.vertical, Layout.outerPaddingVertical)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { self.viewModel.load() }  // 视图出现时加载数据
        .sheet(isPresented: self.$showSessions) {  // 会话切换器弹窗
            if self.showsSessionSwitcher {
                ChatSessionsSheet(viewModel: self.viewModel)
            } else {
                EmptyView()
            }
        }
    }

    /// 消息列表视图
    private var messageList: some View {
        ZStack {
            ScrollView {
                LazyVStack(spacing: Layout.messageSpacing) {
                    self.messageListRows

                    // 底部占位视图，用于实现滚动到底部
                    Color.clear
                        #if os(macOS)
                        .frame(height: Layout.messageListPaddingBottom)
                        #else
                        .frame(height: Layout.messageListPaddingBottom + 1)
                        #endif
                        .id(self.scrollerBottomID)
                }
                // 使用滚动目标实现稳定的自动滚动，避免 ScrollViewReader 重布局闪烁
                .scrollTargetLayout()
                .padding(.top, Layout.messageListPaddingTop)
                .padding(.horizontal, Layout.messageListPaddingHorizontal)
            }
            // 保持滚动固定在底部以显示新消息
            .scrollPosition(id: self.$scrollPosition, anchor: .bottom)
            .onChange(of: self.scrollPosition) { _, position in
                guard let position else { return }
                self.isPinnedToBottom = position == self.scrollerBottomID
            }

            // 加载状态指示器
            if self.viewModel.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 消息列表覆盖层（错误提示、空状态等）
            self.messageListOverlay
        }
        // 确保消息列表在第一次布局时占据垂直空间
        .frame(maxHeight: .infinity, alignment: .top)
        .layoutPriority(1)
        // 初始加载完成后滚动到底部
        .onChange(of: self.viewModel.isLoading) { _, isLoading in
            guard !isLoading, !self.hasPerformedInitialScroll else { return }
            self.scrollPosition = self.scrollerBottomID
            self.hasPerformedInitialScroll = true
            self.isPinnedToBottom = true
        }
        // 会话切换时重置滚动状态
        .onChange(of: self.viewModel.sessionKey) { _, _ in
            self.hasPerformedInitialScroll = false
            self.isPinnedToBottom = true
        }
        // 用户发送消息时滚动到底部
        .onChange(of: self.viewModel.isSending) { _, isSending in
            // 用户发送消息时滚动到底部，即使已经向上滚动
            guard isSending, self.hasPerformedInitialScroll else { return }
            self.isPinnedToBottom = true
            withAnimation(.snappy(duration: 0.22)) {
                self.scrollPosition = self.scrollerBottomID
            }
        }
        // 消息数量变化时处理滚动
        .onChange(of: self.viewModel.messages.count) { _, _ in
            guard self.hasPerformedInitialScroll else { return }
            // 处理用户消息的特殊情况
            if let lastMessage = self.viewModel.messages.last,
               lastMessage.role.lowercased() == "user",
               lastMessage.id != self.lastUserMessageID {
                self.lastUserMessageID = lastMessage.id
                self.isPinnedToBottom = true
                withAnimation(.snappy(duration: 0.22)) {
                    self.scrollPosition = self.scrollerBottomID
                }
                return
            }

            // 只有当固定在底部时才滚动
            guard self.isPinnedToBottom else { return }
            withAnimation(.snappy(duration: 0.22)) {
                self.scrollPosition = self.scrollerBottomID
            }
        }
        // 待处理运行计数变化时滚动
        .onChange(of: self.viewModel.pendingRunCount) { _, _ in
            guard self.hasPerformedInitialScroll, self.isPinnedToBottom else { return }
            withAnimation(.snappy(duration: 0.22)) {
                self.scrollPosition = self.scrollerBottomID
            }
        }
        // 助手流式文本变化时滚动
        .onChange(of: self.viewModel.streamingAssistantText) { _, _ in
            guard self.hasPerformedInitialScroll, self.isPinnedToBottom else { return }
            withAnimation(.snappy(duration: 0.22)) {
                self.scrollPosition = self.scrollerBottomID
            }
        }
    }

    /// 消息列表行视图
    @ViewBuilder
    private var messageListRows: some View {
        // 渲染可见消息
        ForEach(self.visibleMessages) { msg in
            ChatMessageBubble(
                message: msg,
                style: self.style,
                markdownVariant: self.markdownVariant,
                userAccent: self.userAccent)
                .frame(
                    maxWidth: .infinity,
                    alignment: msg.role.lowercased() == "user" ? .trailing : .leading)
        }

        // 显示输入指示器
        if self.viewModel.pendingRunCount > 0 {
            HStack {
                ChatTypingIndicatorBubble(style: self.style)
                    .equatable()
                Spacer(minLength: 0)
            }
        }

        // 显示待处理工具调用
        if !self.viewModel.pendingToolCalls.isEmpty {
            ChatPendingToolsBubble(toolCalls: self.viewModel.pendingToolCalls)
                .equatable()
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        // 显示流式助手消息
        if let text = self.viewModel.streamingAssistantText, AssistantTextParser.hasVisibleContent(in: text) {
            ChatStreamingAssistantBubble(text: text, markdownVariant: self.markdownVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 可见消息数组
    /// 处理引导模式下的特殊逻辑，并合并工具结果
    private var visibleMessages: [MoltbotChatMessage] {
        let base: [MoltbotChatMessage]
        if self.style == .onboarding {
            // 引导模式下，跳过第一条用户消息
            guard let first = self.viewModel.messages.first else { return [] }
            base = first.role.lowercased() == "user" ? Array(self.viewModel.messages.dropFirst()) : self.viewModel
                .messages
        } else {
            base = self.viewModel.messages
        }
        // 合并工具结果到对应消息
        return self.mergeToolResults(in: base)
    }

    /// 消息列表覆盖层
    /// 显示错误提示、空状态等
    @ViewBuilder
    private var messageListOverlay: some View {
        if self.viewModel.isLoading {
            EmptyView()
        } else if let error = self.activeErrorText {
            // 显示错误提示
            let presentation = self.errorPresentation(for: error)
            if self.hasVisibleMessageListContent {
                // 有内容时显示顶部横幅
                VStack(spacing: 0) {
                    ChatNoticeBanner(
                        systemImage: presentation.systemImage,
                        title: presentation.title,
                        message: error,
                        tint: presentation.tint,
                        dismiss: { self.viewModel.errorText = nil },
                        refresh: { self.viewModel.refresh() })
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                // 无内容时显示居中卡片
                ChatNoticeCard(
                    systemImage: presentation.systemImage,
                    title: presentation.title,
                    message: error,
                    tint: presentation.tint,
                    actionTitle: "刷新",
                    action: { self.viewModel.refresh() })
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if self.showsEmptyState {
            // 显示空状态
            ChatNoticeCard(
                systemImage: "bubble.left.and.bubble.right.fill",
                title: self.emptyStateTitle,
                message: self.emptyStateMessage,
                tint: .accentColor,
                actionTitle: nil,
                action: nil)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 当前活动的错误文本
    private var activeErrorText: String? {
        guard let text = self.viewModel.errorText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return nil
        }
        return text
    }

    /// 是否有可见的消息列表内容
    private var hasVisibleMessageListContent: Bool {
        if !self.visibleMessages.isEmpty {
            return true
        }
        if let text = self.viewModel.streamingAssistantText,
           AssistantTextParser.hasVisibleContent(in: text)
        {
            return true
        }
        if self.viewModel.pendingRunCount > 0 {
            return true
        }
        if !self.viewModel.pendingToolCalls.isEmpty {
            return true
        }
        return false
    }

    /// 是否显示空状态
    private var showsEmptyState: Bool {
        self.viewModel.messages.isEmpty &&
            !(self.viewModel.streamingAssistantText.map { AssistantTextParser.hasVisibleContent(in: $0) } ?? false) &&
            self.viewModel.pendingRunCount == 0 &&
            self.viewModel.pendingToolCalls.isEmpty
    }

    /// 空状态标题
    private var emptyStateTitle: String {
        #if os(macOS)
        "网页聊天"
        #else
        "聊天"
        #endif
    }

    /// 空状态消息
    private var emptyStateMessage: String {
        #if os(macOS)
        "在下方输入消息开始。\n回车发送 • Shift-回车添加换行。"
        #else
        "在下方输入消息开始。"
        #endif
    }

    /// 根据错误文本返回错误展示配置
    /// - Parameter error: 错误文本
    /// - Returns: 错误展示配置元组
    private func errorPresentation(for error: String) -> (title: String, systemImage: String, tint: Color) {
        let lower = error.lowercased()
        if lower.contains("not connected") || lower.contains("socket") {
            return ("已断开连接", "wifi.slash", .orange)
        }
        if lower.contains("timed out") {
            return ("超时", "clock.badge.exclamationmark", .orange)
        }
        return ("错误", "exclamationmark.triangle.fill", .orange)
    }

    /// 合并工具结果到对应消息
    /// - Parameter messages: 原始消息数组
    /// - Returns: 合并后的消息数组
    private func mergeToolResults(in messages: [MoltbotChatMessage]) -> [MoltbotChatMessage] {
        var result: [MoltbotChatMessage] = []
        result.reserveCapacity(messages.count)

        for message in messages {
            // 检查是否为工具结果消息
            guard self.isToolResultMessage(message) else {
                result.append(message)
                continue
            }

            // 查找对应的工具调用消息
            guard let toolCallId = message.toolCallId,
                  let last = result.last,
                  self.toolCallIds(in: last).contains(toolCallId)
            else {
                result.append(message)
                continue
            }

            // 提取工具结果文本
            let toolText = self.toolResultText(from: message)
            if toolText.isEmpty {
                continue
            }

            // 将工具结果合并到对应消息
            var content = last.content
            content.append(
                MoltbotChatMessageContent(
                    type: "tool_result",
                    text: toolText,
                    thinking: nil,
                    thinkingSignature: nil,
                    mimeType: nil,
                    fileName: nil,
                    content: nil,
                    id: toolCallId,
                    name: message.toolName,
                    arguments: nil))

            // 创建合并后的消息
            let merged = MoltbotChatMessage(
                id: last.id,
                role: last.role,
                content: content,
                timestamp: last.timestamp,
                toolCallId: last.toolCallId,
                toolName: last.toolName,
                usage: last.usage,
                stopReason: last.stopReason)
            result[result.count - 1] = merged
        }

        return result
    }

    /// 检查消息是否为工具结果消息
    /// - Parameter message: 消息对象
    /// - Returns: 是否为工具结果消息
    private func isToolResultMessage(_ message: MoltbotChatMessage) -> Bool {
        let role = message.role.lowercased()
        return role == "toolresult" || role == "tool_result"
    }

    /// 提取消息中的工具调用ID集合
    /// - Parameter message: 消息对象
    /// - Returns: 工具调用ID集合
    private func toolCallIds(in message: MoltbotChatMessage) -> Set<String> {
        var ids = Set<String>()
        for content in message.content {
            let kind = (content.type ?? "").lowercased()
            let isTool =
                ["toolcall", "tool_call", "tooluse", "tool_use"].contains(kind) ||
                (content.name != nil && content.arguments != nil)
            if isTool, let id = content.id {
                ids.insert(id)
            }
        }
        if let toolCallId = message.toolCallId {
            ids.insert(toolCallId)
        }
        return ids
    }

    /// 从消息中提取工具结果文本
    /// - Parameter message: 消息对象
    /// - Returns: 工具结果文本
    private func toolResultText(from message: MoltbotChatMessage) -> String {
        let parts = message.content.compactMap { content -> String? in
            let kind = (content.type ?? "text").lowercased()
            guard kind == "text" || kind.isEmpty else { return nil }
            return content.text
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 聊天通知卡片
/// 用于显示错误提示、空状态等信息
private struct ChatNoticeCard: View {
    let systemImage: String  // 系统图标
    let title: String  // 标题
    let message: String  // 消息内容
    let tint: Color  // 色调
    let actionTitle: String?  // 操作按钮标题
    let action: (() -> Void)?  // 操作闭包

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(self.tint.opacity(0.16))
                Image(systemName: self.systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(self.tint)
            }
            .frame(width: 52, height: 52)

            Text(self.title)
                .font(.headline)

            Text(self.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: 360)

            // 显示操作按钮
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MoltbotChatTheme.subtleCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
        .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
    }
}

/// 聊天通知横幅
/// 用于在消息列表顶部显示错误提示等信息
private struct ChatNoticeBanner: View {
    let systemImage: String  // 系统图标
    let title: String  // 标题
    let message: String  // 消息内容
    let tint: Color  // 色调
    let dismiss: () -> Void  //  dismiss 闭包
    let refresh: () -> Void  // 刷新闭包

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: self.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(self.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(self.title)
                    .font(.caption.weight(.semibold))

                Text(self.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            // 刷新按钮
            Button(action: self.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("刷新")

            // 关闭按钮
            Button(action: self.dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MoltbotChatTheme.subtleCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)))
    }
}

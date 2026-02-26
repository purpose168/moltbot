import MoltbotKit
import Foundation
import SwiftUI

// 聊天界面常量定义
private enum ChatUIConstants {
    static let bubbleMaxWidth: CGFloat = 560  // 气泡最大宽度
    static let bubbleCorner: CGFloat = 18      // 气泡圆角大小
}

// 聊天气泡形状定义
private struct ChatBubbleShape: InsettableShape {
    // 气泡尾部类型
    enum Tail {
        case left    // 左侧尾部
        case right   // 右侧尾部
        case none    // 无尾部
    }

    let cornerRadius: CGFloat  // 圆角半径
    let tail: Tail             // 尾部类型
    var insetAmount: CGFloat = 0  // 内边距

    private let tailWidth: CGFloat = 7        // 尾部宽度
    private let tailBaseHeight: CGFloat = 9   // 尾部基础高度

    // 创建带内边距的气泡形状
    func inset(by amount: CGFloat) -> ChatBubbleShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    // 生成气泡路径
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: self.insetAmount, dy: self.insetAmount)
        switch self.tail {
        case .left:
            return self.leftTailPath(in: rect, radius: self.cornerRadius)
        case .right:
            return self.rightTailPath(in: rect, radius: self.cornerRadius)
        case .none:
            return Path(roundedRect: rect, cornerRadius: self.cornerRadius)
        }
    }

    // 生成右侧尾部的路径
    private func rightTailPath(in rect: CGRect, radius r: CGFloat) -> Path {
        var path = Path()
        let bubbleMinX = rect.minX
        let bubbleMaxX = rect.maxX - self.tailWidth
        let bubbleMinY = rect.minY
        let bubbleMaxY = rect.maxY

        let available = max(4, bubbleMaxY - bubbleMinY - 2 * r)
        let baseH = min(tailBaseHeight, available)
        let baseBottomY = bubbleMaxY - max(r * 0.45, 6)
        let baseTopY = baseBottomY - baseH
        let midY = (baseTopY + baseBottomY) / 2

        let baseTop = CGPoint(x: bubbleMaxX, y: baseTopY)
        let baseBottom = CGPoint(x: bubbleMaxX, y: baseBottomY)
        let tip = CGPoint(x: bubbleMaxX + self.tailWidth, y: midY)

        path.move(to: CGPoint(x: bubbleMinX + r, y: bubbleMinY))
        path.addLine(to: CGPoint(x: bubbleMaxX - r, y: bubbleMinY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMaxX, y: bubbleMinY + r),
            control: CGPoint(x: bubbleMaxX, y: bubbleMinY))
        path.addLine(to: baseTop)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: bubbleMaxX + self.tailWidth * 0.2, y: baseTopY + baseH * 0.05),
            control2: CGPoint(x: bubbleMaxX + self.tailWidth * 0.95, y: midY - baseH * 0.15))
        path.addCurve(
            to: baseBottom,
            control1: CGPoint(x: bubbleMaxX + self.tailWidth * 0.95, y: midY + baseH * 0.15),
            control2: CGPoint(x: bubbleMaxX + self.tailWidth * 0.2, y: baseBottomY - baseH * 0.05))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMaxX - r, y: bubbleMaxY),
            control: CGPoint(x: bubbleMaxX, y: bubbleMaxY))
        path.addLine(to: CGPoint(x: bubbleMinX + r, y: bubbleMaxY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMinX, y: bubbleMaxY - r),
            control: CGPoint(x: bubbleMinX, y: bubbleMaxY))
        path.addLine(to: CGPoint(x: bubbleMinX, y: bubbleMinY + r))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMinX + r, y: bubbleMinY),
            control: CGPoint(x: bubbleMinX, y: bubbleMinY))

        return path
    }

    // 生成左侧尾部的路径
    private func leftTailPath(in rect: CGRect, radius r: CGFloat) -> Path {
        var path = Path()
        let bubbleMinX = rect.minX + self.tailWidth
        let bubbleMaxX = rect.maxX
        let bubbleMinY = rect.minY
        let bubbleMaxY = rect.maxY

        let available = max(4, bubbleMaxY - bubbleMinY - 2 * r)
        let baseH = min(tailBaseHeight, available)
        let baseBottomY = bubbleMaxY - max(r * 0.45, 6)
        let baseTopY = baseBottomY - baseH
        let midY = (baseTopY + baseBottomY) / 2

        let baseTop = CGPoint(x: bubbleMinX, y: baseTopY)
        let baseBottom = CGPoint(x: bubbleMinX, y: baseBottomY)
        let tip = CGPoint(x: bubbleMinX - self.tailWidth, y: midY)

        path.move(to: CGPoint(x: bubbleMinX + r, y: bubbleMinY))
        path.addLine(to: CGPoint(x: bubbleMaxX - r, y: bubbleMinY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMaxX, y: bubbleMinY + r),
            control: CGPoint(x: bubbleMaxX, y: bubbleMinY))
        path.addLine(to: CGPoint(x: bubbleMaxX, y: bubbleMaxY - r))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMaxX - r, y: bubbleMaxY),
            control: CGPoint(x: bubbleMaxX, y: bubbleMaxY))
        path.addLine(to: CGPoint(x: bubbleMinX + r, y: bubbleMaxY))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMinX, y: bubbleMaxY - r),
            control: CGPoint(x: bubbleMinX, y: bubbleMaxY))
        path.addLine(to: baseBottom)
        path.addCurve(
            to: tip,
            control1: CGPoint(x: bubbleMinX - self.tailWidth * 0.2, y: baseBottomY - baseH * 0.05),
            control2: CGPoint(x: bubbleMinX - self.tailWidth * 0.95, y: midY + baseH * 0.15))
        path.addCurve(
            to: baseTop,
            control1: CGPoint(x: bubbleMinX - self.tailWidth * 0.95, y: midY - baseH * 0.15),
            control2: CGPoint(x: bubbleMinX - self.tailWidth * 0.2, y: baseTopY + baseH * 0.05))
        path.addLine(to: CGPoint(x: bubbleMinX, y: bubbleMinY + r))
        path.addQuadCurve(
            to: CGPoint(x: bubbleMinX + r, y: bubbleMinY),
            control: CGPoint(x: bubbleMinX, y: bubbleMinY))

        return path
    }
}

// 聊天消息气泡视图
@MainActor
struct ChatMessageBubble: View {
    let message: MoltbotChatMessage      // 消息数据
    let style: MoltbotChatView.Style     // 聊天视图样式
    let markdownVariant: ChatMarkdownVariant  // Markdown 渲染变体
    let userAccent: Color?               // 用户强调色

    var body: some View {
        ChatMessageBody(
            message: self.message,
            isUser: self.isUser,
            style: self.style,
            markdownVariant: self.markdownVariant,
            userAccent: self.userAccent)
            .frame(maxWidth: ChatUIConstants.bubbleMaxWidth, alignment: self.isUser ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: self.isUser ? .trailing : .leading)
            .padding(.horizontal, 2)
    }

    // 判断是否为用户消息
    private var isUser: Bool { self.message.role.lowercased() == "user" }
}

// 聊天消息内容视图
@MainActor
private struct ChatMessageBody: View {
    let message: MoltbotChatMessage      // 消息数据
    let isUser: Bool                     // 是否为用户消息
    let style: MoltbotChatView.Style     // 聊天视图样式
    let markdownVariant: ChatMarkdownVariant  // Markdown 渲染变体
    let userAccent: Color?               // 用户强调色

    var body: some View {
        let text = self.primaryText
        let textColor = self.isUser ? MoltbotChatTheme.userText : MoltbotChatTheme.assistantText

        VStack(alignment: .leading, spacing: 10) {
            // 工具结果消息
            if self.isToolResultMessage {
                if !text.isEmpty {
                    ToolResultCard(
                        title: self.toolResultTitle,
                        text: text,
                        isUser: self.isUser)
                }
            } else if self.isUser {
                // 用户消息
                ChatMarkdownRenderer(
                    text: text,
                    context: .user,
                    variant: self.markdownVariant,
                    font: .system(size: 14),
                    textColor: textColor)
            } else {
                // 助手消息
                ChatAssistantTextBody(text: text, markdownVariant: self.markdownVariant)
            }

            // 内联附件
            if !self.inlineAttachments.isEmpty {
                ForEach(self.inlineAttachments.indices, id: \.self) { idx in
                    AttachmentRow(att: self.inlineAttachments[idx], isUser: self.isUser)
                }
            }

            // 工具调用
            if !self.toolCalls.isEmpty {
                ForEach(self.toolCalls.indices, id: \.self) { idx in
                    ToolCallCard(
                        content: self.toolCalls[idx],
                        isUser: self.isUser)
                }
            }

            // 内联工具结果
            if !self.inlineToolResults.isEmpty {
                ForEach(self.inlineToolResults.indices, id: \.self) { idx in
                    let toolResult = self.inlineToolResults[idx]
                    let display = ToolDisplayRegistry.resolve(name: toolResult.name ?? "tool", args: nil)
                    ToolResultCard(
                        title: "\(display.emoji) \(display.title)",
                        text: toolResult.text ?? "",
                        isUser: self.isUser)
                }
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .foregroundStyle(textColor)
        .background(self.bubbleBackground)
        .clipShape(self.bubbleShape)
        .overlay(self.bubbleBorder)
        .shadow(color: self.bubbleShadowColor, radius: self.bubbleShadowRadius, y: self.bubbleShadowYOffset)
        .padding(.leading, self.tailPaddingLeading)
        .padding(.trailing, self.tailPaddingTrailing)
    }

    // 获取主要文本内容
    private var primaryText: String {
        let parts = self.message.content.compactMap { content -> String? in
            let kind = (content.type ?? "text").lowercased()
            guard kind == "text" || kind.isEmpty else { return nil }
            return content.text
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 获取内联附件
    private var inlineAttachments: [MoltbotChatMessageContent] {
        self.message.content.filter { content in
            switch content.type ?? "text" {
            case "file", "attachment":
                true
            default:
                false
            }
        }
    }

    // 获取工具调用
    private var toolCalls: [MoltbotChatMessageContent] {
        self.message.content.filter { content in
            let kind = (content.type ?? "").lowercased()
            if ["toolcall", "tool_call", "tooluse", "tool_use"].contains(kind) {
                return true
            }
            return content.name != nil && content.arguments != nil
        }
    }

    // 获取内联工具结果
    private var inlineToolResults: [MoltbotChatMessageContent] {
        self.message.content.filter { content in
            let kind = (content.type ?? "").lowercased()
            return kind == "toolresult" || kind == "tool_result"
        }
    }

    // 判断是否为工具结果消息
    private var isToolResultMessage: Bool {
        let role = self.message.role.lowercased()
        return role == "toolresult" || role == "tool_result"
    }

    // 获取工具结果标题
    private var toolResultTitle: String {
        if let name = self.message.toolName, !name.isEmpty {
            let display = ToolDisplayRegistry.resolve(name: name, args: nil)
            return "\(display.emoji) \(display.title)"
        }
        let display = ToolDisplayRegistry.resolve(name: "tool", args: nil)
        return "\(display.emoji) \(display.title)"
    }

    // 获取气泡填充颜色
    private var bubbleFillColor: Color {
        if self.isUser {
            return self.userAccent ?? MoltbotChatTheme.userBubble
        }
        if self.style == .onboarding {
            return MoltbotChatTheme.onboardingAssistantBubble
        }
        return MoltbotChatTheme.assistantBubble
    }

    // 获取气泡背景
    private var bubbleBackground: AnyShapeStyle {
        AnyShapeStyle(self.bubbleFillColor)
    }

    // 获取气泡边框颜色
    private var bubbleBorderColor: Color {
        if self.isUser {
            return Color.white.opacity(0.12)
        }
        if self.style == .onboarding {
            return MoltbotChatTheme.onboardingAssistantBorder
        }
        return Color.white.opacity(0.08)
    }

    // 获取气泡边框宽度
    private var bubbleBorderWidth: CGFloat {
        if self.isUser { return 0.5 }
        if self.style == .onboarding { return 0.8 }
        return 1
    }

    // 获取气泡边框
    private var bubbleBorder: some View {
        self.bubbleShape.strokeBorder(self.bubbleBorderColor, lineWidth: self.bubbleBorderWidth)
    }

    // 获取气泡形状
    private var bubbleShape: ChatBubbleShape {
        ChatBubbleShape(cornerRadius: ChatUIConstants.bubbleCorner, tail: self.bubbleTail)
    }

    // 获取气泡尾部类型
    private var bubbleTail: ChatBubbleShape.Tail {
        guard self.style == .onboarding else { return .none }
        return self.isUser ? .right : .left
    }

    // 获取尾部左侧内边距
    private var tailPaddingLeading: CGFloat {
        self.style == .onboarding && !self.isUser ? 8 : 0
    }

    // 获取尾部右侧内边距
    private var tailPaddingTrailing: CGFloat {
        self.style == .onboarding && self.isUser ? 8 : 0
    }

    // 获取气泡阴影颜色
    private var bubbleShadowColor: Color {
        self.style == .onboarding && !self.isUser ? Color.black.opacity(0.28) : .clear
    }

    // 获取气泡阴影半径
    private var bubbleShadowRadius: CGFloat {
        self.style == .onboarding && !self.isUser ? 6 : 0
    }

    // 获取气泡阴影Y偏移
    private var bubbleShadowYOffset: CGFloat {
        self.style == .onboarding && !self.isUser ? 2 : 0
    }
}

// 附件行视图
private struct AttachmentRow: View {
    let att: MoltbotChatMessageContent  // 附件内容
    let isUser: Bool                     // 是否为用户消息

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "paperclip")  // 附件图标
            Text(self.att.fileName ?? "Attachment")  // 附件文件名
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(self.isUser ? MoltbotChatTheme.userText : MoltbotChatTheme.assistantText)
            Spacer()
        }
        .padding(10)
        .background(self.isUser ? Color.white.opacity(0.2) : Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// 工具调用卡片视图
private struct ToolCallCard: View {
    let content: MoltbotChatMessageContent  // 工具调用内容
    let isUser: Bool                         // 是否为用户消息

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(self.toolName)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            }

            if let summary = self.summary, !summary.isEmpty {
                Text(summary)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MoltbotChatTheme.subtleCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }

    // 获取工具名称
    private var toolName: String {
        "\(self.display.emoji) \(self.display.title)"
    }

    // 获取工具摘要
    private var summary: String? {
        self.display.detailLine
    }

    // 获取工具显示信息
    private var display: ToolDisplaySummary {
        ToolDisplayRegistry.resolve(name: self.content.name ?? "tool", args: self.content.arguments)
    }
}

// 工具结果卡片视图
private struct ToolResultCard: View {
    let title: String  // 工具结果标题
    let text: String   // 工具结果文本
    let isUser: Bool   // 是否为用户消息
    @State private var expanded = false  // 是否展开

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(self.title)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
            }

            Text(self.displayText)
                .font(.footnote.monospaced())
                .foregroundStyle(self.isUser ? MoltbotChatTheme.userText : MoltbotChatTheme.assistantText)
                .lineLimit(self.expanded ? nil : Self.previewLineLimit)

            // 展开/收起按钮
            if self.shouldShowToggle {
                Button(self.expanded ? "显示更少" : "显示完整输出") {
                    self.expanded.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MoltbotChatTheme.subtleCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)))
    }

    private static let previewLineLimit = 8  // 预览行数限制

    // 获取文本行数
    private var lines: [Substring] {
        self.text.components(separatedBy: .newlines).map { Substring($0) }
    }

    // 获取显示文本
    private var displayText: String {
        guard !self.expanded, self.lines.count > Self.previewLineLimit else { return self.text }
        return self.lines.prefix(Self.previewLineLimit).joined(separator: "\n") + "\n…"
    }

    // 判断是否显示展开/收起按钮
    private var shouldShowToggle: Bool {
        self.lines.count > Self.previewLineLimit
    }
}

// 输入指示器气泡视图
@MainActor
struct ChatTypingIndicatorBubble: View {
    let style: MoltbotChatView.Style  // 聊天视图样式

    var body: some View {
        HStack(spacing: 10) {
            TypingDots()  // 输入点动画
            if self.style == .standard {
                Text("Clawd 正在思考…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.vertical, self.style == .standard ? 12 : 10)
        .padding(.horizontal, self.style == .standard ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MoltbotChatTheme.assistantBubble))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: ChatUIConstants.bubbleMaxWidth, alignment: .leading)
        .focusable(false)
    }
}

// 输入指示器气泡视图的Equatable实现
@MainActor
extension ChatTypingIndicatorBubble: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.style == rhs.style
    }
}

// 流式助手气泡视图
@MainActor
struct ChatStreamingAssistantBubble: View {
    let text: String                     // 助手文本
    let markdownVariant: ChatMarkdownVariant  // Markdown 渲染变体

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatAssistantTextBody(text: self.text, markdownVariant: self.markdownVariant)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MoltbotChatTheme.assistantBubble))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: ChatUIConstants.bubbleMaxWidth, alignment: .leading)
        .focusable(false)
    }
}

// 待处理工具气泡视图
@MainActor
struct ChatPendingToolsBubble: View {
    let toolCalls: [MoltbotChatPendingToolCall]  // 待处理工具调用

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("正在运行工具…", systemImage: "hammer")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(self.toolCalls) { call in
                let display = ToolDisplayRegistry.resolve(name: call.name, args: call.args)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(display.emoji) \(display.label)")
                            .font(.footnote.monospaced())
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        ProgressView().controlSize(.mini)  // 进度指示器
                    }
                    if let detail = display.detailLine, !detail.isEmpty {
                        Text(detail)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(MoltbotChatTheme.assistantBubble))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: ChatUIConstants.bubbleMaxWidth, alignment: .leading)
        .focusable(false)
    }
}

// 待处理工具气泡视图的Equatable实现
@MainActor
extension ChatPendingToolsBubble: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.toolCalls == rhs.toolCalls
    }
}

// 输入点动画视图
@MainActor
private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion  // 无障碍减少动画
    @Environment(\.scenePhase) private var scenePhase                    // 场景阶段
    @State private var animate = false                                   // 是否动画

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { idx in
                Circle()
                    .fill(Color.secondary.opacity(0.55))
                    .frame(width: 7, height: 7)
                    .scaleEffect(self.reduceMotion ? 0.85 : (self.animate ? 1.05 : 0.70))
                    .opacity(self.reduceMotion ? 0.55 : (self.animate ? 0.95 : 0.30))
                    .animation(
                        self.reduceMotion ? nil : .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(idx) * 0.16),
                        value: self.animate)
            }
        }
        .onAppear { self.updateAnimationState() }
        .onDisappear { self.animate = false }
        .onChange(of: self.scenePhase) { _, _ in
            self.updateAnimationState()
        }
        .onChange(of: self.reduceMotion) { _, _ in
            self.updateAnimationState()
        }
    }

    // 更新动画状态
    private func updateAnimationState() {
        guard !self.reduceMotion, self.scenePhase == .active else {
            self.animate = false
            return
        }
        self.animate = true
    }
}

// 助手文本内容视图
private struct ChatAssistantTextBody: View {
    let text: String                     // 文本内容
    let markdownVariant: ChatMarkdownVariant  // Markdown 渲染变体

    var body: some View {
        let segments = AssistantTextParser.segments(from: self.text)  // 解析文本段
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                let font = segment.kind == .thinking ? Font.system(size: 14).italic() : Font.system(size: 14)
                ChatMarkdownRenderer(
                    text: segment.text,
                    context: .assistant,
                    variant: self.markdownVariant,
                    font: font,
                    textColor: MoltbotChatTheme.assistantText)
            }
        }
    }
}

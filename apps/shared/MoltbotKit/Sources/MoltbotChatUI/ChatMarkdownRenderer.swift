import SwiftUI
import Textual

/// Markdown渲染变体枚举
/// - standard: 标准渲染模式
/// - compact: 紧凑渲染模式
public enum ChatMarkdownVariant: String, CaseIterable, Sendable {
    case standard
    case compact
}

/// Markdown渲染器视图
/// 用于在聊天界面中渲染Markdown格式的文本
@MainActor
struct ChatMarkdownRenderer: View {
    /// 上下文枚举
    /// - user: 用户消息
    /// - assistant: 助手消息
    enum Context {
        case user
        case assistant
    }

    /// 要渲染的文本内容
    let text: String
    /// 消息上下文（用户或助手）
    let context: Context
    /// Markdown渲染变体
    let variant: ChatMarkdownVariant
    /// 字体设置
    let font: Font
    /// 文本颜色
    let textColor: Color

    var body: some View {
        // 预处理Markdown文本
        let processed = ChatMarkdownPreprocessor.preprocess(markdown: self.text)
        VStack(alignment: .leading, spacing: 10) {
            // 渲染结构化文本
            StructuredText(markdown: processed.cleaned)
                .modifier(ChatMarkdownStyle(
                    variant: self.variant,
                    context: self.context,
                    font: self.font,
                    textColor: self.textColor))

            // 如果有图像，显示图像列表
            if !processed.images.isEmpty {
                InlineImageList(images: processed.images)
            }
        }
    }
}

/// Markdown样式修饰符
/// 用于为Markdown文本应用样式
private struct ChatMarkdownStyle: ViewModifier {
    /// Markdown渲染变体
    let variant: ChatMarkdownVariant
    /// 消息上下文
    let context: ChatMarkdownRenderer.Context
    /// 字体设置
    let font: Font
    /// 文本颜色
    let textColor: Color

    func body(content: Content) -> some View {
        Group {
            // 根据变体选择不同的结构化文本样式
            if self.variant == .compact {
                content.textual.structuredTextStyle(.default)
            } else {
                content.textual.structuredTextStyle(.gitHub)
            }
        }
        .font(self.font)                    // 应用字体
        .foregroundStyle(self.textColor)    // 应用文本颜色
        .textual.inlineStyle(self.inlineStyle)  // 应用内联样式
        .textual.textSelection(.enabled)    // 启用文本选择
    }

    /// 内联样式配置
    private var inlineStyle: InlineStyle {
        // 根据上下文确定链接颜色
        let linkColor: Color = self.context == .user ? self.textColor : .accentColor
        // 根据变体确定代码字体缩放比例
        let codeScale: CGFloat = self.variant == .compact ? 0.85 : 0.9
        return InlineStyle()
            .code(.monospaced, .fontScale(codeScale))  // 配置代码样式
            .link(.foregroundColor(linkColor))         // 配置链接样式
    }
}

/// 内联图像列表视图
/// 用于显示Markdown中的内联图像
@MainActor
private struct InlineImageList: View {
    /// 图像数组
    let images: [ChatMarkdownPreprocessor.InlineImage]

    var body: some View {
        // 遍历所有图像
        ForEach(images, id: \.id) { item in
            if let img = item.image {
                // 如果有图像数据，显示图像
                MoltbotPlatformImageFactory.image(img)
                    .resizable()           // 可调整大小
                    .scaledToFit()         // 适应容器
                    .frame(maxHeight: 260)  // 最大高度限制
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))  // 圆角裁剪
                    .overlay(
                        // 添加边框效果
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            } else {
                // 如果没有图像数据，显示标签
                Text(item.label.isEmpty ? "Image" : item.label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

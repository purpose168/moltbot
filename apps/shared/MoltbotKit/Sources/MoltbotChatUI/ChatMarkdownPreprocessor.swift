import Foundation

/// Markdown 预处理工具，用于提取和处理聊天中的 Markdown 内容
enum ChatMarkdownPreprocessor {
    /// 内联图片结构，用于表示从 Markdown 中提取的图片
    struct InlineImage: Identifiable {
        let id = UUID() /// 唯一标识符
        let label: String /// 图片标签/替代文本
        let image: MoltbotPlatformImage? /// 解码后的图片对象
    }

    /// 预处理结果结构
    struct Result {
        let cleaned: String /// 清理后的文本（移除了图片标记）
        let images: [InlineImage] /// 提取的图片数组
    }

    /// 预处理 Markdown 文本，提取其中的内联图片
    /// - Parameter raw: 原始 Markdown 文本
    /// - Returns: 包含清理后文本和提取图片的结果
    static func preprocess(markdown raw: String) -> Result {
        // 正则表达式模式，用于匹配内联图片语法：![标签](data:image/...;base64,...)
        let pattern = #"!\[([^\]]*)\]\((data:image\/[^;]+;base64,[^)]+)\)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            // 如果正则表达式创建失败，返回原始文本和空图片数组
            return Result(cleaned: raw, images: [])
        }

        let ns = raw as NSString
        // 查找所有匹配的内联图片
        let matches = re.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return Result(cleaned: raw, images: []) }

        var images: [InlineImage] = []
        var cleaned = raw

        // 反向遍历匹配结果，避免修改字符串时影响后续匹配的位置
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            // 提取图片标签
            let label = ns.substring(with: match.range(at: 1))
            // 提取 data URL
            let dataURL = ns.substring(with: match.range(at: 2))

            // 从 data URL 中解码图片
            let image: MoltbotPlatformImage? = {
                guard let comma = dataURL.firstIndex(of: ",") else { return nil }
                // 提取 base64 编码部分
                let b64 = String(dataURL[dataURL.index(after: comma)...])
                // 解码 base64 数据
                guard let data = Data(base64Encoded: b64) else { return nil }
                // 创建图片对象
                return MoltbotPlatformImage(data: data)
            }()
            // 添加到图片数组
            images.append(InlineImage(label: label, image: image))

            // 从原始文本中移除图片标记
            let start = cleaned.index(cleaned.startIndex, offsetBy: match.range.location)
            let end = cleaned.index(start, offsetBy: match.range.length)
            cleaned.replaceSubrange(start..<end, with: "")
        }

        // 标准化文本：移除多余的空行并修剪首尾空白
        let normalized = cleaned
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 返回结果，注意图片数组需要反转（因为我们是反向遍历的）
        return Result(cleaned: normalized, images: images.reversed())
    }
}

import Foundation

/// 助手文本段落，用于区分思考和响应内容
struct AssistantTextSegment: Identifiable {
    /// 段落类型枚举
    enum Kind {
        case thinking  // 思考内容
        case response  // 响应内容
    }

    let id = UUID()  // 唯一标识符
    let kind: Kind  // 段落类型
    let text: String  // 段落文本
}

/// 助手文本解析器，用于解析原始文本并生成段落数组
enum AssistantTextParser {
    /// 从原始文本生成段落数组
    /// - Parameter raw: 原始文本
    /// - Returns: 解析后的段落数组
    static func segments(from raw: String) -> [AssistantTextSegment] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard raw.contains("<") else {
            return [AssistantTextSegment(kind: .response, text: trimmed)]
        }

        var segments: [AssistantTextSegment] = []
        var cursor = raw.startIndex
        var currentKind: AssistantTextSegment.Kind = .response
        var matchedTag = false

        while let match = self.nextTag(in: raw, from: cursor) {
            matchedTag = true
            if match.range.lowerBound > cursor {
                self.appendSegment(kind: currentKind, text: raw[cursor..<match.range.lowerBound], to: &segments)
            }

            guard let tagEnd = raw.range(of: ">", range: match.range.upperBound..<raw.endIndex) else {
                cursor = raw.endIndex
                break
            }

            let isSelfClosing = self.isSelfClosingTag(in: raw, tagEnd: tagEnd)
            cursor = tagEnd.upperBound
            if isSelfClosing { continue }

            if match.closing {
                currentKind = .response
            } else {
                currentKind = match.kind == .think ? .thinking : .response
            }
        }

        if cursor < raw.endIndex {
            self.appendSegment(kind: currentKind, text: raw[cursor..<raw.endIndex], to: &segments)
        }

        guard matchedTag else {
            return [AssistantTextSegment(kind: .response, text: trimmed)]
        }

        return segments
    }

    /// 检查原始文本是否包含可见内容
    /// - Parameter raw: 原始文本
    /// - Returns: 是否包含可见内容
    static func hasVisibleContent(in raw: String) -> Bool {
        !self.segments(from: raw).isEmpty
    }

    /// 标签类型枚举
    private enum TagKind {
        case think  // 思考标签
        case final  // 最终响应标签
    }

    /// 标签匹配结果
    private struct TagMatch {
        let kind: TagKind  // 标签类型
        let closing: Bool  // 是否为关闭标签
        let range: Range<String.Index>  // 标签在文本中的范围
    }

    /// 查找下一个标签
    /// - Parameters:
    ///   - text: 文本
    ///   - start: 开始查找的位置
    /// - Returns: 标签匹配结果
    private static func nextTag(in text: String, from start: String.Index) -> TagMatch? {
        let candidates: [TagMatch] = [
            self.findTagStart(tag: "think", closing: false, in: text, from: start).map {
                TagMatch(kind: .think, closing: false, range: $0)
            },
            self.findTagStart(tag: "think", closing: true, in: text, from: start).map {
                TagMatch(kind: .think, closing: true, range: $0)
            },
            self.findTagStart(tag: "final", closing: false, in: text, from: start).map {
                TagMatch(kind: .final, closing: false, range: $0)
            },
            self.findTagStart(tag: "final", closing: true, in: text, from: start).map {
                TagMatch(kind: .final, closing: true, range: $0)
            },
        ].compactMap(\.self)

        return candidates.min { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// 查找标签开始位置
    /// - Parameters:
    ///   - tag: 标签名称
    ///   - closing: 是否为关闭标签
    ///   - text: 文本
    ///   - start: 开始查找的位置
    /// - Returns: 标签在文本中的范围
    private static func findTagStart(
        tag: String,
        closing: Bool,
        in text: String,
        from start: String.Index) -> Range<String.Index>?
    {
        let token = closing ? "</\(tag)" : "<\(tag)"
        var searchRange = start..<text.endIndex
        while let range = text.range(
            of: token,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange)
        {
            let boundaryIndex = range.upperBound
            guard boundaryIndex < text.endIndex else { return range }
            let boundary = text[boundaryIndex]
            let isBoundary = boundary == ">" || boundary.isWhitespace || (!closing && boundary == "/")
            if isBoundary {
                return range
            }
            searchRange = boundaryIndex..<text.endIndex
        }
        return nil
    }

    /// 检查是否为自闭合标签
    /// - Parameters:
    ///   - text: 文本
    ///   - tagEnd: 标签结束位置
    /// - Returns: 是否为自闭合标签
    private static func isSelfClosingTag(in text: String, tagEnd: Range<String.Index>) -> Bool {
        var cursor = tagEnd.lowerBound
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            let char = text[cursor]
            if char.isWhitespace { continue }
            return char == "/"
        }
        return false
    }

    /// 追加段落到数组
    /// - Parameters:
    ///   - kind: 段落类型
    ///   - text: 段落文本
    ///   - segments: 段落数组
    private static func appendSegment(
        kind: AssistantTextSegment.Kind,
        text: Substring,
        to segments: inout [AssistantTextSegment])
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments.append(AssistantTextSegment(kind: kind, text: trimmed))
    }
}

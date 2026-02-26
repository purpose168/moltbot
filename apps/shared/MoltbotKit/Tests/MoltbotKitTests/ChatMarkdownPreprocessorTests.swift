import Testing
@testable import MoltbotChatUI

/// 测试套件：ChatMarkdownPreprocessor 功能测试
@Suite("ChatMarkdownPreprocessor")
struct ChatMarkdownPreprocessorTests {
    /// 测试从 Markdown 中提取 Data URL 格式的图片
    @Test func extractsDataURLImages() {
        // 一个简单的 base64 编码的 PNG 图片数据（1x1 像素）
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4////GQAJ+wP/2hN8NwAAAABJRU5ErkJggg=="
        // 包含文本和 Data URL 图片的 Markdown 内容
        let markdown = """
        Hello

        ![Pixel](data:image/png;base64,\(base64))
        """

        // 调用预处理方法处理 Markdown 内容
        let result = ChatMarkdownPreprocessor.preprocess(markdown: markdown)

        // 验证处理结果：清理后的文本只包含 "Hello"
        #expect(result.cleaned == "Hello")
        // 验证处理结果：成功提取出 1 张图片
        #expect(result.images.count == 1)
        // 验证处理结果：提取的图片对象不为空
        #expect(result.images.first?.image != nil)
    }
}

import XCTest
@testable import MoltbotKit

/// 测试 TalkDirectiveParser 的功能
final class TalkDirectiveTests: XCTestCase {
    /// 测试解析指令并移除指令行
    func testParsesDirectiveAndStripsLine() {
        let text = """
        {"voice":"abc123","once":true}
        Hello there.
        """
        let result = TalkDirectiveParser.parse(text)
        XCTAssertEqual(result.directive?.voiceId, "abc123")  // 验证语音 ID 解析正确
        XCTAssertEqual(result.directive?.once, true)         // 验证 once 参数解析正确
        XCTAssertEqual(result.stripped, "Hello there.")     // 验证指令行被正确移除
    }

    /// 测试忽略非指令内容
    func testIgnoresNonDirective() {
        let text = "Hello world."
        let result = TalkDirectiveParser.parse(text)
        XCTAssertNil(result.directive)            // 验证没有解析出指令
        XCTAssertEqual(result.stripped, text)     // 验证原始文本保持不变
    }

    /// 测试当没有识别的字段时保留指令行
    func testKeepsDirectiveLineIfNoRecognizedFields() {
        let text = """
        {"unknown":"value"}
        Hello.
        """
        let result = TalkDirectiveParser.parse(text)
        XCTAssertNil(result.directive)            // 验证没有解析出指令
        XCTAssertEqual(result.stripped, text)     // 验证原始文本保持不变
    }

    /// 测试解析扩展选项
    func testParsesExtendedOptions() {
        let text = """
        {"voice_id":"v1","model_id":"m1","rate":200,"stability":0.5,"similarity":0.8,"style":0.2,"speaker_boost":true,"seed":1234,"normalize":"auto","lang":"en","output_format":"mp3_44100_128"}
        Hello.
        """
        let result = TalkDirectiveParser.parse(text)
        XCTAssertEqual(result.directive?.voiceId, "v1")              // 验证语音 ID
        XCTAssertEqual(result.directive?.modelId, "m1")              // 验证模型 ID
        XCTAssertEqual(result.directive?.rateWPM, 200)                // 验证语速（词/分钟）
        XCTAssertEqual(result.directive?.stability, 0.5)              // 验证稳定性
        XCTAssertEqual(result.directive?.similarity, 0.8)             // 验证相似度
        XCTAssertEqual(result.directive?.style, 0.2)                  // 验证风格
        XCTAssertEqual(result.directive?.speakerBoost, true)          // 验证说话人增强
        XCTAssertEqual(result.directive?.seed, 1234)                  // 验证随机种子
        XCTAssertEqual(result.directive?.normalize, "auto")           // 验证归一化设置
        XCTAssertEqual(result.directive?.language, "en")              // 验证语言
        XCTAssertEqual(result.directive?.outputFormat, "mp3_44100_128") // 验证输出格式
        XCTAssertEqual(result.stripped, "Hello.")                    // 验证指令行被移除
    }

    /// 测试解析指令时跳过开头的空行
    func testSkipsLeadingEmptyLinesWhenParsingDirective() {
        let text = """


        {"voice":"abc123"}
        Hello there.
        """
        let result = TalkDirectiveParser.parse(text)
        XCTAssertEqual(result.directive?.voiceId, "abc123")  // 验证语音 ID 解析正确
        XCTAssertEqual(result.stripped, "Hello there.")     // 验证指令行被正确移除
    }

    /// 测试追踪未知键
    func testTracksUnknownKeys() {
        let text = """
        {"voice":"abc","mystery":"value","extra":1}
        Hi.
        """
        let result = TalkDirectiveParser.parse(text)
        XCTAssertEqual(result.directive?.voiceId, "abc")     // 验证语音 ID 解析正确
        XCTAssertEqual(result.unknownKeys, ["extra", "mystery"])  // 验证未知键被正确追踪
    }
}

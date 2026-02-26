import XCTest
@testable import MoltbotKit

final class ElevenLabsTTSValidationTests: XCTestCase {
    /// 测试验证输出格式只允许 MP3 预设格式
    func testValidatedOutputFormatAllowsOnlyMp3Presets() {
        XCTAssertEqual(ElevenLabsTTSClient.validatedOutputFormat("mp3_44100_128"), "mp3_44100_128")
        XCTAssertEqual(ElevenLabsTTSClient.validatedOutputFormat("pcm_16000"), "pcm_16000")
    }

    /// 测试验证语言代码只接受两个字母的代码
    func testValidatedLanguageAcceptsTwoLetterCodes() {
        XCTAssertEqual(ElevenLabsTTSClient.validatedLanguage("EN"), "en")
        XCTAssertNil(ElevenLabsTTSClient.validatedLanguage("eng"))
    }

    /// 测试验证归一化只接受已知值
    func testValidatedNormalizeAcceptsKnownValues() {
        XCTAssertEqual(ElevenLabsTTSClient.validatedNormalize("AUTO"), "auto")
        XCTAssertNil(ElevenLabsTTSClient.validatedNormalize("maybe"))
    }
}

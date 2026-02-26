import MoltbotKit
import Testing

/// Bonjour 转义序列测试套件
@Suite struct BonjourEscapesTests {
    /// 测试基本解码功能 - 普通字符串直接通过
    @Test func decodePassThrough() {
        #expect(BonjourEscapes.decode("hello") == "hello")  // 普通字符串应保持不变
        #expect(BonjourEscapes.decode("") == "")  // 空字符串应保持不变
    }

    /// 测试解码空格转义序列
    @Test func decodeSpaces() {
        #expect(BonjourEscapes.decode("Moltbot\\032Gateway") == "Moltbot Gateway")  // \032 应解码为空格
    }

    /// 测试解码多个转义序列
    @Test func decodeMultipleEscapes() {
        #expect(BonjourEscapes.decode("A\\038B\\047C\\032D") == "A&B/C D")  // 解码多个不同的转义序列
    }

    /// 测试忽略无效的转义序列
    @Test func decodeIgnoresInvalidEscapeSequences() {
        #expect(BonjourEscapes.decode("Hello\\03World") == "Hello\\03World")  // 无效的转义序列应保持不变
        #expect(BonjourEscapes.decode("Hello\\XYZWorld") == "Hello\\XYZWorld")  // 无效的转义序列应保持不变
    }

    /// 测试使用十进制 Unicode 标量值进行解码
    @Test func decodeUsesDecimalUnicodeScalarValue() {
        #expect(BonjourEscapes.decode("Hello\\065World") == "HelloAWorld")  // \065 应解码为 'A'（ASCII 值 65）
    }
}

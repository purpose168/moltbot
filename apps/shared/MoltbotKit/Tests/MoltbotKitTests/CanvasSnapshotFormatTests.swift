import MoltbotKit
import Foundation
import Testing

/// 画布快照格式测试套件
/// 测试MoltbotCanvasSnapshotFormat的各种格式解析功能
@Suite struct CanvasSnapshotFormatTests {
    /// 测试是否接受jpg作为jpeg的别名
    /// 验证JSON解析时，"jpg"格式能正确映射到.jpeg枚举值
    @Test func acceptsJpgAlias() throws {
        /// 用于JSON解码的包装结构体
        struct Wrapper: Codable {
            var format: MoltbotCanvasSnapshotFormat
        }

        // 创建包含jpg格式的JSON数据
        let data = try #require("{\"format\":\"jpg\"}".data(using: .utf8))
        // 解码JSON数据到Wrapper结构体
        let decoded = try JSONDecoder().decode(Wrapper.self, from: data)
        // 验证解码后的格式是否为.jpeg
        #expect(decoded.format == .jpeg)
    }
}

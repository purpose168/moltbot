import XCTest
@testable import MoltbotKit

/// 测试 TalkHistoryTimestamp 时间戳处理类的功能
final class TalkHistoryTimestampTests: XCTestCase {
    /// 测试秒级时间戳的小公差接受情况
    /// 验证 isAfter 方法在处理接近阈值的秒级时间戳时的行为
    func testSecondsTimestampsAreAcceptedWithSmallTolerance() {
        // 测试接近阈值的时间戳（相差0.4秒）应该被接受
        XCTAssertTrue(TalkHistoryTimestamp.isAfter(999.6, sinceSeconds: 1000))
        // 测试超出公差范围的时间戳（相差0.6秒）应该被拒绝
        XCTAssertFalse(TalkHistoryTimestamp.isAfter(999.4, sinceSeconds: 1000))
    }

    /// 测试毫秒级时间戳的小公差接受情况
    /// 验证 isAfter 方法在处理接近阈值的毫秒级时间戳时的行为
    func testMillisecondsTimestampsAreAcceptedWithSmallTolerance() {
        // 设置基准时间（秒）
        let sinceSeconds = 1_700_000_000.0
        // 转换为毫秒
        let sinceMs = sinceSeconds * 1000
        // 测试接近阈值的时间戳（相差500毫秒）应该被接受
        XCTAssertTrue(TalkHistoryTimestamp.isAfter(sinceMs - 500, sinceSeconds: sinceSeconds))
        // 测试超出公差范围的时间戳（相差501毫秒）应该被拒绝
        XCTAssertFalse(TalkHistoryTimestamp.isAfter(sinceMs - 501, sinceSeconds: sinceSeconds))
    }
}

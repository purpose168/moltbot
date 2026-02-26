import Foundation

/// 人类友好的时间间隔字符串（例如 "2分钟前"）
/// - Parameters:
///   - date: 要计算时间间隔的日期
///   - now: 当前日期，默认为当前时间
/// - Returns: 格式化后的时间间隔字符串
func age(from date: Date, now: Date = .init()) -> String {
    // 计算时间间隔（秒）
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    let minutes = seconds / 60
    let hours = minutes / 60
    let days = hours / 24

    // 根据时间间隔返回相应的字符串
    if seconds < 60 { return "刚刚" }
    if minutes == 1 { return "1分钟前" }
    if minutes < 60 { return "\(minutes)分钟前" }
    if hours == 1 { return "1小时前" }
    if hours < 24 { return "\(hours)小时前" }
    if days == 1 { return "昨天" }
    return "\(days)天前"
}

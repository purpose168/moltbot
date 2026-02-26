import SwiftUI

/// CronSettings 辅助方法扩展
/// 
/// 包含 CronSettings 的辅助方法扩展
extension CronSettings {
    /// 选中的作业
    var selectedJob: CronJob? {
        guard let id = self.store.selectedJobId else { return nil }
        return self.store.jobs.first(where: { $0.id == id })
    }

    /// 状态颜色
    /// - Parameter status: 状态字符串
    /// - Returns: 对应的颜色
    func statusTint(_ status: String?) -> Color {
        switch (status ?? "").lowercased() {
        case "ok": .green
        case "error": .red
        case "skipped": .orange
        default: .secondary
        }
    }

    /// 调度摘要
    /// - Parameter schedule: Cron 调度
    /// - Returns: 调度摘要字符串
    func scheduleSummary(_ schedule: CronSchedule) -> String {
        switch schedule {
        case let .at(atMs):
            let date = Date(timeIntervalSince1970: TimeInterval(atMs) / 1000)
            return "at \(date.formatted(date: .abbreviated, time: .standard))"
        case let .every(everyMs, _):
            return "every \(self.formatDuration(ms: everyMs))"
        case let .cron(expr, tz):
            if let tz, !tz.isEmpty { return "cron \(expr) (\(tz))" }
            return "cron \(expr)"
        }
    }

    /// 格式化持续时间
    /// - Parameter ms: 毫秒数
    /// - Returns: 格式化的持续时间字符串
    func formatDuration(ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let s = Double(ms) / 1000.0
        if s < 60 { return "\(Int(round(s)))s" }
        let m = s / 60.0
        if m < 60 { return "\(Int(round(m)))m" }
        let h = m / 60.0
        if h < 48 { return "\(Int(round(h)))h" }
        let d = h / 24.0
        return "\(Int(round(d)))d"
    }

    /// 下次运行标签
    /// - Parameters:
    ///   - date: 下次运行日期
    ///   - now: 当前时间，默认为当前日期
    /// - Returns: 下次运行标签字符串
    func nextRunLabel(_ date: Date, now: Date = .init()) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 0 { return "到期" }
        if delta < 60 { return "不到 1 分钟" }
        let minutes = Int(round(delta / 60))
        if minutes < 60 { return "\(minutes) 分钟后" }
        let hours = Int(round(Double(minutes) / 60))
        if hours < 48 { return "\(hours) 小时后" }
        let days = Int(round(Double(hours) / 24))
        return "\(days) 天后"
    }
}

import Charts
import SwiftUI

/// 成本使用历史菜单视图
/// 
/// 用于显示成本使用历史的 SwiftUI 视图
struct CostUsageHistoryMenuView: View {
    /// 成本使用摘要
    let summary: GatewayCostUsageSummary
    /// 视图宽度
    let width: CGFloat

    /// 视图主体
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            self.header
            self.chart
            self.footer
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: max(1, self.width), alignment: .leading)
    }

    /// 头部视图
    private var header: some View {
        let todayKey = CostUsageMenuDateParser.format(Date())
        let todayEntry = self.summary.daily.first { $0.date == todayKey }
        let todayCost = CostUsageFormatting.formatUsd(todayEntry?.totalCost) ?? "n/a"
        let totalCost = CostUsageFormatting.formatUsd(self.summary.totals.totalCost) ?? "n/a"

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今天")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(todayCost)
                    .font(.system(size: 14, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("最近 \(self.summary.days)天")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(totalCost)
                    .font(.system(size: 14, weight: .semibold))
            }
            Spacer()
        }
    }

    /// 图表视图
    private var chart: some View {
        let entries = self.summary.daily.compactMap { entry -> (Date, Double)? in
            guard let date = CostUsageMenuDateParser.parse(entry.date) else { return nil }
            return (date, entry.totalCost)
        }

        return Chart(entries, id: \.0) { entry in
            BarMark(
                x: .value("日期", entry.0),
                y: .value("成本", entry.1))
                .foregroundStyle(Color.accentColor)
                .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: 110)
    }

    /// 底部视图
    private var footer: some View {
        if self.summary.totals.missingCostEntries == 0 {
            return AnyView(EmptyView())
        }
        return AnyView(
            Text("部分数据: \(self.summary.totals.missingCostEntries) 个条目缺少成本")
                .font(.caption2)
                .foregroundStyle(.secondary))
    }
}

/// 成本使用菜单日期解析器
/// 
/// 用于解析和格式化成本使用菜单中的日期
private enum CostUsageMenuDateParser {
    /// 日期格式化器
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// 解析日期字符串
    /// - Parameter value: 日期字符串
    /// - Returns: 解析后的日期
    static func parse(_ value: String) -> Date? {
        self.formatter.date(from: value)
    }

    /// 格式化日期
    /// - Parameter date: 日期
    /// - Returns: 格式化后的日期字符串
    static func format(_ date: Date) -> String {
        self.formatter.string(from: date)
    }
}

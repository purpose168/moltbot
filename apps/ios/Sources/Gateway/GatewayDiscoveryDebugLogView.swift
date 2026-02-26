import SwiftUI
import UIKit

/// 网关发现调试日志视图
/// 用于显示和管理网关发现过程中的调试日志
struct GatewayDiscoveryDebugLogView: View {
    /// 网关连接控制器，用于获取调试日志数据
    @Environment(GatewayConnectionController.self) private var gatewayController
    /// 存储调试日志启用状态的AppStorage
    @AppStorage("gateway.discovery.debugLogs") private var debugLogsEnabled: Bool = false

    var body: some View {
        List {
            // 当调试日志未启用时显示提示信息
            if !self.debugLogsEnabled {
                Text("启用“发现调试日志”以开始收集事件。")
                    .foregroundStyle(.secondary)
            }

            // 当日志为空时显示提示信息
            if self.gatewayController.discoveryDebugLog.isEmpty {
                Text("尚无日志条目。")
                    .foregroundStyle(.secondary)
            } else {
                // 遍历显示所有日志条目
                ForEach(self.gatewayController.discoveryDebugLog) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        // 显示格式化的时间
                        Text(Self.formatTime(entry.ts))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // 显示日志消息，支持文本选择
                        Text(entry.message)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("发现日志")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 复制按钮，点击时将所有日志复制到剪贴板
                Button("复制") {
                    UIPasteboard.general.string = self.formattedLog()
                }
                // 当日志为空时禁用复制按钮
                .disabled(self.gatewayController.discoveryDebugLog.isEmpty)
            }
        }
    }

    /// 格式化日志为字符串
    /// - Returns: 格式化后的日志字符串，包含时间戳和消息
    private func formattedLog() -> String {
        self.gatewayController.discoveryDebugLog
            .map { "\(Self.formatISO($0.ts)) \($0.message)" }
            .joined(separator: "\n")
    }

    /// 时间格式化器，用于显示简洁的时间格式
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// ISO8601日期格式化器，用于生成标准格式的时间戳
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 格式化时间为HH:mm:ss格式
    /// - Parameter date: 要格式化的日期
    /// - Returns: 格式化后的时间字符串
    private static func formatTime(_ date: Date) -> String {
        self.timeFormatter.string(from: date)
    }

    /// 格式化日期为ISO8601标准格式
    /// - Parameter date: 要格式化的日期
    /// - Returns: 格式化后的ISO8601字符串
    private static func formatISO(_ date: Date) -> String {
        self.isoFormatter.string(from: date)
    }
}

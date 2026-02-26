import MoltbotProtocol
import SwiftUI

/// 代理事件窗口
/// 显示代理执行的事件列表，包括工具调用、任务执行等
@MainActor
struct AgentEventsWindow: View {
    /// 事件存储实例
    private let store = AgentEventStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("代理事件")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("清空") { self.store.clear() }
                    .buttonStyle(.bordered)
            }
            .padding(.bottom, 4)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // 倒序显示事件，最新的事件在顶部
                    ForEach(self.store.events.reversed(), id: \.seq) { evt in
                        EventRow(event: evt)
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 520, minHeight: 360)
    }
}

/// 事件行项目
/// 显示单个代理事件的详细信息
private struct EventRow: View {
    /// 事件数据
    let event: ControlAgentEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                // 事件类型标签
                Text(self.event.stream.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(self.tint)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                // 运行 ID
                Text("运行 " + self.event.runId)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                // 时间戳
                Text(self.formattedTs)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            // 事件数据（JSON 格式）
            if let json = self.prettyJSON(event.data) {
                Text(json)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04)))
    }

    /// 根据事件类型返回对应的颜色
    private var tint: Color {
        switch self.event.stream {
        case "job": .blue       // 任务事件 - 蓝色
        case "tool": .orange    // 工具事件 - 橙色
        case "assistant": .green // 助手事件 - 绿色
        default: .gray           // 默认事件 - 灰色
        }
    }

    /// 格式化时间戳
    private var formattedTs: String {
        let date = Date(timeIntervalSince1970: event.ts / 1000)
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: date)
    }

    /// 将事件数据转换为美化的 JSON 字符串
    /// - Parameter dict: 事件数据字典
    /// - Returns: 美化后的 JSON 字符串，转换失败返回 nil
    private func prettyJSON(_ dict: [String: MoltbotProtocol.AnyCodable]) -> String? {
        // 标准化数据格式
        let normalized = dict.mapValues { $0.value }
        guard JSONSerialization.isValidJSONObject(normalized),
              let data = try? JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }
}

/// 代理事件窗口预览
struct AgentEventsWindow_Previews: PreviewProvider {
    static var previews: some View {
        // 创建示例事件
        let sample = ControlAgentEvent(
            runId: "abc",
            seq: 1,
            stream: "tool",
            ts: Date().timeIntervalSince1970 * 1000,
            data: [
                "phase": MoltbotProtocol.AnyCodable("start"),
                "name": MoltbotProtocol.AnyCodable("bash"),
            ],
            summary: nil)
        // 添加到事件存储
        AgentEventStore.shared.append(sample)
        return AgentEventsWindow()
    }
}

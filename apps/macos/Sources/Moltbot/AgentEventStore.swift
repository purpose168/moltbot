import Foundation
import Observation

/// 代理事件存储类
/// 用于管理和存储 ControlAgentEvent 类型的事件
/// 采用单例模式设计，确保全局只有一个事件存储实例
@MainActor   // 标记为在主线程执行，确保UI操作的线程安全
@Observable  // 标记为可观察对象，支持SwiftUI的响应式更新
final class AgentEventStore {
    /// 单例实例，通过静态属性提供全局访问点
    static let shared = AgentEventStore()

    /// 事件数组，使用 private(set) 确保只能通过类方法修改
    /// 这样可以保证事件存储的一致性和可控性
    private(set) var events: [ControlAgentEvent] = []
    /// 最大事件存储数量，限制为400个
    /// 防止事件过多导致内存占用过高
    private let maxEvents = 400

    /// 添加事件到存储中
    /// - Parameter event: 要添加的 ControlAgentEvent 类型事件
    func append(_ event: ControlAgentEvent) {
        // 将事件添加到数组末尾
        self.events.append(event)
        // 如果事件数量超过最大值，移除最早的事件
        // 保持事件存储数量在合理范围内
        if self.events.count > self.maxEvents {
            self.events.removeFirst(self.events.count - self.maxEvents)
        }
    }

    /// 清空所有事件
    /// 用于重置事件存储，例如在开始新会话时
    func clear() {
        self.events.removeAll()
    }
}

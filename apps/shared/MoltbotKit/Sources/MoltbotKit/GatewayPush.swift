import MoltbotProtocol

/// 来自网关 WebSocket 的服务器推送消息。
///
/// 这是传统 `NotificationCenter` 扇形分发的进程内替代品。
public enum GatewayPush: Sendable {
    /// 连接（或重新连接）时到达的完整快照。
    case snapshot(HelloOk)
    /// 服务器推送的事件帧。
    case event(EventFrame)
    /// 检测到的事件帧序列间隙（`expected...received`）。
    case seqGap(expected: Int, received: Int)
}

// MARK: - GatewayPush 枚举说明
// 
// 此枚举定义了从网关 WebSocket 接收的三种类型的服务器推送消息：
// 1. snapshot: 当客户端连接或重新连接到服务器时，服务器会发送一个完整的快照数据，包含当前状态
// 2. event: 服务器实时推送的事件帧，包含各种实时更新
// 3. seqGap: 当检测到事件帧序列存在间隙时的通知，包含期望的序列号和实际接收到的序列号
// 
// 该枚举遵循 Sendable 协议，确保在并发环境中可以安全传递。

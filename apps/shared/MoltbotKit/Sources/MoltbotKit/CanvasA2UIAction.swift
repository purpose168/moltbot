import Foundation

/// Moltbot Canvas A2UI 动作枚举，用于处理 Canvas 相关的 A2UI 操作
/// A2UI (Agent to UI) 表示从代理到用户界面的交互
public enum MoltbotCanvasA2UIAction: Sendable {
    /// 代理消息上下文结构，包含动作相关的所有信息
    public struct AgentMessageContext: Sendable {
        /// 会话信息结构
        public struct Session: Sendable {
            /// 会话密钥
            public var key: String
            /// 界面表面 ID
            public var surfaceId: String

            /// 初始化会话信息
            /// - Parameters:
            ///   - key: 会话密钥
            ///   - surfaceId: 界面表面 ID
            public init(key: String, surfaceId: String) {
                self.key = key
                self.surfaceId = surfaceId
            }
        }

        /// 组件信息结构
        public struct Component: Sendable {
            /// 组件 ID
            public var id: String
            /// 组件主机
            public var host: String
            /// 组件实例 ID
            public var instanceId: String

            /// 初始化组件信息
            /// - Parameters:
            ///   - id: 组件 ID
            ///   - host: 组件主机
            ///   - instanceId: 组件实例 ID
            public init(id: String, host: String, instanceId: String) {
                self.id = id
                self.host = host
                self.instanceId = instanceId
            }
        }

        /// 动作名称
        public var actionName: String
        /// 会话信息
        public var session: Session
        /// 组件信息
        public var component: Component
        /// 上下文 JSON 字符串（可选）
        public var contextJSON: String?

        /// 初始化代理消息上下文
        /// - Parameters:
        ///   - actionName: 动作名称
        ///   - session: 会话信息
        ///   - component: 组件信息
        ///   - contextJSON: 上下文 JSON 字符串（可选）
        public init(actionName: String, session: Session, component: Component, contextJSON: String?) {
            self.actionName = actionName
            self.session = session
            self.component = component
            self.contextJSON = contextJSON
        }
    }

    /// 从用户动作字典中提取动作名称
    /// - Parameter userAction: 用户动作字典
    /// - Returns: 提取的动作名称，如果不存在则返回 nil
    public static func extractActionName(_ userAction: [String: Any]) -> String? {
        let keys = ["name", "action"]
        for key in keys {
            if let raw = userAction[key] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// 清理标签值，确保其符合规范
    /// - Parameter value: 原始标签值
    /// - Returns: 清理后的标签值
    public static func sanitizeTagValue(_ value: String) -> String {
        // 去除首尾空白字符
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // 确保值不为空
        let nonEmpty = trimmed.isEmpty ? "-" : trimmed
        // 将空格替换为下划线
        let normalized = nonEmpty.replacingOccurrences(of: " ", with: "_")
        // 定义允许的字符集
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-. :")
        // 过滤并替换不允许的字符为下划线
        let scalars = normalized.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        return String(scalars)
    }

    /// 将对象压缩为 JSON 字符串
    /// - Parameter obj: 要压缩的对象
    /// - Returns: 压缩后的 JSON 字符串，如果失败则返回 nil
    public static func compactJSON(_ obj: Any?) -> String? {
        guard let obj else { return nil }
        guard JSONSerialization.isValidJSONObject(obj) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    /// 格式化代理消息
    /// - Parameter context: 代理消息上下文
    /// - Returns: 格式化后的消息字符串
    public static func formatAgentMessage(_ context: AgentMessageContext) -> String {
        // 处理上下文后缀
        let ctxSuffix = context.contextJSON.flatMap { $0.isEmpty ? nil : " ctx=\($0)" } ?? ""
        return [
            "CANVAS_A2UI",
            "action=\(self.sanitizeTagValue(context.actionName))",         // 动作名称
            "session=\(self.sanitizeTagValue(context.session.key))",      // 会话密钥
            "surface=\(self.sanitizeTagValue(context.session.surfaceId))", // 界面表面 ID
            "component=\(self.sanitizeTagValue(context.component.id))",    // 组件 ID
            "host=\(self.sanitizeTagValue(context.component.host))",       // 组件主机
            "instance=\(self.sanitizeTagValue(context.component.instanceId))\(ctxSuffix)", // 组件实例 ID 和上下文
            "default=update_canvas", // 默认操作为更新画布
        ].joined(separator: " ")
    }

    /// 生成 JavaScript 代码，用于分发 A2UI 动作状态事件
    /// - Parameters:
    ///   - actionId: 动作 ID
    ///   - ok: 动作是否成功
    ///   - error: 错误信息（可选）
    /// - Returns: 生成的 JavaScript 代码字符串
    public static func jsDispatchA2UIActionStatus(actionId: String, ok: Bool, error: String?) -> String {
        // 构建 payload 字典
        let payload: [String: Any] = [
            "id": actionId,
            "ok": ok,
            "error": error ?? "",
        ]
        // 生成 JSON 字符串
        let json: String = {
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let str = String(data: data, encoding: .utf8)
            {
                return str
            }
            // 备用方案，直接构建 JSON 字符串
            return "{\"id\":\"\(actionId)\",\"ok\":\(ok ? "true" : "false"),\"error\":\"\"}"
        }()
        // 生成 JavaScript 事件分发代码
        return "window.dispatchEvent(new CustomEvent('moltbot:a2ui-action-status', { detail: \(json) }));"
    }
}

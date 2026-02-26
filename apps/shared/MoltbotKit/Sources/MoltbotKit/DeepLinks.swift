import Foundation

/// 深度链接路由枚举，定义应用支持的深度链接类型
public enum DeepLinkRoute: Sendable, Equatable {
    /// 代理（Agent）类型的深度链接
    case agent(AgentDeepLink)
}

/// 代理深度链接结构体，包含代理相关的参数
public struct AgentDeepLink: Codable, Sendable, Equatable {
    /// 消息内容
    public let message: String
    /// 会话密钥，用于标识特定会话
    public let sessionKey: String?
    /// 思考内容，可能包含代理的思考过程
    public let thinking: String?
    /// 是否需要传递消息
    public let deliver: Bool
    /// 消息接收者
    public let to: String?
    /// 消息传递渠道
    public let channel: String?
    /// 超时时间（秒）
    public let timeoutSeconds: Int?
    /// 密钥，用于验证或其他用途
    public let key: String?

    /// 初始化方法
    /// - Parameters:
    ///   - message: 消息内容
    ///   - sessionKey: 会话密钥
    ///   - thinking: 思考内容
    ///   - deliver: 是否需要传递消息
    ///   - to: 消息接收者
    ///   - channel: 消息传递渠道
    ///   - timeoutSeconds: 超时时间（秒）
    ///   - key: 密钥
    public init(
        message: String,
        sessionKey: String?,
        thinking: String?,
        deliver: Bool,
        to: String?,
        channel: String?,
        timeoutSeconds: Int?,
        key: String?)
    {
        self.message = message
        self.sessionKey = sessionKey
        self.thinking = thinking
        self.deliver = deliver
        self.to = to
        self.channel = channel
        self.timeoutSeconds = timeoutSeconds
        self.key = key
    }
}

/// 深度链接解析器，用于解析URL并转换为对应的深度链接路由
public enum DeepLinkParser {
    /// 解析URL为深度链接路由
    /// - Parameter url: 要解析的URL
    /// - Returns: 解析后的深度链接路由，如果解析失败则返回nil
    public static func parse(_ url: URL) -> DeepLinkRoute? {
        // 验证URL scheme是否为"moltbot"
        guard url.scheme?.lowercased() == "moltbot" else { return nil }
        // 验证URL host是否存在且非空
        guard let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        // 尝试解析URL组件
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        // 将查询参数转换为字典
        let query = (comps.queryItems ?? []).reduce(into: [String: String]()) { dict, item in
            guard let value = item.value else { return }
            dict[item.name] = value
        }

        // 根据host类型进行不同的处理
        switch host {
        case "agent":
            // 验证消息参数是否存在且非空
            guard let message = query["message"],
                  !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            // 解析deliver参数，默认为false
            let deliver = (query["deliver"] as NSString?)?.boolValue ?? false
            // 解析timeoutSeconds参数，确保为非负数
            let timeoutSeconds = query["timeoutSeconds"].flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil }
            // 创建并返回agent类型的深度链接
            return .agent(
                .init(
                    message: message,
                    sessionKey: query["sessionKey"],
                    thinking: query["thinking"],
                    deliver: deliver,
                    to: query["to"],
                    channel: query["channel"],
                    timeoutSeconds: timeoutSeconds,
                    key: query["key"]))
        default:
            // 未知的host类型，返回nil
            return nil
        }
    }
}

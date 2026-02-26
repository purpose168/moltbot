import Foundation
import Network

/// 网关端点ID管理枚举
/// 提供用于处理网络端点(NWEndpoint)的ID生成和描述的静态方法
public enum GatewayEndpointID {
    /// 为网络端点生成稳定的ID
    /// - 参数 endpoint: 网络端点对象
    /// - 返回值: 表示端点的稳定ID字符串
    public static func stableID(_ endpoint: NWEndpoint) -> String {
        switch endpoint {
        case let .service(name, type, domain, _):
            // 在编码/解码差异中保持稳定（例如空格的\032表示）
            let normalizedName = Self.normalizeServiceNameForID(name)
            return "\(type)|\(domain)|\(normalizedName)"
        default:
            return String(describing: endpoint)
        }
    }

    /// 为网络端点生成易读的描述
    /// - 参数 endpoint: 网络端点对象
    /// - 返回值: 端点的易读描述字符串
    public static func prettyDescription(_ endpoint: NWEndpoint) -> String {
        BonjourEscapes.decode(String(describing: endpoint))
    }

    /// 为ID规范化服务名称
    /// - 参数 rawName: 原始服务名称
    /// - 返回值: 规范化后的服务名称
    private static func normalizeServiceNameForID(_ rawName: String) -> String {
        // 解码原始名称
        let decoded = BonjourEscapes.decode(rawName)
        // 规范化空白字符，将连续空白替换为单个空格
        let normalized = decoded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // 去除首尾空白和换行符
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

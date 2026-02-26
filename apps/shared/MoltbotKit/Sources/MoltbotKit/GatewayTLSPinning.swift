import CryptoKit
import Foundation
import Security

/// TLS证书固定相关参数
public struct GatewayTLSParams: Sendable {
    /// 是否强制要求TLS验证
    public let required: Bool
    /// 预期的证书指纹
    public let expectedFingerprint: String?
    /// 是否允许TOFU（Trust On First Use，首次使用时信任）
    public let allowTOFU: Bool
    /// 存储证书指纹的键
    public let storeKey: String?

    /// 初始化TLS参数
    /// - Parameters:
    ///   - required: 是否强制要求TLS验证
    ///   - expectedFingerprint: 预期的证书指纹
    ///   - allowTOFU: 是否允许TOFU（首次使用时信任）
    ///   - storeKey: 存储证书指纹的键
    public init(required: Bool, expectedFingerprint: String?, allowTOFU: Bool, storeKey: String?) {
        self.required = required
        self.expectedFingerprint = expectedFingerprint
        self.allowTOFU = allowTOFU
        self.storeKey = storeKey
    }
}

/// TLS证书指纹存储
public enum GatewayTLSStore {
    /// 应用组名称
    private static let suiteName = "bot.molt.shared"
    /// 旧应用组名称（用于迁移）
    private static let legacySuiteName = "com.clawdbot.shared"
    /// 存储键前缀
    private static let keyPrefix = "gateway.tls."

    /// 获取UserDefaults实例
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// 获取旧的UserDefaults实例（用于迁移）
    private static var legacyDefaults: UserDefaults? {
        UserDefaults(suiteName: legacySuiteName)
    }

    /// 加载证书指纹
    /// - Parameter stableID: 稳定标识符
    /// - Returns: 证书指纹，如果不存在则返回nil
    public static func loadFingerprint(stableID: String) -> String? {
        let key = self.keyPrefix + stableID
        let raw = self.defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw?.isEmpty == false { return raw }

        // 尝试从旧存储中加载
        let legacy = self.legacyDefaults?.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if legacy?.isEmpty == false {
            // 迁移到新存储
            self.defaults.set(legacy, forKey: key)
            return legacy
        }

        return nil
    }

    /// 保存证书指纹
    /// - Parameters:
    ///   - value: 证书指纹
    ///   - stableID: 稳定标识符
    public static func saveFingerprint(_ value: String, stableID: String) {
        let key = self.keyPrefix + stableID
        self.defaults.set(value, forKey: key)
    }
}

/// 实现TLS证书固定的WebSocket会话
public final class GatewayTLSPinningSession: NSObject, WebSocketSessioning, URLSessionDelegate, @unchecked Sendable {
    /// TLS参数
    private let params: GatewayTLSParams
    /// URLSession实例
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    /// 初始化会话
    /// - Parameter params: TLS参数
    public init(params: GatewayTLSParams) {
        self.params = params
        super.init()
    }

    /// 创建WebSocket任务
    /// - Parameter url: WebSocket URL
    /// - Returns: WebSocket任务包装器
    public func makeWebSocketTask(url: URL) -> WebSocketTaskBox {
        let task = self.session.webSocketTask(with: url)
        task.maximumMessageSize = 16 * 1024 * 1024 // 16MB
        return WebSocketTaskBox(task: task)
    }

    /// 处理URL会话的认证挑战
    /// - Parameters:
    ///   - session: URL会话
    ///   - challenge: 认证挑战
    ///   - completionHandler: 完成处理程序
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // 确保是服务器信任认证方法
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // 处理预期的证书指纹
        let expected = params.expectedFingerprint.map(normalizeFingerprint)
        if let fingerprint = certificateFingerprint(trust) {
            if let expected {
                // 验证指纹是否匹配
                if fingerprint == expected {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
                    completionHandler(.cancelAuthenticationChallenge, nil)
                }
                return
            }
            // 处理TOFU模式
            if params.allowTOFU {
                if let storeKey = params.storeKey {
                    GatewayTLSStore.saveFingerprint(fingerprint, stableID: storeKey)
                }
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
        }

        // 执行默认的信任评估
        let ok = SecTrustEvaluateWithError(trust, nil)
        if ok || !params.required {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

/// 获取证书指纹
/// - Parameter trust: 安全信任对象
/// - Returns: 证书指纹，如果获取失败则返回nil
private func certificateFingerprint(_ trust: SecTrust) -> String? {
    guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
          let cert = chain.first
    else {
        return nil
    }
    return sha256Hex(SecCertificateCopyData(cert) as Data)
}

/// 计算数据的SHA256哈希值（十六进制格式）
/// - Parameter data: 要哈希的数据
/// - Returns: 十六进制格式的SHA256哈希值
private func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// 标准化证书指纹
/// - Parameter raw: 原始指纹字符串
/// - Returns: 标准化后的指纹字符串
private func normalizeFingerprint(_ raw: String) -> String {
    // 移除SHA-256前缀
    let stripped = raw.replacingOccurrences(
        of: #"(?i)^sha-?256\s*:?\s*"#,
        with: "",
        options: .regularExpression)
    // 转换为小写并过滤非十六进制字符
    return stripped.lowercased().filter(\.isHexDigit)
}

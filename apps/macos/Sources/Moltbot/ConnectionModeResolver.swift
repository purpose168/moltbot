import Foundation

/// 有效连接模式来源
/// 
/// 表示连接模式的来源
enum EffectiveConnectionModeSource: Sendable, Equatable {
    /// 配置模式
    case configMode
    /// 配置远程URL
    case configRemoteURL
    /// 用户默认设置
    case userDefaults
    /// 引导流程
    case onboarding
}

/// 有效连接模式
/// 
/// 包含连接模式和其来源
struct EffectiveConnectionMode: Sendable, Equatable {
    /// 连接模式
    let mode: AppState.ConnectionMode
    /// 来源
    let source: EffectiveConnectionModeSource
}

/// 连接模式解析器
/// 
/// 用于解析应用程序的连接模式
enum ConnectionModeResolver {
    /// 解析连接模式
    /// - Parameters:
    ///   - root: 配置根字典
    ///   - defaults: 用户默认设置，默认为标准用户默认设置
    /// - Returns: 有效连接模式
    static func resolve(
        root: [String: Any],
        defaults: UserDefaults = .standard) -> EffectiveConnectionMode
    {
        let gateway = root["gateway"] as? [String: Any]
        let configModeRaw = (gateway?["mode"] as? String) ?? ""
        let configMode = configModeRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch configMode {
        case "local":
            return EffectiveConnectionMode(mode: .local, source: .configMode)
        case "remote":
            return EffectiveConnectionMode(mode: .remote, source: .configMode)
        default:
            break
        }

        let remoteURLRaw = ((gateway?["remote"] as? [String: Any])?["url"] as? String) ?? ""
        let remoteURL = remoteURLRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !remoteURL.isEmpty {
            return EffectiveConnectionMode(mode: .remote, source: .configRemoteURL)
        }

        if let storedModeRaw = defaults.string(forKey: connectionModeKey) {
            let storedMode = AppState.ConnectionMode(rawValue: storedModeRaw) ?? .local
            return EffectiveConnectionMode(mode: storedMode, source: .userDefaults)
        }

        let seen = defaults.bool(forKey: "moltbot.onboardingSeen")
        return EffectiveConnectionMode(mode: seen ? .local : .unconfigured, source: .onboarding)
    }
}

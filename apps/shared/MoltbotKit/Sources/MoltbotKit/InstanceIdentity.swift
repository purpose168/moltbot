import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// 实例身份管理枚举，用于获取和存储应用实例的唯一标识及设备相关信息
public enum InstanceIdentity {
    /// 共享存储套件名称
    private static let suiteName = "bot.molt.shared"
    /// 旧版共享存储套件名称（用于兼容）
    private static let legacySuiteName = "com.clawdbot.shared"
    /// 实例ID在存储中的键名
    private static let instanceIdKey = "instanceId"

    /// 获取共享存储实例
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// 获取旧版共享存储实例（用于兼容）
    private static var legacyDefaults: UserDefaults? {
        UserDefaults(suiteName: legacySuiteName)
    }

#if canImport(UIKit)
    /// 在主线程上执行闭包的工具方法
    /// - Parameter body: 需要在主线程执行的闭包
    /// - Returns: 闭包执行的结果
    private static func readMainActor<T: Sendable>(_ body: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { body() }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { body() }
        }
    }
#endif

    /// 应用实例的唯一标识符
    /// - 首先尝试从共享存储中读取已存在的ID
    /// - 如果不存在，尝试从旧版存储中读取（用于兼容）
    /// - 如果仍然不存在，生成新的UUID并存储
    public static let instanceId: String = {
        let defaults = Self.defaults
        // 尝试从共享存储中读取已存在的实例ID
        if let existing = defaults.string(forKey: instanceIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            return existing
        }

        // 尝试从旧版存储中读取实例ID（用于兼容）
        if let legacy = Self.legacyDefaults?.string(forKey: instanceIdKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        {
            // 将旧版ID迁移到新的存储中
            defaults.set(legacy, forKey: instanceIdKey)
            return legacy
        }

        // 生成新的UUID作为实例ID
        let id = UUID().uuidString.lowercased()
        // 存储新生成的实例ID
        defaults.set(id, forKey: instanceIdKey)
        return id
    }()

    /// 设备的显示名称
    /// - 在iOS/iPadOS上，返回设备名称
    /// - 在macOS上，返回主机名称
    /// - 如果名称为空，返回默认值"moltbot"
    public static let displayName: String = {
#if canImport(UIKit)
        let name = Self.readMainActor {
            UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return name.isEmpty ? "moltbot" : name
#else
        if let name = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty
        {
            return name
        }
        return "moltbot"
#endif
    }()

    /// 设备型号标识符
    /// - 在iOS/iPadOS上，通过utsname获取
    /// - 在macOS上，通过sysctl获取
    /// - 如果获取失败或结果为空，返回nil
    public static let modelIdentifier: String? = {
#if canImport(UIKit)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { ptr in
            String(bytes: ptr.prefix { $0 != 0 }, encoding: .utf8)
        }
        let trimmed = machine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
#else
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 1 else { return nil }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }

        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard let raw = String(bytes: bytes, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
#endif
    }()

    /// 设备家族
    /// - 在iOS/iPadOS上，根据设备类型返回"iPad"、"iPhone"或"iOS"
    /// - 在macOS上，返回"Mac"
    public static let deviceFamily: String = {
#if canImport(UIKit)
        return Self.readMainActor {
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return "iPad"
            case .phone: return "iPhone"
            default: return "iOS"
            }
        }
#else
        return "Mac"
#endif
    }()

    /// 平台字符串，包含操作系统名称和版本
    /// - 在iOS/iPadOS上，返回"iPadOS X.X.X"或"iOS X.X.X"
    /// - 在macOS上，返回"macOS X.X.X"
    public static let platformString: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
#if canImport(UIKit)
        let name = Self.readMainActor {
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return "iPadOS"
            case .phone: return "iOS"
            default: return "iOS"
            }
        }
        return "\(name) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
#else
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
#endif
    }()
}

import Foundation

/// 设备认证条目，包含令牌信息
/// - 实现了 Codable 和 Sendable 协议，支持序列化和并发安全
public struct DeviceAuthEntry: Codable, Sendable {
    /// 认证令牌
    public let token: String
    /// 角色名称
    public let role: String
    /// 权限范围列表
    public let scopes: [String]
    /// 更新时间戳（毫秒）
    public let updatedAtMs: Int

    /// 初始化方法
    /// - Parameters:
    ///   - token: 认证令牌
    ///   - role: 角色名称
    ///   - scopes: 权限范围列表
    ///   - updatedAtMs: 更新时间戳（毫秒）
    public init(token: String, role: String, scopes: [String], updatedAtMs: Int) {
        self.token = token
        self.role = role
        self.scopes = scopes
        self.updatedAtMs = updatedAtMs
    }
}

/// 设备认证存储文件结构
/// - 用于序列化和反序列化认证信息到 JSON 文件
private struct DeviceAuthStoreFile: Codable {
    /// 版本号
    var version: Int
    /// 设备 ID
    var deviceId: String
    /// 令牌字典，键为角色名称，值为认证条目
    var tokens: [String: DeviceAuthEntry]
}

/// 设备认证存储工具
/// - 提供令牌的加载、存储和清除功能
public enum DeviceAuthStore {
    /// 存储文件名
    private static let fileName = "device-auth.json"

    /// 加载指定设备和角色的令牌
    /// - Parameters:
    ///   - deviceId: 设备 ID
    ///   - role: 角色名称
    /// - Returns: 设备认证条目，如果不存在则返回 nil
    public static func loadToken(deviceId: String, role: String) -> DeviceAuthEntry? {
        // 读取存储文件并验证设备 ID
        guard let store = readStore(), store.deviceId == deviceId else { return nil }
        // 标准化角色名称
        let role = normalizeRole(role)
        // 返回对应角色的令牌
        return store.tokens[role]
    }

    /// 存储设备认证令牌
    /// - Parameters:
    ///   - deviceId: 设备 ID
    ///   - role: 角色名称
    ///   - token: 认证令牌
    ///   - scopes: 权限范围列表，默认为空
    /// - Returns: 存储的设备认证条目
    public static func storeToken(
        deviceId: String,
        role: String,
        token: String,
        scopes: [String] = []
    ) -> DeviceAuthEntry {
        // 标准化角色名称
        let normalizedRole = normalizeRole(role)
        // 读取现有存储
        var next = readStore()
        
        // 如果存储不存在或设备 ID 不匹配，创建新的存储
        if next?.deviceId != deviceId {
            next = DeviceAuthStoreFile(version: 1, deviceId: deviceId, tokens: [:])
        }
        
        // 创建认证条目
        let entry = DeviceAuthEntry(
            token: token,
            role: normalizedRole,
            scopes: normalizeScopes(scopes),
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)  // 当前时间戳（毫秒）
        )
        
        // 确保存储对象存在
        if next == nil {
            next = DeviceAuthStoreFile(version: 1, deviceId: deviceId, tokens: [:])
        }
        
        // 存储令牌并写入文件
        next?.tokens[normalizedRole] = entry
        if let store = next {
            writeStore(store)
        }
        
        return entry
    }

    /// 清除指定设备和角色的令牌
    /// - Parameters:
    ///   - deviceId: 设备 ID
    ///   - role: 角色名称
    public static func clearToken(deviceId: String, role: String) {
        // 读取存储并验证设备 ID
        guard var store = readStore(), store.deviceId == deviceId else { return }
        // 标准化角色名称
        let normalizedRole = normalizeRole(role)
        // 确保令牌存在
        guard store.tokens[normalizedRole] != nil else { return }
        // 移除令牌并写入文件
        store.tokens.removeValue(forKey: normalizedRole)
        writeStore(store)
    }

    /// 标准化角色名称
    /// - Parameter role: 原始角色名称
    /// - Returns: 去除空白字符后的角色名称
    private static func normalizeRole(_ role: String) -> String {
        role.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 标准化权限范围列表
    /// - Parameter scopes: 原始权限范围列表
    /// - Returns: 去重、排序后的权限范围列表
    private static func normalizeScopes(_ scopes: [String]) -> [String] {
        let trimmed = scopes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }  // 去除空白字符
            .filter { !$0.isEmpty }  // 过滤空字符串
        return Array(Set(trimmed)).sorted()  // 去重并排序
    }

    /// 获取存储文件的 URL 路径
    /// - Returns: 存储文件的 URL
    private static func fileURL() -> URL {
        DeviceIdentityPaths.stateDirURL()
            .appendingPathComponent("identity", isDirectory: true)  // 在状态目录下创建 identity 子目录
            .appendingPathComponent(fileName, isDirectory: false)  // 添加文件名
    }

    /// 读取存储文件
    /// - Returns: 设备认证存储文件对象，如果读取失败则返回 nil
    private static func readStore() -> DeviceAuthStoreFile? {
        let url = fileURL()
        // 尝试读取文件数据
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 尝试解码 JSON 数据
        guard let decoded = try? JSONDecoder().decode(DeviceAuthStoreFile.self, from: data) else {
            return nil
        }
        // 验证版本号
        guard decoded.version == 1 else { return nil }
        return decoded
    }

    /// 写入存储文件
    /// - Parameter store: 设备认证存储文件对象
    private static func writeStore(_ store: DeviceAuthStoreFile) {
        let url = fileURL()
        do {
            // 确保目录存在
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            // 编码为 JSON 数据
            let data = try JSONEncoder().encode(store)
            // 原子写入文件，确保操作的原子性
            try data.write(to: url, options: [.atomic])
            // 设置文件权限为 600，确保只有所有者可读写
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // 仅做最大努力尝试，失败不抛出异常
        }
    }
}

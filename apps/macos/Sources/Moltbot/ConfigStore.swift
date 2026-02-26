import MoltbotProtocol
import Foundation

/// 配置存储
///
/// 用于加载和保存应用程序配置的静态枚举
enum ConfigStore {
    /// 配置存储覆盖
    ///
    /// 用于测试和特殊场景下的配置存储覆盖
    struct Overrides: Sendable {
        /// 是否为远程模式的覆盖
        var isRemoteMode: (@Sendable () async -> Bool)?
        /// 加载本地配置的覆盖
        var loadLocal: (@MainActor @Sendable () -> [String: Any])?
        /// 保存本地配置的覆盖
        var saveLocal: (@MainActor @Sendable ([String: Any]) -> Void)?
        /// 加载远程配置的覆盖
        var loadRemote: (@MainActor @Sendable () async -> [String: Any])?
        /// 保存远程配置的覆盖
        var saveRemote: (@MainActor @Sendable ([String: Any]) async throws -> Void)?
    }

    /// 覆盖存储
    ///
    /// 用于存储配置存储覆盖的actor
    private actor OverrideStore {
        /// 覆盖实例
        var overrides = Overrides()

        /// 设置覆盖
        /// - Parameter overrides: 覆盖实例
        func setOverride(_ overrides: Overrides) {
            self.overrides = overrides
        }
    }

    /// 覆盖存储实例
    private static let overrideStore = OverrideStore()
    /// 上次配置哈希
    @MainActor private static var lastHash: String?

    /// 检查是否为远程模式
    /// - Returns: 是否为远程模式
    private static func isRemoteMode() async -> Bool {
        let overrides = await self.overrideStore.overrides
        if let override = overrides.isRemoteMode {
            return await override()
        }
        return await MainActor.run { AppStateStore.shared.connectionMode == .remote }
    }

    /// 加载配置
    /// - Returns: 配置字典
    @MainActor
    static func load() async -> [String: Any] {
        let overrides = await self.overrideStore.overrides
        if await self.isRemoteMode() {
            if let override = overrides.loadRemote {
                return await override()
            }
            return await self.loadFromGateway() ?? [:]
        }
        if let override = overrides.loadLocal {
            return override()
        }
        if let gateway = await self.loadFromGateway() {
            return gateway
        }
        return MoltbotConfigFile.loadDict()
    }

    /// 保存配置
    /// - Parameter root: 配置字典
    /// - Throws: 保存失败时抛出错误
    @MainActor
    static func save(_ root: sending [String: Any]) async throws {
        let overrides = await self.overrideStore.overrides
        if await self.isRemoteMode() {
            if let override = overrides.saveRemote {
                try await override(root)
            } else {
                try await self.saveToGateway(root)
            }
        } else {
            if let override = overrides.saveLocal {
                override(root)
            } else {
                do {
                    try await self.saveToGateway(root)
                } catch {
                    MoltbotConfigFile.saveDict(root)
                }
            }
        }
    }

    /// 从网关加载配置
    /// - Returns: 配置字典，如果加载失败则返回nil
    @MainActor
    private static func loadFromGateway() async -> [String: Any]? {
        do {
            let snap: ConfigSnapshot = try await GatewayConnection.shared.requestDecoded(
                method: .configGet,
                params: nil,
                timeoutMs: 8000)
            self.lastHash = snap.hash
            return snap.config?.mapValues { $0.foundationValue } ?? [:]
        } catch {
            return nil
        }
    }

    /// 保存配置到网关
    /// - Parameter root: 配置字典
    /// - Throws: 保存失败时抛出错误
    @MainActor
    private static func saveToGateway(_ root: [String: Any]) async throws {
        if self.lastHash == nil {
            _ = await self.loadFromGateway()
        }
        // 将配置字典序列化为JSON数据，使用美化和排序选项
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        guard let raw = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ConfigStore", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "配置编码失败。",
            ])
        }
        // 构建请求参数，包含原始配置数据
        var params: [String: AnyCodable] = ["raw": AnyCodable(raw)]
        // 如果存在上次配置哈希，则添加到参数中以实现乐观锁机制
        if let baseHash = self.lastHash {
            params["baseHash"] = AnyCodable(baseHash)
        }
        // 向网关发送配置设置请求
        _ = try await GatewayConnection.shared.requestRaw(
            method: .configSet,
            params: params,
            timeoutMs: 10000)
        // 重新加载配置以同步状态
        _ = await self.loadFromGateway()
    }

    #if DEBUG
    /// 测试设置覆盖
    /// - Parameter overrides: 覆盖实例
    static func _testSetOverrides(_ overrides: Overrides) async {
        await self.overrideStore.setOverride(overrides)
    }

    /// 测试清除覆盖
    static func _testClearOverrides() async {
        await self.overrideStore.setOverride(.init())
    }
    #endif
}

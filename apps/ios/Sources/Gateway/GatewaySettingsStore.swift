import Foundation

/// 网关设置存储类
/// 负责管理与网关相关的配置和持久化存储
/// 包括实例ID、网关偏好设置、令牌和密码等信息的存储和加载
enum GatewaySettingsStore {
    // MARK: - 服务标识符
    /// 当前网关服务标识符
    private static let gatewayService = "bot.molt.gateway"
    /// 旧版网关服务标识符
    private static let legacyGatewayService = "com.clawdbot.gateway"
    /// 旧版桥接服务标识符
    private static let legacyBridgeService = "com.clawdbot.bridge"
    /// 当前节点服务标识符
    private static let nodeService = "bot.molt.node"
    /// 旧版节点服务标识符
    private static let legacyNodeService = "com.clawdbot.node"

    // MARK: - 默认键值
    /// 实例ID默认键
    private static let instanceIdDefaultsKey = "node.instanceId"
    /// 首选网关稳定ID默认键
    private static let preferredGatewayStableIDDefaultsKey = "gateway.preferredStableID"
    /// 最后发现的网关稳定ID默认键
    private static let lastDiscoveredGatewayStableIDDefaultsKey = "gateway.lastDiscoveredStableID"
    /// 手动模式启用默认键
    private static let manualEnabledDefaultsKey = "gateway.manual.enabled"
    /// 手动模式主机默认键
    private static let manualHostDefaultsKey = "gateway.manual.host"
    /// 手动模式端口默认键
    private static let manualPortDefaultsKey = "gateway.manual.port"
    /// 手动模式TLS默认键
    private static let manualTlsDefaultsKey = "gateway.manual.tls"
    /// 发现调试日志默认键
    private static let discoveryDebugLogsDefaultsKey = "gateway.discovery.debugLogs"

    // MARK: - 旧版默认键值
    /// 旧版首选桥接稳定ID默认键
    private static let legacyPreferredBridgeStableIDDefaultsKey = "bridge.preferredStableID"
    /// 旧版最后发现的桥接稳定ID默认键
    private static let legacyLastDiscoveredBridgeStableIDDefaultsKey = "bridge.lastDiscoveredStableID"
    /// 旧版手动模式启用默认键
    private static let legacyManualEnabledDefaultsKey = "bridge.manual.enabled"
    /// 旧版手动模式主机默认键
    private static let legacyManualHostDefaultsKey = "bridge.manual.host"
    /// 旧版手动模式端口默认键
    private static let legacyManualPortDefaultsKey = "bridge.manual.port"
    /// 旧版发现调试日志默认键
    private static let legacyDiscoveryDebugLogsDefaultsKey = "bridge.discovery.debugLogs"

    // MARK: - 钥匙串账户
    /// 实例ID账户
    private static let instanceIdAccount = "instanceId"
    /// 首选网关稳定ID账户
    private static let preferredGatewayStableIDAccount = "preferredStableID"
    /// 最后发现的网关稳定ID账户
    private static let lastDiscoveredGatewayStableIDAccount = "lastDiscoveredStableID"

    // MARK: - 公共方法
    /// 引导持久化存储
    /// 确保所有必要的设置都已正确初始化和迁移
    static func bootstrapPersistence() {
        self.ensureStableInstanceID()        // 确保稳定实例ID
        self.ensurePreferredGatewayStableID() // 确保首选网关稳定ID
        self.ensureLastDiscoveredGatewayStableID() // 确保最后发现的网关稳定ID
        self.migrateLegacyDefaults()          // 迁移旧版默认值
    }

    /// 加载稳定实例ID
    /// - Returns: 稳定实例ID，如果不存在则返回nil
    static func loadStableInstanceID() -> String? {
        // 尝试从当前服务加载
        if let value = KeychainStore.loadString(service: self.nodeService, account: self.instanceIdAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }

        // 尝试从旧版服务加载并迁移
        if let legacy = KeychainStore.loadString(service: self.legacyNodeService, account: self.instanceIdAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        {
            _ = KeychainStore.saveString(legacy, service: self.nodeService, account: self.instanceIdAccount)
            return legacy
        }

        return nil
    }

    /// 保存稳定实例ID
    /// - Parameter instanceId: 要保存的实例ID
    static func saveStableInstanceID(_ instanceId: String) {
        _ = KeychainStore.saveString(instanceId, service: self.nodeService, account: self.instanceIdAccount)
    }

    /// 加载首选网关稳定ID
    /// - Returns: 首选网关稳定ID，如果不存在则返回nil
    static func loadPreferredGatewayStableID() -> String? {
        // 尝试从当前服务加载
        if let value = KeychainStore.loadString(
            service: self.gatewayService,
            account: self.preferredGatewayStableIDAccount
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }

        // 尝试从旧版服务加载并迁移
        if let legacy = KeychainStore.loadString(
            service: self.legacyGatewayService,
            account: self.preferredGatewayStableIDAccount
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        {
            _ = KeychainStore.saveString(
                legacy,
                service: self.gatewayService,
                account: self.preferredGatewayStableIDAccount)
            return legacy
        }

        return nil
    }

    /// 保存首选网关稳定ID
    /// - Parameter stableID: 要保存的稳定ID
    static func savePreferredGatewayStableID(_ stableID: String) {
        _ = KeychainStore.saveString(
            stableID,
            service: self.gatewayService,
            account: self.preferredGatewayStableIDAccount)
    }

    /// 加载最后发现的网关稳定ID
    /// - Returns: 最后发现的网关稳定ID，如果不存在则返回nil
    static func loadLastDiscoveredGatewayStableID() -> String? {
        // 尝试从当前服务加载
        if let value = KeychainStore.loadString(
            service: self.gatewayService,
            account: self.lastDiscoveredGatewayStableIDAccount
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }

        // 尝试从旧版服务加载并迁移
        if let legacy = KeychainStore.loadString(
            service: self.legacyGatewayService,
            account: self.lastDiscoveredGatewayStableIDAccount
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
            !legacy.isEmpty
        {
            _ = KeychainStore.saveString(
                legacy,
                service: self.gatewayService,
                account: self.lastDiscoveredGatewayStableIDAccount)
            return legacy
        }

        return nil
    }

    /// 保存最后发现的网关稳定ID
    /// - Parameter stableID: 要保存的稳定ID
    static func saveLastDiscoveredGatewayStableID(_ stableID: String) {
        _ = KeychainStore.saveString(
            stableID,
            service: self.gatewayService,
            account: self.lastDiscoveredGatewayStableIDAccount)
    }

    /// 加载网关令牌
    /// - Parameter instanceId: 实例ID
    /// - Returns: 网关令牌，如果不存在则返回nil
    static func loadGatewayToken(instanceId: String) -> String? {
        let account = self.gatewayTokenAccount(instanceId: instanceId)
        let token = KeychainStore.loadString(service: self.gatewayService, account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if token?.isEmpty == false { return token }

        // 尝试从旧版桥接令牌迁移
        let legacyAccount = self.legacyBridgeTokenAccount(instanceId: instanceId)
        let legacy = KeychainStore.loadString(service: self.legacyBridgeService, account: legacyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let legacy, !legacy.isEmpty {
            _ = KeychainStore.saveString(legacy, service: self.gatewayService, account: account)
            return legacy
        }
        return nil
    }

    /// 保存网关令牌
    /// - Parameters:
    ///   - token: 要保存的令牌
    ///   - instanceId: 实例ID
    static func saveGatewayToken(_ token: String, instanceId: String) {
        _ = KeychainStore.saveString(
            token,
            service: self.gatewayService,
            account: self.gatewayTokenAccount(instanceId: instanceId))
    }

    /// 加载网关密码
    /// - Parameter instanceId: 实例ID
    /// - Returns: 网关密码，如果不存在则返回nil
    static func loadGatewayPassword(instanceId: String) -> String? {
        KeychainStore.loadString(
            service: self.gatewayService,
            account: self.gatewayPasswordAccount(instanceId: instanceId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 保存网关密码
    /// - Parameters:
    ///   - password: 要保存的密码
    ///   - instanceId: 实例ID
    static func saveGatewayPassword(_ password: String, instanceId: String) {
        _ = KeychainStore.saveString(
            password,
            service: self.gatewayService,
            account: self.gatewayPasswordAccount(instanceId: instanceId))
    }

    // MARK: - 私有辅助方法
    /// 生成网关令牌账户名
    /// - Parameter instanceId: 实例ID
    /// - Returns: 网关令牌账户名
    private static func gatewayTokenAccount(instanceId: String) -> String {
        "gateway-token.\(instanceId)"
    }

    /// 生成旧版桥接令牌账户名
    /// - Parameter instanceId: 实例ID
    /// - Returns: 旧版桥接令牌账户名
    private static func legacyBridgeTokenAccount(instanceId: String) -> String {
        "bridge-token.\(instanceId)"
    }

    /// 生成网关密码账户名
    /// - Parameter instanceId: 实例ID
    /// - Returns: 网关密码账户名
    private static func gatewayPasswordAccount(instanceId: String) -> String {
        "gateway-password.\(instanceId)"
    }

    /// 确保稳定实例ID存在
    private static func ensureStableInstanceID() {
        let defaults = UserDefaults.standard

        // 尝试从默认值加载并保存到钥匙串
        if let existing = defaults.string(forKey: self.instanceIdDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            if self.loadStableInstanceID() == nil {
                self.saveStableInstanceID(existing)
            }
            return
        }

        // 尝试从钥匙串加载并保存到默认值
        if let stored = self.loadStableInstanceID(), !stored.isEmpty {
            defaults.set(stored, forKey: self.instanceIdDefaultsKey)
            return
        }

        // 生成新的实例ID并保存
        let fresh = UUID().uuidString
        self.saveStableInstanceID(fresh)
        defaults.set(fresh, forKey: self.instanceIdDefaultsKey)
    }

    /// 确保首选网关稳定ID存在
    private static func ensurePreferredGatewayStableID() {
        let defaults = UserDefaults.standard

        // 尝试从默认值加载并保存到钥匙串
        if let existing = defaults.string(forKey: self.preferredGatewayStableIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            if self.loadPreferredGatewayStableID() == nil {
                self.savePreferredGatewayStableID(existing)
            }
            return
        }

        // 尝试从钥匙串加载并保存到默认值
        if let stored = self.loadPreferredGatewayStableID(), !stored.isEmpty {
            defaults.set(stored, forKey: self.preferredGatewayStableIDDefaultsKey)
        }
    }

    /// 确保最后发现的网关稳定ID存在
    private static func ensureLastDiscoveredGatewayStableID() {
        let defaults = UserDefaults.standard

        // 尝试从默认值加载并保存到钥匙串
        if let existing = defaults.string(forKey: self.lastDiscoveredGatewayStableIDDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !existing.isEmpty
        {
            if self.loadLastDiscoveredGatewayStableID() == nil {
                self.saveLastDiscoveredGatewayStableID(existing)
            }
            return
        }

        // 尝试从钥匙串加载并保存到默认值
        if let stored = self.loadLastDiscoveredGatewayStableID(), !stored.isEmpty {
            defaults.set(stored, forKey: self.lastDiscoveredGatewayStableIDDefaultsKey)
        }
    }

    /// 迁移旧版默认值
    private static func migrateLegacyDefaults() {
        let defaults = UserDefaults.standard

        // 迁移首选网关稳定ID
        if defaults.string(forKey: self.preferredGatewayStableIDDefaultsKey)?.isEmpty != false,
           let legacy = defaults.string(forKey: self.legacyPreferredBridgeStableIDDefaultsKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            defaults.set(legacy, forKey: self.preferredGatewayStableIDDefaultsKey)
            self.savePreferredGatewayStableID(legacy)
        }

        // 迁移最后发现的网关稳定ID
        if defaults.string(forKey: self.lastDiscoveredGatewayStableIDDefaultsKey)?.isEmpty != false,
           let legacy = defaults.string(forKey: self.legacyLastDiscoveredBridgeStableIDDefaultsKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            defaults.set(legacy, forKey: self.lastDiscoveredGatewayStableIDDefaultsKey)
            self.saveLastDiscoveredGatewayStableID(legacy)
        }

        // 迁移手动模式启用状态
        if defaults.object(forKey: self.manualEnabledDefaultsKey) == nil,
           defaults.object(forKey: self.legacyManualEnabledDefaultsKey) != nil
        {
            defaults.set(
                defaults.bool(forKey: self.legacyManualEnabledDefaultsKey),
                forKey: self.manualEnabledDefaultsKey)
        }

        // 迁移手动模式主机
        if defaults.string(forKey: self.manualHostDefaultsKey)?.isEmpty != false,
           let legacy = defaults.string(forKey: self.legacyManualHostDefaultsKey),
           !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            defaults.set(legacy, forKey: self.manualHostDefaultsKey)
        }

        // 迁移手动模式端口
        if defaults.integer(forKey: self.manualPortDefaultsKey) == 0,
           defaults.integer(forKey: self.legacyManualPortDefaultsKey) > 0
        {
            defaults.set(
                defaults.integer(forKey: self.legacyManualPortDefaultsKey),
                forKey: self.manualPortDefaultsKey)
        }

        // 迁移发现调试日志设置
        if defaults.object(forKey: self.discoveryDebugLogsDefaultsKey) == nil,
           defaults.object(forKey: self.legacyDiscoveryDebugLogsDefaultsKey) != nil
        {
            defaults.set(
                defaults.bool(forKey: self.legacyDiscoveryDebugLogsDefaultsKey),
                forKey: self.discoveryDebugLogsDefaultsKey)
        }
    }
}

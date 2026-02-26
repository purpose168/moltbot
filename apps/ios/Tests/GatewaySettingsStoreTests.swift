import Foundation
import Testing
@testable import Moltbot

/// 表示 Keychain 中的一个条目
private struct KeychainEntry: Hashable {
    let service: String
    let account: String
}

/// Gateway 服务标识符
private let gatewayService = "bot.molt.gateway"
/// Node 服务标识符
private let nodeService = "bot.molt.node"
/// 实例 ID 的 Keychain 条目
private let instanceIdEntry = KeychainEntry(service: nodeService, account: "instanceId")
/// 首选 Gateway 的 Keychain 条目
private let preferredGatewayEntry = KeychainEntry(service: gatewayService, account: "preferredStableID")
/// 最后发现的 Gateway 的 Keychain 条目
private let lastGatewayEntry = KeychainEntry(service: gatewayService, account: "lastDiscoveredStableID")

/// 对指定键的 UserDefaults 值进行快照
/// - Parameter keys: 需要快照的键数组
/// - Returns: 包含键值对的字典
private func snapshotDefaults(_ keys: [String]) -> [String: Any?] {
    let defaults = UserDefaults.standard
    var snapshot: [String: Any?] = [:]
    for key in keys {
        snapshot[key] = defaults.object(forKey: key)
    }
    return snapshot
}

/// 应用指定的 UserDefaults 值
/// - Parameter values: 要应用的键值对字典
private func applyDefaults(_ values: [String: Any?]) {
    let defaults = UserDefaults.standard
    for (key, value) in values {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// 恢复 UserDefaults 的快照值
/// - Parameter snapshot: 之前获取的快照
private func restoreDefaults(_ snapshot: [String: Any?]) {
    applyDefaults(snapshot)
}

/// 对指定的 Keychain 条目进行快照
/// - Parameter entries: 需要快照的 Keychain 条目数组
/// - Returns: 包含条目和对应值的字典
private func snapshotKeychain(_ entries: [KeychainEntry]) -> [KeychainEntry: String?] {
    var snapshot: [KeychainEntry: String?] = [:]
    for entry in entries {
        snapshot[entry] = KeychainStore.loadString(service: entry.service, account: entry.account)
    }
    return snapshot
}

/// 应用指定的 Keychain 值
/// - Parameter values: 要应用的条目和对应值的字典
private func applyKeychain(_ values: [KeychainEntry: String?]) {
    for (entry, value) in values {
        if let value {
            _ = KeychainStore.saveString(value, service: entry.service, account: entry.account)
        } else {
            _ = KeychainStore.delete(service: entry.service, account: entry.account)
        }
    }
}

/// 恢复 Keychain 的快照值
/// - Parameter snapshot: 之前获取的快照
private func restoreKeychain(_ snapshot: [KeychainEntry: String?]) {
    applyKeychain(snapshot)
}

/// Gateway 设置存储的测试套件
@Suite(.serialized) struct GatewaySettingsStoreTests {
    /// 测试当 Keychain 中缺少数据时，从 UserDefaults 复制数据到 Keychain
    @Test func bootstrapCopiesDefaultsToKeychainWhenMissing() {
        let defaultsKeys = [
            "node.instanceId",
            "gateway.preferredStableID",
            "gateway.lastDiscoveredStableID",
        ]
        let entries = [instanceIdEntry, preferredGatewayEntry, lastGatewayEntry]
        let defaultsSnapshot = snapshotDefaults(defaultsKeys)
        let keychainSnapshot = snapshotKeychain(entries)
        defer {
            restoreDefaults(defaultsSnapshot)
            restoreKeychain(keychainSnapshot)
        }

        applyDefaults([
            "node.instanceId": "node-test",
            "gateway.preferredStableID": "preferred-test",
            "gateway.lastDiscoveredStableID": "last-test",
        ])
        applyKeychain([
            instanceIdEntry: nil,
            preferredGatewayEntry: nil,
            lastGatewayEntry: nil,
        ])

        GatewaySettingsStore.bootstrapPersistence()

        #expect(KeychainStore.loadString(service: nodeService, account: "instanceId") == "node-test")
        #expect(KeychainStore.loadString(service: gatewayService, account: "preferredStableID") == "preferred-test")
        #expect(KeychainStore.loadString(service: gatewayService, account: "lastDiscoveredStableID") == "last-test")
    }

    /// 测试当 UserDefaults 中缺少数据时，从 Keychain 复制数据到 UserDefaults
    @Test func bootstrapCopiesKeychainToDefaultsWhenMissing() {
        let defaultsKeys = [
            "node.instanceId",
            "gateway.preferredStableID",
            "gateway.lastDiscoveredStableID",
        ]
        let entries = [instanceIdEntry, preferredGatewayEntry, lastGatewayEntry]
        let defaultsSnapshot = snapshotDefaults(defaultsKeys)
        let keychainSnapshot = snapshotKeychain(entries)
        defer {
            restoreDefaults(defaultsSnapshot)
            restoreKeychain(keychainSnapshot)
        }

        applyDefaults([
            "node.instanceId": nil,
            "gateway.preferredStableID": nil,
            "gateway.lastDiscoveredStableID": nil,
        ])
        applyKeychain([
            instanceIdEntry: "node-from-keychain",
            preferredGatewayEntry: "preferred-from-keychain",
            lastGatewayEntry: "last-from-keychain",
        ])

        GatewaySettingsStore.bootstrapPersistence()

        let defaults = UserDefaults.standard
        #expect(defaults.string(forKey: "node.instanceId") == "node-from-keychain")
        #expect(defaults.string(forKey: "gateway.preferredStableID") == "preferred-from-keychain")
        #expect(defaults.string(forKey: "gateway.lastDiscoveredStableID") == "last-from-keychain")
    }
}

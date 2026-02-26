import Foundation
import Security

/// Keychain 存储工具类，用于安全地存储、读取和删除字符串数据
/// 
/// 该类提供了一组静态方法，用于与 iOS 的 Keychain 服务进行交互，
/// 实现了字符串数据的安全存储和管理。
enum KeychainStore {
    
    /// 从 Keychain 中加载字符串
    /// 
    /// - Parameters:
    ///   - service: 服务标识符，用于区分不同的应用或功能
    ///   - account: 账户标识符，用于在同一服务中区分不同的条目
    /// - Returns: 存储的字符串，如果不存在或读取失败则返回 nil
    static func loadString(service: String, account: String) -> String? {
        // 构建查询字典，指定要查找的 Keychain 项
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,      // 项类型为通用密码
            kSecAttrService as String: service,                 // 服务标识符
            kSecAttrAccount as String: account,                 // 账户标识符
            kSecReturnData as String: true,                     // 返回数据
            kSecMatchLimit as String: kSecMatchLimitOne,        // 只返回一个匹配项
        ]

        var item: CFTypeRef?
        // 执行查询操作
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        // 检查操作是否成功，并将返回的数据转换为字符串
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 向 Keychain 中保存字符串
    /// 
    /// - Parameters:
    ///   - value: 要保存的字符串值
    ///   - service: 服务标识符，用于区分不同的应用或功能
    ///   - account: 账户标识符，用于在同一服务中区分不同的条目
    /// - Returns: 保存是否成功
    static func saveString(_ value: String, service: String, account: String) -> Bool {
        // 将字符串转换为数据
        let data = Data(value.utf8)
        // 构建查询字典，指定要更新的 Keychain 项
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,      // 项类型为通用密码
            kSecAttrService as String: service,                 // 服务标识符
            kSecAttrAccount as String: account,                 // 账户标识符
        ]

        // 构建更新字典，包含要保存的数据
        let update: [String: Any] = [kSecValueData as String: data]
        // 尝试更新现有项
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        
        // 如果更新成功，返回 true
        if status == errSecSuccess { return true }
        // 如果不是因为项不存在而失败，返回 false
        if status != errSecItemNotFound { return false }

        // 如果项不存在，则创建新项
        var insert = query
        insert[kSecValueData as String] = data                                   // 添加要保存的数据
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly  // 设置访问权限
        // 执行添加操作并返回结果
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    /// 从 Keychain 中删除指定的项
    /// 
    /// - Parameters:
    ///   - service: 服务标识符，用于区分不同的应用或功能
    ///   - account: 账户标识符，用于在同一服务中区分不同的条目
    /// - Returns: 删除是否成功（如果项不存在也视为成功）
    static func delete(service: String, account: String) -> Bool {
        // 构建查询字典，指定要删除的 Keychain 项
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,      // 项类型为通用密码
            kSecAttrService as String: service,                 // 服务标识符
            kSecAttrAccount as String: account,                 // 账户标识符
        ]
        // 执行删除操作
        let status = SecItemDelete(query as CFDictionary)
        // 返回结果，项不存在也视为成功
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

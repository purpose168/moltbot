import Foundation
import Testing
@testable import Moltbot

/// KeychainStore 测试套件
/// 测试 KeychainStore 的保存、加载、更新和删除功能
@Suite struct KeychainStoreTests {
    /// 测试保存、加载、更新和删除的完整流程
    /// 验证数据可以正确地保存到 Keychain，然后读取，更新，最后删除
    @Test func saveLoadUpdateDeleteRoundTrip() {
        // 生成唯一的服务名称，避免测试之间的干扰
        let service = "bot.molt.tests.\(UUID().uuidString)"
        // 测试使用的账户名称
        let account = "value"

        // 首先删除可能存在的旧数据
        #expect(KeychainStore.delete(service: service, account: account))
        // 验证数据已被删除
        #expect(KeychainStore.loadString(service: service, account: account) == nil)

        // 保存第一个字符串值
        #expect(KeychainStore.saveString("first", service: service, account: account))
        // 验证保存成功并能正确读取
        #expect(KeychainStore.loadString(service: service, account: account) == "first")

        // 更新字符串值为第二个值
        #expect(KeychainStore.saveString("second", service: service, account: account))
        // 验证更新成功并能正确读取新值
        #expect(KeychainStore.loadString(service: service, account: account) == "second")

        // 删除数据
        #expect(KeychainStore.delete(service: service, account: account))
        // 验证数据已被删除
        #expect(KeychainStore.loadString(service: service, account: account) == nil)
    }
}

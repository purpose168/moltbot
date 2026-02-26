import Testing
@testable import Moltbot

/// 测试网络设置辅助功能
@Suite struct SettingsNetworkingHelpersTests {
    /// 测试解析IPv4地址和端口
    @Test func parseHostPortParsesIPv4() {
        #expect(SettingsNetworkingHelpers.parseHostPort(from: "127.0.0.1:8080") == .init(host: "127.0.0.1", port: 8080))
    }

    /// 测试解析主机名并去除空白字符
    @Test func parseHostPortParsesHostnameAndTrims() {
        #expect(SettingsNetworkingHelpers.parseHostPort(from: "  example.com:80 \n") == .init(
            host: "example.com",
            port: 80))
    }

    /// 测试解析带方括号的IPv6地址
    @Test func parseHostPortParsesBracketedIPv6() {
        #expect(
            SettingsNetworkingHelpers.parseHostPort(from: "[2001:db8::1]:443") ==
                .init(host: "2001:db8::1", port: 443))
    }

    /// 测试拒绝缺少端口的输入
    @Test func parseHostPortRejectsMissingPort() {
        #expect(SettingsNetworkingHelpers.parseHostPort(from: "example.com") == nil)
        #expect(SettingsNetworkingHelpers.parseHostPort(from: "[2001:db8::1]") == nil)
    }

    /// 测试拒绝无效端口的输入
    @Test func parseHostPortRejectsInvalidPort() {
        #expect(SettingsNetworkingHelpers.parseHostPort(from: "example.com:lol") == nil)
        #expect(SettingsNetworkingHelpers.parseHostPort(from: "[2001:db8::1]:lol") == nil)
    }

    /// 测试格式化IPv4地址和端口为HTTP URL字符串
    @Test func httpURLStringFormatsIPv4AndPort() {
        #expect(SettingsNetworkingHelpers
            .httpURLString(host: "127.0.0.1", port: 8080, fallback: "fallback") == "http://127.0.0.1:8080")
    }

    /// 测试为IPv6地址添加方括号并格式化为HTTP URL字符串
    @Test func httpURLStringBracketsIPv6() {
        #expect(SettingsNetworkingHelpers
            .httpURLString(host: "2001:db8::1", port: 8080, fallback: "fallback") == "http://[2001:db8::1]:8080")
    }

    /// 测试保留已经带方括号的IPv6地址并格式化为HTTP URL字符串
    @Test func httpURLStringLeavesAlreadyBracketedIPv6() {
        #expect(SettingsNetworkingHelpers
            .httpURLString(host: "[2001:db8::1]", port: 8080, fallback: "fallback") == "http://[2001:db8::1]:8080")
    }

    /// 测试当缺少主机或端口时使用回退值
    @Test func httpURLStringFallsBackWhenMissingHostOrPort() {
        #expect(SettingsNetworkingHelpers.httpURLString(host: nil, port: 80, fallback: "x") == "http://x")
        #expect(SettingsNetworkingHelpers.httpURLString(host: "example.com", port: nil, fallback: "y") == "http://y")
    }
}

import MoltbotProtocol
import Foundation

/// Moltbot 配置文件管理枚举
enum MoltbotConfigFile {
    /// 配置日志记录器
    private static let logger = Logger(subsystem: "bot.molt", category: "config")

    /// 获取配置文件的 URL
    /// - Returns: 配置文件的 URL
    static func url() -> URL {
        MoltbotPaths.configURL
    }

    /// 获取状态目录的 URL
    /// - Returns: 状态目录的 URL
    static func stateDirURL() -> URL {
        MoltbotPaths.stateDirURL
    }

    /// 获取默认工作区的 URL
    /// - Returns: 默认工作区的 URL
    static func defaultWorkspaceURL() -> URL {
        MoltbotPaths.workspaceURL
    }

    /// 加载配置字典
    /// - Returns: 配置字典，如果加载失败则返回空字典
    static func loadDict() -> [String: Any] {
        let url = self.url()
        // 检查配置文件是否存在
        guard FileManager().fileExists(atPath: url.path) else { return [:] }
        do {
            // 读取配置文件数据
            let data = try Data(contentsOf: url)
            // 解析配置数据
            guard let root = self.parseConfigData(data) else {
                self.logger.warning("配置 JSON 根节点无效")
                return [:]
            }
            return root
        } catch {
            self.logger.warning("配置读取失败: \(error.localizedDescription)")
            return [:]
        }
    }

    /// 保存配置字典
    /// - Parameter dict: 要保存的配置字典
    static func saveDict(_ dict: [String: Any]) {
        // Nix 模式在生产环境中禁用配置写入，但测试依赖于保存临时配置
        if ProcessInfo.processInfo.isNixMode, !ProcessInfo.processInfo.isRunningTests { return }
        do {
            // 将配置字典序列化为 JSON 数据
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
            let url = self.url()
            // 创建目录（如果不存在）
            try FileManager().createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            // 写入数据（原子操作）
            try data.write(to: url, options: [.atomic])
        } catch {
            self.logger.error("配置保存失败: \(error.localizedDescription)")
        }
    }

    /// 加载网关配置字典
    /// - Returns: 网关配置字典，如果不存在则返回空字典
    static func loadGatewayDict() -> [String: Any] {
        let root = self.loadDict()
        return root["gateway"] as? [String: Any] ?? [:]
    }

    /// 更新网关配置字典
    /// - Parameter mutate: 用于修改网关配置的闭包
    static func updateGatewayDict(_ mutate: (inout [String: Any]) -> Void) {
        var root = self.loadDict()
        var gateway = root["gateway"] as? [String: Any] ?? [:]
        // 应用修改
        mutate(&gateway)
        // 如果网关配置为空，则从根配置中移除
        if gateway.isEmpty {
            root.removeValue(forKey: "gateway")
        } else {
            root["gateway"] = gateway
        }
        // 保存配置
        self.saveDict(root)
    }

    /// 检查浏览器控制是否启用
    /// - Parameter defaultValue: 默认值，默认为 true
    /// - Returns: 浏览器控制是否启用
    static func browserControlEnabled(defaultValue: Bool = true) -> Bool {
        let root = self.loadDict()
        let browser = root["browser"] as? [String: Any]
        return browser?["enabled"] as? Bool ?? defaultValue
    }

    /// 设置浏览器控制是否启用
    /// - Parameter enabled: 是否启用浏览器控制
    static func setBrowserControlEnabled(_ enabled: Bool) {
        var root = self.loadDict()
        var browser = root["browser"] as? [String: Any] ?? [:]
        browser["enabled"] = enabled
        root["browser"] = browser
        self.saveDict(root)
        self.logger.debug("浏览器控制已更新 enabled=\(enabled)")
    }

    /// 获取代理工作区
    /// - Returns: 代理工作区路径，如果不存在则返回 nil
    static func agentWorkspace() -> String? {
        let root = self.loadDict()
        let agents = root["agents"] as? [String: Any]
        let defaults = agents?["defaults"] as? [String: Any]
        return defaults?["workspace"] as? String
    }

    /// 设置代理工作区
    /// - Parameter workspace: 代理工作区路径，设置为 nil 或空字符串将移除该设置
    static func setAgentWorkspace(_ workspace: String?) {
        var root = self.loadDict()
        var agents = root["agents"] as? [String: Any] ?? [:]
        var defaults = agents["defaults"] as? [String: Any] ?? [:]
        // 去除空白字符
        let trimmed = workspace?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            // 如果为空，则移除工作区设置
            defaults.removeValue(forKey: "workspace")
        } else {
            // 否则设置工作区
            defaults["workspace"] = trimmed
        }
        // 清理空字典
        if defaults.isEmpty {
            agents.removeValue(forKey: "defaults")
        } else {
            agents["defaults"] = defaults
        }
        if agents.isEmpty {
            root.removeValue(forKey: "agents")
        } else {
            root["agents"] = agents
        }
        // 保存配置
        self.saveDict(root)
        self.logger.debug("agents.defaults.workspace 已更新 set=\(!trimmed.isEmpty)")
    }

    /// 获取网关密码
    /// - Returns: 网关密码，如果不存在则返回 nil
    static func gatewayPassword() -> String? {
        let root = self.loadDict()
        guard let gateway = root["gateway"] as? [String: Any],
              let remote = gateway["remote"] as? [String: Any]
        else {
            return nil
        }
        return remote["password"] as? String
    }

    /// 获取网关端口
    /// - Returns: 网关端口，如果不存在或无效则返回 nil
    static func gatewayPort() -> Int? {
        let root = self.loadDict()
        guard let gateway = root["gateway"] as? [String: Any] else { return nil }
        // 尝试直接获取 Int 类型的端口
        if let port = gateway["port"] as? Int, port > 0 { return port }
        // 尝试获取 NSNumber 类型的端口
        if let number = gateway["port"] as? NSNumber, number.intValue > 0 {
            return number.intValue
        }
        // 尝试解析字符串类型的端口
        if let raw = gateway["port"] as? String,
           let parsed = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           parsed > 0
        {
            return parsed
        }
        return nil
    }

    /// 获取远程网关端口
    /// - Returns: 远程网关端口，如果不存在或无效则返回 nil
    static func remoteGatewayPort() -> Int? {
        guard let url = self.remoteGatewayUrl(),
              let port = url.port,
              port > 0
        else { return nil }
        return port
    }

    /// 获取匹配指定 SSH 主机的远程网关端口
    /// - Parameter sshHost: SSH 主机地址
    /// - Returns: 匹配的远程网关端口，如果不存在或不匹配则返回 nil
    static func remoteGatewayPort(matchingHost sshHost: String) -> Int? {
        let trimmedSshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSshHost.isEmpty,
              let url = self.remoteGatewayUrl(),
              let port = url.port,
              port > 0,
              let urlHost = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlHost.isEmpty
        else {
            return nil
        }

        // 生成主机键并比较
        let sshKey = Self.hostKey(trimmedSshHost)
        let urlKey = Self.hostKey(urlHost)
        guard !sshKey.isEmpty, !urlKey.isEmpty, sshKey == urlKey else { return nil }
        return port
    }

    /// 设置远程网关 URL
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口号
    static func setRemoteGatewayUrl(host: String, port: Int?) {
        // 验证端口有效性
        guard let port, port > 0 else { return }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // 验证主机地址有效性
        guard !trimmedHost.isEmpty else { return }
        // 更新网关配置
        self.updateGatewayDict { gateway in
            var remote = gateway["remote"] as? [String: Any] ?? [:]
            // 保留现有 URL 的协议方案
            let existingUrl = (remote["url"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let scheme = URL(string: existingUrl)?.scheme ?? "ws"
            // 构建新的 URL
            remote["url"] = "\(scheme)://\(trimmedHost):\(port)"
            gateway["remote"] = remote
        }
    }

    /// 获取远程网关 URL
    /// - Returns: 远程网关 URL，如果不存在或无效则返回 nil
    private static func remoteGatewayUrl() -> URL? {
        let root = self.loadDict()
        guard let gateway = root["gateway"] as? [String: Any],
              let remote = gateway["remote"] as? [String: Any],
              let raw = remote["url"] as? String
        else {
            return nil
        }
        // 去除空白字符
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // 验证并创建 URL
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }
        return url
    }

    /// 生成主机键，用于比较主机地址
    /// - Parameter host: 主机地址
    /// - Returns: 标准化的主机键
    private static func hostKey(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        // 如果包含冒号（IPv6 地址），直接返回
        if trimmed.contains(":") { return trimmed }
        // 检查是否为纯数字和点组成的地址（IPv4 地址）
        let digits = CharacterSet(charactersIn: "0123456789.")
        if trimmed.rangeOfCharacter(from: digits.inverted) == nil {
            return trimmed
        }
        // 对于域名，返回第一个部分（去掉后缀）
        return trimmed.split(separator: ".").first.map(String.init) ?? trimmed
    }

    /// 解析配置数据
    /// - Parameter data: 配置文件数据
    /// - Returns: 解析后的配置字典，如果解析失败则返回 nil
    private static func parseConfigData(_ data: Data) -> [String: Any]? {
        // 尝试使用标准 JSON 序列化解析
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return root
        }
        // 尝试使用 JSON5 解析（如果支持）
        let decoder = JSONDecoder()
        if #available(macOS 12.0, *) {
            decoder.allowsJSON5 = true
        }
        if let decoded = try? decoder.decode([String: AnyCodable].self, from: data) {
            self.logger.notice("使用 JSON5 解码器解析配置")
            return decoded.mapValues { $0.foundationValue }
        }
        return nil
    }
}

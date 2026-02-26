import MoltbotProtocol
import Foundation

/// ChannelsStore 的配置相关扩展
/// 提供配置加载、更新和管理功能
extension ChannelsStore {
    /// 加载配置架构
    /// 从服务器获取配置架构信息并解析
    func loadConfigSchema() async {
        // 防止重复加载
        guard !self.configSchemaLoading else { return }
        self.configSchemaLoading = true
        defer { self.configSchemaLoading = false }

        do {
            // 请求配置架构数据
            let res: ConfigSchemaResponse = try await GatewayConnection.shared.requestDecoded(
                method: .configSchema,
                params: nil,
                timeoutMs: 8000)
            // 提取架构值并创建节点
            let schemaValue = res.schema.foundationValue
            self.configSchema = ConfigSchemaNode(raw: schemaValue)
            // 处理 UI 提示信息
            let hintValues = res.uihints.mapValues { $0.foundationValue }
            self.configUiHints = decodeUiHints(hintValues)
        } catch {
            // 处理错误
            self.configStatus = error.localizedDescription
        }
    }

    /// 加载配置
    /// 从服务器获取配置快照并应用
    func loadConfig() async {
        do {
            // 请求配置快照
            let snap: ConfigSnapshot = try await GatewayConnection.shared.requestDecoded(
                method: .configGet,
                params: nil,
                timeoutMs: 10000)
            // 检查配置有效性
            self.configStatus = snap.valid == false
                ? "配置无效；请在 ~/.clawdbot/moltbot.json 中修复。"
                : nil
            // 处理配置数据
            self.configRoot = snap.config?.mapValues { $0.foundationValue } ?? [:]
            self.configDraft = cloneConfigValue(self.configRoot) as? [String: Any] ?? self.configRoot
            self.configDirty = false
            self.configLoaded = true

            // 应用 UI 配置
            self.applyUIConfig(snap)
        } catch {
            // 处理错误
            self.configStatus = error.localizedDescription
        }
    }

    /// 应用 UI 配置
    /// 从配置快照中提取并应用 UI 相关设置
    private func applyUIConfig(_ snap: ConfigSnapshot) {
        // 提取 UI 配置
        let ui = snap.config?["ui"]?.dictionaryValue
        // 处理接缝颜色设置
        let rawSeam = ui?["seamColor"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        AppStateStore.shared.seamColorHex = rawSeam.isEmpty ? nil : rawSeam
    }

    /// 获取指定频道的配置架构
    /// - Parameter channelId: 频道 ID
    /// - Returns: 对应的配置架构节点
    func channelConfigSchema(for channelId: String) -> ConfigSchemaNode? {
        guard let root = self.configSchema else { return nil }
        return root.node(at: [.key("channels"), .key(channelId)])
    }

    /// 获取指定路径的配置值
    /// - Parameter path: 配置路径
    /// - Returns: 配置值，如果不存在则返回 nil
    func configValue(at path: ConfigPath) -> Any? {
        // 尝试从配置草稿中获取值
        if let value = valueAtPath(self.configDraft, path: path) {
            return value
        }
        // 检查路径长度
        guard path.count >= 2 else { return nil }
        // 处理频道配置的特殊情况
        if case .key("channels") = path[0], case .key = path[1] {
            let fallbackPath = Array(path.dropFirst())
            return valueAtPath(self.configDraft, path: fallbackPath)
        }
        return nil
    }

    /// 更新配置值
    /// - Parameters:
    ///   - path: 配置路径
    ///   - value: 新的配置值
    func updateConfigValue(path: ConfigPath, value: Any?) {
        var root: Any = self.configDraft
        // 设置新值
        setValue(&root, path: path, value: value)
        // 更新配置草稿并标记为脏
        self.configDraft = root as? [String: Any] ?? self.configDraft
        self.configDirty = true
    }

    /// 保存配置草稿
    /// 将当前配置草稿保存到存储并重新加载
    func saveConfigDraft() async {
        // 防止重复保存
        guard !self.isSavingConfig else { return }
        self.isSavingConfig = true
        defer { self.isSavingConfig = false }

        do {
            // 保存配置
            try await ConfigStore.save(self.configDraft)
            // 重新加载配置
            await self.loadConfig()
        } catch {
            // 处理错误
            self.configStatus = error.localizedDescription
        }
    }

    /// 重新加载配置草稿
    /// 从存储重新加载配置
    func reloadConfigDraft() async {
        await self.loadConfig()
    }
}

/// 根据路径获取值
/// - Parameters:
///   - root: 根对象
///   - path: 配置路径
/// - Returns: 路径对应的值，如果不存在则返回 nil
private func valueAtPath(_ root: Any, path: ConfigPath) -> Any? {
    var current: Any? = root
    // 遍历路径 segments
    for segment in path {
        switch segment {
        case let .key(key):
            // 处理字典类型
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        case let .index(index):
            // 处理数组类型
            guard let array = current as? [Any], array.indices.contains(index) else { return nil }
            current = array[index]
        }
    }
    return current
}

/// 根据路径设置值
/// - Parameters:
///   - root: 根对象（inout）
///   - path: 配置路径
///   - value: 要设置的值
private func setValue(_ root: inout Any, path: ConfigPath, value: Any?) {
    guard let segment = path.first else { return }
    switch segment {
    case let .key(key):
        // 处理字典类型
        var dict = root as? [String: Any] ?? [:]
        if path.count == 1 {
            // 到达路径末尾，设置值
            if let value {
                dict[key] = value
            } else {
                dict.removeValue(forKey: key)
            }
            root = dict
            return
        }
        // 递归处理子路径
        var child = dict[key] ?? [:]
        setValue(&child, path: Array(path.dropFirst()), value: value)
        dict[key] = child
        root = dict
    case let .index(index):
        // 处理数组类型
        var array = root as? [Any] ?? []
        // 确保数组长度足够
        if index >= array.count {
            array.append(contentsOf: repeatElement(NSNull() as Any, count: index - array.count + 1))
        }
        if path.count == 1 {
            // 到达路径末尾，设置值
            if let value {
                array[index] = value
            } else if array.indices.contains(index) {
                array.remove(at: index)
            }
            root = array
            return
        }
        // 递归处理子路径
        var child = array[index]
        setValue(&child, path: Array(path.dropFirst()), value: value)
        array[index] = child
        root = array
    }
}

/// 克隆配置值
/// 通过 JSON 序列化和反序列化实现深拷贝
/// - Parameter value: 要克隆的值
/// - Returns: 克隆后的值
private func cloneConfigValue(_ value: Any) -> Any {
    // 检查是否为有效的 JSON 对象
    guard JSONSerialization.isValidJSONObject(value) else { return value }
    do {
        // 序列化和反序列化实现深拷贝
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        return try JSONSerialization.jsonObject(with: data, options: [])
    } catch {
        // 出错时返回原值
        return value
    }
}

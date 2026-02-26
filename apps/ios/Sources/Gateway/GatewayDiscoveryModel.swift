import MoltbotKit
import Foundation
import Network
import Observation

/// 网关发现模型，用于发现网络中的Moltbot网关设备
@MainActor
@Observable
final class GatewayDiscoveryModel {
    /// 调试日志条目结构
    struct DebugLogEntry: Identifiable, Equatable {
        var id = UUID()
        var ts: Date        // 时间戳
        var message: String // 日志消息
    }

    /// 已发现的网关设备结构
    struct DiscoveredGateway: Identifiable, Equatable {
        var id: String { self.stableID } // 使用stableID作为唯一标识符
        var name: String                 // 网关名称
        var endpoint: NWEndpoint         // 网络端点
        var stableID: String             // 稳定标识符
        var debugID: String              // 调试标识符
        var lanHost: String?             // 局域网主机地址
        var tailnetDns: String?          // Tailnet DNS地址
        var gatewayPort: Int?            // 网关端口
        var canvasPort: Int?             // Canvas端口
        var tlsEnabled: Bool             // 是否启用TLS
        var tlsFingerprintSha256: String? // TLS指纹（SHA256）
        var cliPath: String?             // CLI路径
    }

    /// 已发现的网关列表
    var gateways: [DiscoveredGateway] = []
    /// 当前状态文本
    var statusText: String = "空闲"
    /// 调试日志
    private(set) var debugLog: [DebugLogEntry] = []

    /// 按域存储的浏览器实例
    private var browsers: [String: NWBrowser] = [:]
    /// 按域存储的网关列表
    private var gatewaysByDomain: [String: [DiscoveredGateway]] = [:]
    /// 按域存储的浏览器状态
    private var statesByDomain: [String: NWBrowser.State] = [:]
    /// 是否启用调试日志
    private var debugLoggingEnabled = false
    /// 上次的稳定标识符集合
    private var lastStableIDs = Set<String>()

    /// 设置是否启用调试日志
    /// - Parameter enabled: 是否启用调试日志
    func setDebugLoggingEnabled(_ enabled: Bool) {
        let wasEnabled = self.debugLoggingEnabled
        self.debugLoggingEnabled = enabled
        if !enabled {
            self.debugLog = []
        } else if !wasEnabled {
            self.appendDebugLog("调试日志已启用")
            self.appendDebugLog("快照: 状态=\(self.statusText) 网关=\(self.gateways.count)")
        }
    }

    /// 开始网关发现
    func start() {
        if !self.browsers.isEmpty { return }
        self.appendDebugLog("开始()")

        // 遍历所有网关服务域
        for domain in MoltbotBonjour.gatewayServiceDomains {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let browser = NWBrowser(
                for: .bonjour(type: MoltbotBonjour.gatewayServiceType, domain: domain),
                using: params)

            // 设置状态更新处理器
            browser.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.statesByDomain[domain] = state
                    self.updateStatusText()
                    self.appendDebugLog("状态[\(domain)]: \(Self.prettyState(state))")
                }
            }

            // 设置浏览结果变更处理器
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.gatewaysByDomain[domain] = results.compactMap { result -> DiscoveredGateway? in
                        switch result.endpoint {
                        case let .service(name, _, _, _):
                            let decodedName = BonjourEscapes.decode(name)
                            let txt = result.endpoint.txtRecord?.dictionary ?? [:]
                            let advertisedName = txt["displayName"]
                            let prettyAdvertised = advertisedName
                                .map(Self.prettifyInstanceName)
                                .flatMap { $0.isEmpty ? nil : $0 }
                            let prettyName = prettyAdvertised ?? Self.prettifyInstanceName(decodedName)
                            return DiscoveredGateway(
                                name: prettyName,
                                endpoint: result.endpoint,
                                stableID: GatewayEndpointID.stableID(result.endpoint),
                                debugID: GatewayEndpointID.prettyDescription(result.endpoint),
                                lanHost: Self.txtValue(txt, key: "lanHost"),
                                tailnetDns: Self.txtValue(txt, key: "tailnetDns"),
                                gatewayPort: Self.txtIntValue(txt, key: "gatewayPort"),
                                canvasPort: Self.txtIntValue(txt, key: "canvasPort"),
                                tlsEnabled: Self.txtBoolValue(txt, key: "gatewayTls"),
                                tlsFingerprintSha256: Self.txtValue(txt, key: "gatewayTlsSha256"),
                                cliPath: Self.txtValue(txt, key: "cliPath"))
                        default:
                            return nil
                        }
                    }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

                    self.recomputeGateways()
                }
            }

            self.browsers[domain] = browser
            browser.start(queue: DispatchQueue(label: "bot.molt.ios.gateway-discovery.\(domain)"))
        }
    }

    /// 停止网关发现
    func stop() {
        self.appendDebugLog("停止()")
        for browser in self.browsers.values {
            browser.cancel()
        }
        self.browsers = [:]
        self.gatewaysByDomain = [:]
        self.statesByDomain = [:]
        self.gateways = []
        self.statusText = "已停止"
    }

    /// 重新计算网关列表
    private func recomputeGateways() {
        let next = self.gatewaysByDomain.values
            .flatMap(\.self)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let nextIDs = Set(next.map(\.stableID))
        let added = nextIDs.subtracting(self.lastStableIDs)
        let removed = self.lastStableIDs.subtracting(nextIDs)
        if !added.isEmpty || !removed.isEmpty {
            self.appendDebugLog("结果: 总数=\(next.count) 新增=\(added.count) 移除=\(removed.count)")
        }
        self.lastStableIDs = nextIDs
        self.gateways = next
    }

    /// 更新状态文本
    private func updateStatusText() {
        let states = Array(self.statesByDomain.values)
        if states.isEmpty {
            self.statusText = self.browsers.isEmpty ? "空闲" : "设置中"
            return
        }

        // 检查是否有失败状态
        if let failed = states.first(where: { state in
            if case .failed = state { return true }
            return false
        }) {
            if case let .failed(err) = failed {
                self.statusText = "失败: \(err)"
                return
            }
        }

        // 检查是否有等待状态
        if let waiting = states.first(where: { state in
            if case .waiting = state { return true }
            return false
        }) {
            if case let .waiting(err) = waiting {
                self.statusText = "等待: \(err)"
                return
            }
        }

        // 检查是否有就绪状态
        if states.contains(where: { if case .ready = $0 { true } else { false } }) {
            self.statusText = "搜索中…"
            return
        }

        // 检查是否有设置状态
        if states.contains(where: { if case .setup = $0 { true } else { false } }) {
            self.statusText = "设置中"
            return
        }

        self.statusText = "搜索中…"
    }

    /// 将浏览器状态转换为可读字符串
    /// - Parameter state: 浏览器状态
    /// - Returns: 可读的状态字符串
    private static func prettyState(_ state: NWBrowser.State) -> String {
        switch state {
        case .setup:
            "设置中"
        case .ready:
            "就绪"
        case let .failed(err):
            "失败 (\(err))"
        case .cancelled:
            "已取消"
        case let .waiting(err):
            "等待 (\(err))"
        @unknown default:
            "未知"
        }
    }

    /// 添加调试日志
    /// - Parameter message: 日志消息
    private func appendDebugLog(_ message: String) {
        guard self.debugLoggingEnabled else { return }
        self.debugLog.append(DebugLogEntry(ts: Date(), message: message))
        if self.debugLog.count > 200 {
            self.debugLog.removeFirst(self.debugLog.count - 200)
        }
    }

    /// 美化实例名称
    /// - Parameter decodedName: 解码后的名称
    /// - Returns: 美化后的名称
    private static func prettifyInstanceName(_ decodedName: String) -> String {
        let normalized = decodedName.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let stripped = normalized.replacingOccurrences(of: " (Moltbot)", with: "")
            .replacingOccurrences(of: #"\s+\(\d+\)$"#, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从TXT记录中获取字符串值
    /// - Parameters:
    ///   - dict: TXT记录字典
    ///   - key: 键
    /// - Returns: 字符串值，为空则返回nil
    private static func txtValue(_ dict: [String: String], key: String) -> String? {
        let raw = dict[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// 从TXT记录中获取整数值
    /// - Parameters:
    ///   - dict: TXT记录字典
    ///   - key: 键
    /// - Returns: 整数值，为空或无效则返回nil
    private static func txtIntValue(_ dict: [String: String], key: String) -> Int? {
        guard let raw = self.txtValue(dict, key: key) else { return nil }
        return Int(raw)
    }

    /// 从TXT记录中获取布尔值
    /// - Parameters:
    ///   - dict: TXT记录字典
    ///   - key: 键
    /// - Returns: 布尔值，为空则返回false
    private static func txtBoolValue(_ dict: [String: String], key: String) -> Bool {
        guard let raw = self.txtValue(dict, key: key)?.lowercased() else { return false }
        return raw == "1" || raw == "true" || raw == "yes"
    }
}

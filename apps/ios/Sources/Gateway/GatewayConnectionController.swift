import MoltbotKit
import Darwin
import Foundation
import Network
import Observation
import SwiftUI
import UIKit

/// 网关连接控制器，负责管理与网关的连接，包括网关发现、自动连接等功能
@MainActor
@Observable
final class GatewayConnectionController {
    /// 已发现的网关列表
    private(set) var gateways: [GatewayDiscoveryModel.DiscoveredGateway] = []
    /// 发现状态文本
    private(set) var discoveryStatusText: String = "空闲"
    /// 发现调试日志
    private(set) var discoveryDebugLog: [GatewayDiscoveryModel.DebugLogEntry] = []

    /// 网关发现模型
    private let discovery = GatewayDiscoveryModel()
    /// 应用模型弱引用
    private weak var appModel: NodeAppModel?
    /// 是否已自动连接
    private var didAutoConnect = false

    /// 初始化网关连接控制器
    /// - Parameters:
    ///   - appModel: 应用模型
    ///   - startDiscovery: 是否启动发现，默认为true
    init(appModel: NodeAppModel, startDiscovery: Bool = true) {
        self.appModel = appModel

        // 初始化网关设置存储
        GatewaySettingsStore.bootstrapPersistence()
        let defaults = UserDefaults.standard
        // 设置调试日志启用状态
        self.discovery.setDebugLoggingEnabled(defaults.bool(forKey: "gateway.discovery.debugLogs"))

        // 从发现模型更新状态
        self.updateFromDiscovery()
        // 观察发现模型变化
        self.observeDiscovery()

        // 如果需要启动发现
        if startDiscovery {
            self.discovery.start()
        }
    }

    /// 设置发现调试日志启用状态
    /// - Parameter enabled: 是否启用
    func setDiscoveryDebugLoggingEnabled(_ enabled: Bool) {
        self.discovery.setDebugLoggingEnabled(enabled)
    }

    /// 设置场景阶段
    /// - Parameter phase: 场景阶段
    func setScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            // 后台状态停止发现
            self.discovery.stop()
        case .active, .inactive:
            // 活跃或非活跃状态启动发现
            self.discovery.start()
        @unknown default:
            // 未知状态启动发现
            self.discovery.start()
        }
    }

    /// 连接到指定网关
    /// - Parameter gateway: 要连接的网关
    func connect(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        // 获取实例ID
        let instanceId = UserDefaults.standard.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 加载网关令牌和密码
        let token = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        let password = GatewaySettingsStore.loadGatewayPassword(instanceId: instanceId)
        // 解析网关主机
        guard let host = self.resolveGatewayHost(gateway) else { return }
        // 获取网关端口
        let port = gateway.gatewayPort ?? 18789
        // 解析TLS参数
        let tlsParams = self.resolveDiscoveredTLSParams(gateway: gateway)
        // 构建网关URL
        guard let url = self.buildGatewayURL(
            host: host,
            port: port,
            useTLS: tlsParams?.required == true)
        else { return }
        // 标记已自动连接
        self.didAutoConnect = true
        // 启动自动连接
        self.startAutoConnect(
            url: url,
            gatewayStableID: gateway.stableID,
            tls: tlsParams,
            token: token,
            password: password)
    }

    /// 手动连接到网关
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口
    ///   - useTLS: 是否使用TLS
    func connectManual(host: String, port: Int, useTLS: Bool) async {
        // 获取实例ID
        let instanceId = UserDefaults.standard.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 加载网关令牌和密码
        let token = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        let password = GatewaySettingsStore.loadGatewayPassword(instanceId: instanceId)
        // 生成手动连接的稳定ID
        let stableID = self.manualStableID(host: host, port: port)
        // 解析手动TLS参数
        let tlsParams = self.resolveManualTLSParams(stableID: stableID, tlsEnabled: useTLS)
        // 构建网关URL
        guard let url = self.buildGatewayURL(
            host: host,
            port: port,
            useTLS: tlsParams?.required == true)
        else { return }
        // 标记已自动连接
        self.didAutoConnect = true
        // 启动自动连接
        self.startAutoConnect(
            url: url,
            gatewayStableID: stableID,
            tls: tlsParams,
            token: token,
            password: password)
    }

    /// 从发现模型更新状态
    private func updateFromDiscovery() {
        let newGateways = self.discovery.gateways
        self.gateways = newGateways
        self.discoveryStatusText = self.discovery.statusText
        self.discoveryDebugLog = self.discovery.debugLog
        // 更新最后发现的网关
        self.updateLastDiscoveredGateway(from: newGateways)
        // 尝试自动连接
        self.maybeAutoConnect()
    }

    /// 观察发现模型变化
    private func observeDiscovery() {
        withObservationTracking {
            _ = self.discovery.gateways
            _ = self.discovery.statusText
            _ = self.discovery.debugLog
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateFromDiscovery()
                self.observeDiscovery()
            }
        }
    }

    /// 尝试自动连接
    private func maybeAutoConnect() {
        // 如果已经自动连接，则返回
        guard !self.didAutoConnect else { return }
        // 如果没有应用模型，则返回
        guard let appModel = self.appModel else { return }
        // 如果已经有网关服务器名称，则返回
        guard appModel.gatewayServerName == nil else { return }

        let defaults = UserDefaults.standard
        // 检查是否启用手动连接
        let manualEnabled = defaults.bool(forKey: "gateway.manual.enabled")

        // 获取实例ID
        let instanceId = defaults.string(forKey: "node.instanceId")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 如果实例ID为空，则返回
        guard !instanceId.isEmpty else { return }

        // 加载网关令牌和密码
        let token = GatewaySettingsStore.loadGatewayToken(instanceId: instanceId)
        let password = GatewaySettingsStore.loadGatewayPassword(instanceId: instanceId)

        // 如果启用手动连接
        if manualEnabled {
            // 获取手动连接主机
            let manualHost = defaults.string(forKey: "gateway.manual.host")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // 如果主机为空，则返回
            guard !manualHost.isEmpty else { return }

            // 获取手动连接端口
            let manualPort = defaults.integer(forKey: "gateway.manual.port")
            let resolvedPort = manualPort > 0 ? manualPort : 18789
            // 获取是否使用TLS
            let manualTLS = defaults.bool(forKey: "gateway.manual.tls")

            // 生成手动连接的稳定ID
            let stableID = self.manualStableID(host: manualHost, port: resolvedPort)
            // 解析手动TLS参数
            let tlsParams = self.resolveManualTLSParams(stableID: stableID, tlsEnabled: manualTLS)

            // 构建网关URL
            guard let url = self.buildGatewayURL(
                host: manualHost,
                port: resolvedPort,
                useTLS: tlsParams?.required == true)
            else { return }

            // 标记已自动连接
            self.didAutoConnect = true
            // 启动自动连接
            self.startAutoConnect(
                url: url,
                gatewayStableID: stableID,
                tls: tlsParams,
                token: token,
                password: password)
            return
        }

        // 获取首选网关稳定ID
        let preferredStableID = defaults.string(forKey: "gateway.preferredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 获取最后发现的网关稳定ID
        let lastDiscoveredStableID = defaults.string(forKey: "gateway.lastDiscoveredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 过滤出非空的候选ID
        let candidates = [preferredStableID, lastDiscoveredStableID].filter { !$0.isEmpty }
        // 查找第一个在已发现网关中的候选ID
        guard let targetStableID = candidates.first(where: { id in
            self.gateways.contains(where: { $0.stableID == id })
        }) else { return }

        // 查找目标网关
        guard let target = self.gateways.first(where: { $0.stableID == targetStableID }) else { return }
        // 解析网关主机
        guard let host = self.resolveGatewayHost(target) else { return }
        // 获取网关端口
        let port = target.gatewayPort ?? 18789
        // 解析TLS参数
        let tlsParams = self.resolveDiscoveredTLSParams(gateway: target)
        // 构建网关URL
        guard let url = self.buildGatewayURL(host: host, port: port, useTLS: tlsParams?.required == true)
        else { return }

        // 标记已自动连接
        self.didAutoConnect = true
        // 启动自动连接
        self.startAutoConnect(
            url: url,
            gatewayStableID: target.stableID,
            tls: tlsParams,
            token: token,
            password: password)
    }

    /// 更新最后发现的网关
    /// - Parameter gateways: 网关列表
    private func updateLastDiscoveredGateway(from gateways: [GatewayDiscoveryModel.DiscoveredGateway]) {
        let defaults = UserDefaults.standard
        // 获取首选网关稳定ID
        let preferred = defaults.string(forKey: "gateway.preferredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 获取最后发现的网关稳定ID
        let existingLast = defaults.string(forKey: "gateway.lastDiscoveredStableID")?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 避免覆盖用户意图（首选/最后发现的网关也在手动连接时设置）
        guard preferred.isEmpty, existingLast.isEmpty else { return }
        // 如果没有网关，则返回
        guard let first = gateways.first else { return }

        // 设置最后发现的网关稳定ID
        defaults.set(first.stableID, forKey: "gateway.lastDiscoveredStableID")
        GatewaySettingsStore.saveLastDiscoveredGatewayStableID(first.stableID)
    }

    /// 启动自动连接
    /// - Parameters:
    ///   - url: 网关URL
    ///   - gatewayStableID: 网关稳定ID
    ///   - tls: TLS参数
    ///   - token: 令牌
    ///   - password: 密码
    private func startAutoConnect(
        url: URL,
        gatewayStableID: String,
        tls: GatewayTLSParams?,
        token: String?,
        password: String?
    ) {
        // 如果没有应用模型，则返回
        guard let appModel else { return }
        // 创建连接选项
        let connectOptions = self.makeConnectOptions()

        Task { [weak self] in
            guard let self else { return }
            await MainActor.run {
                // 设置网关状态文本为"连接中..."
                appModel.gatewayStatusText = "连接中..."
            }
            // 连接到网关
            appModel.connectToGateway(
                url: url,
                gatewayStableID: gatewayStableID,
                tls: tls,
                token: token,
                password: password,
                connectOptions: connectOptions)
        }
    }

    /// 解析发现的网关TLS参数
    /// - Parameter gateway: 网关
    /// - Returns: TLS参数
    private func resolveDiscoveredTLSParams(gateway: GatewayDiscoveryModel.DiscoveredGateway) -> GatewayTLSParams? {
        let stableID = gateway.stableID
        // 加载存储的指纹
        let stored = GatewayTLSStore.loadFingerprint(stableID: stableID)

        // 如果网关启用了TLS，或者有TLS指纹，或者存储了指纹
        if gateway.tlsEnabled || gateway.tlsFingerprintSha256 != nil || stored != nil {
            return GatewayTLSParams(
                required: true,
                expectedFingerprint: gateway.tlsFingerprintSha256 ?? stored,
                allowTOFU: stored == nil,
                storeKey: stableID)
        }

        return nil
    }

    /// 解析手动TLS参数
    /// - Parameters:
    ///   - stableID: 稳定ID
    ///   - tlsEnabled: 是否启用TLS
    /// - Returns: TLS参数
    private func resolveManualTLSParams(stableID: String, tlsEnabled: Bool) -> GatewayTLSParams? {
        // 加载存储的指纹
        let stored = GatewayTLSStore.loadFingerprint(stableID: stableID)
        // 如果启用了TLS，或者存储了指纹
        if tlsEnabled || stored != nil {
            return GatewayTLSParams(
                required: true,
                expectedFingerprint: stored,
                allowTOFU: stored == nil,
                storeKey: stableID)
        }

        return nil
    }

    /// 解析网关主机
    /// - Parameter gateway: 网关
    /// - Returns: 主机地址
    private func resolveGatewayHost(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> String? {
        // 优先使用局域网主机
        if let lanHost = gateway.lanHost?.trimmingCharacters(in: .whitespacesAndNewlines), !lanHost.isEmpty {
            return lanHost
        }
        // 其次使用Tailnet DNS
        if let tailnet = gateway.tailnetDns?.trimmingCharacters(in: .whitespacesAndNewlines), !tailnet.isEmpty {
            return tailnet
        }
        return nil
    }

    /// 构建网关URL
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口
    ///   - useTLS: 是否使用TLS
    /// - Returns: 网关URL
    private func buildGatewayURL(host: String, port: Int, useTLS: Bool) -> URL? {
        // 根据是否使用TLS选择协议
        let scheme = useTLS ? "wss" : "ws"
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        return components.url
    }

    /// 生成手动连接的稳定ID
    /// - Parameters:
    ///   - host: 主机地址
    ///   - port: 端口
    /// - Returns: 稳定ID
    private func manualStableID(host: String, port: Int) -> String {
        "manual|\(host.lowercased())|\(port)"
    }

    /// 创建连接选项
    /// - Returns: 连接选项
    private func makeConnectOptions() -> GatewayConnectOptions {
        let defaults = UserDefaults.standard
        // 解析显示名称
        let displayName = self.resolvedDisplayName(defaults: defaults)

        return GatewayConnectOptions(
            role: "node",
            scopes: [],
            caps: self.currentCaps(),
            commands: self.currentCommands(),
            permissions: [:],
            clientId: "moltbot-ios",
            clientMode: "node",
            clientDisplayName: displayName)
    }

    /// 解析显示名称
    /// - Parameter defaults: 用户默认设置
    /// - Returns: 显示名称
    private func resolvedDisplayName(defaults: UserDefaults) -> String {
        let key = "node.displayName"
        // 获取现有显示名称
        let existing = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 如果现有显示名称非空且不是默认值，则返回
        if !existing.isEmpty, existing != "iOS Node" { return existing }

        // 获取设备名称
        let deviceName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果设备名称为空，则使用默认值
        let candidate = deviceName.isEmpty ? "iOS Node" : deviceName

        // 如果现有显示名称为空或为默认值，则更新
        if existing.isEmpty || existing == "iOS Node" {
            defaults.set(candidate, forKey: key)
        }

        return candidate
    }

    /// 获取当前能力
    /// - Returns: 能力列表
    private func currentCaps() -> [String] {
        // 基础能力
        var caps = [MoltbotCapability.canvas.rawValue, MoltbotCapability.screen.rawValue]

        // 默认启用：如果键不存在，则视为启用
        let cameraEnabled =
            UserDefaults.standard.object(forKey: "camera.enabled") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "camera.enabled")
        // 如果启用了相机，则添加相机能力
        if cameraEnabled { caps.append(MoltbotCapability.camera.rawValue) }

        // 检查是否启用语音唤醒
        let voiceWakeEnabled = UserDefaults.standard.bool(forKey: VoiceWakePreferences.enabledKey)
        // 如果启用了语音唤醒，则添加语音唤醒能力
        if voiceWakeEnabled { caps.append(MoltbotCapability.voiceWake.rawValue) }

        // 获取位置模式
        let locationModeRaw = UserDefaults.standard.string(forKey: "location.enabledMode") ?? "off"
        let locationMode = MoltbotLocationMode(rawValue: locationModeRaw) ?? .off
        // 如果位置模式不是关闭，则添加位置能力
        if locationMode != .off { caps.append(MoltbotCapability.location.rawValue) }

        return caps
    }

    /// 获取当前命令
    /// - Returns: 命令列表
    private func currentCommands() -> [String] {
        // 基础命令
        var commands: [String] = [
            MoltbotCanvasCommand.present.rawValue,
            MoltbotCanvasCommand.hide.rawValue,
            MoltbotCanvasCommand.navigate.rawValue,
            MoltbotCanvasCommand.evalJS.rawValue,
            MoltbotCanvasCommand.snapshot.rawValue,
            MoltbotCanvasA2UICommand.push.rawValue,
            MoltbotCanvasA2UICommand.pushJSONL.rawValue,
            MoltbotCanvasA2UICommand.reset.rawValue,
            MoltbotScreenCommand.record.rawValue,
            MoltbotSystemCommand.notify.rawValue,
            MoltbotSystemCommand.which.rawValue,
            MoltbotSystemCommand.run.rawValue,
            MoltbotSystemCommand.execApprovalsGet.rawValue,
            MoltbotSystemCommand.execApprovalsSet.rawValue,
        ]

        let caps = Set(self.currentCaps())
        // 如果有相机能力，则添加相机命令
        if caps.contains(MoltbotCapability.camera.rawValue) {
            commands.append(MoltbotCameraCommand.list.rawValue)
            commands.append(MoltbotCameraCommand.snap.rawValue)
            commands.append(MoltbotCameraCommand.clip.rawValue)
        }
        // 如果有位置能力，则添加位置命令
        if caps.contains(MoltbotCapability.location.rawValue) {
            commands.append(MoltbotLocationCommand.get.rawValue)
        }

        return commands
    }

    /// 获取平台字符串
    /// - Returns: 平台字符串
    private func platformString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        // 根据设备类型确定平台名称
        let name = switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            "iPadOS"
        case .phone:
            "iOS"
        default:
            "iOS"
        }
        // 返回平台名称和版本号
        return "\(name) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 获取设备系列
    /// - Returns: 设备系列
    private func deviceFamily() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            "iPad"
        case .phone:
            "iPhone"
        default:
            "iOS"
        }
    }

    /// 获取模型标识符
    /// - Returns: 模型标识符
    private func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        // 从系统信息中获取机器型号
        let machine = withUnsafeBytes(of: &systemInfo.machine) { ptr in
            String(bytes: ptr.prefix { $0 != 0 }, encoding: .utf8)
        }
        let trimmed = machine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    /// 获取应用版本
    /// - Returns: 应用版本
    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

#if DEBUG
extension GatewayConnectionController {
    /// 测试解析显示名称
    /// - Parameter defaults: 用户默认设置
    /// - Returns: 显示名称
    func _test_resolvedDisplayName(defaults: UserDefaults) -> String {
        self.resolvedDisplayName(defaults: defaults)
    }

    /// 测试获取当前能力
    /// - Returns: 能力列表
    func _test_currentCaps() -> [String] {
        self.currentCaps()
    }

    /// 测试获取当前命令
    /// - Returns: 命令列表
    func _test_currentCommands() -> [String] {
        self.currentCommands()
    }

    /// 测试获取平台字符串
    /// - Returns: 平台字符串
    func _test_platformString() -> String {
        self.platformString()
    }

    /// 测试获取设备系列
    /// - Returns: 设备系列
    func _test_deviceFamily() -> String {
        self.deviceFamily()
    }

    /// 测试获取模型标识符
    /// - Returns: 模型标识符
    func _test_modelIdentifier() -> String {
        self.modelIdentifier()
    }

    /// 测试获取应用版本
    /// - Returns: 应用版本
    func _test_appVersion() -> String {
        self.appVersion()
    }

    /// 测试设置网关列表
    /// - Parameter gateways: 网关列表
    func _test_setGateways(_ gateways: [GatewayDiscoveryModel.DiscoveredGateway]) {
        self.gateways = gateways
    }

    /// 测试触发自动连接
    func _test_triggerAutoConnect() {
        self.maybeAutoConnect()
    }
}
#endif
import MoltbotKit
import Network
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
private final class ConnectStatusStore {
    var text: String?
}

extension ConnectStatusStore: @unchecked Sendable {}

struct SettingsTab: View {
    @Environment(NodeAppModel.self) private var appModel: NodeAppModel
    @Environment(VoiceWakeManager.self) private var voiceWake: VoiceWakeManager
    @Environment(GatewayConnectionController.self) private var gatewayController: GatewayConnectionController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("node.displayName") private var displayName: String = "iOS Node"
    @AppStorage("node.instanceId") private var instanceId: String = UUID().uuidString
    @AppStorage("voiceWake.enabled") private var voiceWakeEnabled: Bool = false
    @AppStorage("talk.enabled") private var talkEnabled: Bool = false
    @AppStorage("talk.button.enabled") private var talkButtonEnabled: Bool = true
    @AppStorage("camera.enabled") private var cameraEnabled: Bool = true
    @AppStorage("location.enabledMode") private var locationEnabledModeRaw: String = MoltbotLocationMode.off.rawValue
    @AppStorage("location.preciseEnabled") private var locationPreciseEnabled: Bool = true
    @AppStorage("screen.preventSleep") private var preventSleep: Bool = true
    @AppStorage("gateway.preferredStableID") private var preferredGatewayStableID: String = ""
    @AppStorage("gateway.lastDiscoveredStableID") private var lastDiscoveredGatewayStableID: String = ""
    @AppStorage("gateway.manual.enabled") private var manualGatewayEnabled: Bool = false
    @AppStorage("gateway.manual.host") private var manualGatewayHost: String = ""
    @AppStorage("gateway.manual.port") private var manualGatewayPort: Int = 18789
    @AppStorage("gateway.manual.tls") private var manualGatewayTLS: Bool = true
    @AppStorage("gateway.discovery.debugLogs") private var discoveryDebugLogsEnabled: Bool = false
    @AppStorage("canvas.debugStatusEnabled") private var canvasDebugStatusEnabled: Bool = false
    @State private var connectStatus = ConnectStatusStore()
    @State private var connectingGatewayID: String?
    @State private var localIPAddress: String?
    @State private var lastLocationModeRaw: String = MoltbotLocationMode.off.rawValue
    @State private var gatewayToken: String = ""
    @State private var gatewayPassword: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("节点") {
                    TextField("名称", text: self.$displayName)
                    Text(self.instanceId)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LabeledContent("IP", value: self.localIPAddress ?? "—")
                        .contextMenu {
                            if let ip = self.localIPAddress {
                                Button {
                                    UIPasteboard.general.string = ip
                                } label: {
                                    Label("复制", systemImage: "doc.on.doc")
                                }
                            }
                        }
                    LabeledContent("平台", value: self.platformString())
                    LabeledContent("版本", value: self.appVersion())
                    LabeledContent("型号", value: self.modelIdentifier())
                }

                Section("网关") {
                    LabeledContent("发现", value: self.gatewayController.discoveryStatusText)
                    LabeledContent("状态", value: self.appModel.gatewayStatusText)
                    if let serverName = self.appModel.gatewayServerName {
                        LabeledContent("服务器", value: serverName)
                        if let addr = self.appModel.gatewayRemoteAddress {
                            let parts = Self.parseHostPort(from: addr)
                            let urlString = Self.httpURLString(host: parts?.host, port: parts?.port, fallback: addr)
                            LabeledContent("地址") {
                                Text(urlString)
                            }
                            .contextMenu {
                                Button {
                                    UIPasteboard.general.string = urlString
                                } label: {
                                    Label("复制 URL", systemImage: "doc.on.doc")
                                }

                                if let parts {
                                    Button {
                                        UIPasteboard.general.string = parts.host
                                    } label: {
                                        Label("复制主机", systemImage: "doc.on.doc")
                                    }

                                    Button {
                                        UIPasteboard.general.string = "\(parts.port)"
                                    } label: {
                                        Label("复制端口", systemImage: "doc.on.doc")
                                    }
                                }
                            }
                        }

                        Button("断开连接", role: .destructive) {
                            self.appModel.disconnectGateway()
                        }

                        self.gatewayList(showing: .availableOnly)
                    } else {
                        self.gatewayList(showing: .all)
                    }

                    if let text = self.connectStatus.text {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("高级") {
                        Toggle("使用手动网关", isOn: self.$manualGatewayEnabled)

                        TextField("主机", text: self.$manualGatewayHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("端口", value: self.$manualGatewayPort, format: .number)
                            .keyboardType(.numberPad)

                        Toggle("使用 TLS", isOn: self.$manualGatewayTLS)

                        Button {
                            Task { await self.connectManual() }
                        } label: {
                            if self.connectingGatewayID == "manual" {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                    Text("连接中…")
                                }
                            } else {
                                Text("连接 (手动)")
                            }
                        }
                        .disabled(self.connectingGatewayID != nil || self.manualGatewayHost
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty || self.manualGatewayPort <= 0 || self.manualGatewayPort > 65535)

                        Text(
                            "当 mDNS/Bonjour 发现被阻止时使用此选项。 "
                                + "网关 WebSocket 默认监听 18789 端口。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Toggle("发现调试日志", isOn: self.$discoveryDebugLogsEnabled)
                            .onChange(of: self.discoveryDebugLogsEnabled) { _, newValue in
                                self.gatewayController.setDiscoveryDebugLoggingEnabled(newValue)
                            }

                        NavigationLink("发现日志") {
                            GatewayDiscoveryDebugLogView()
                        }

                        Toggle("调试画布状态", isOn: self.$canvasDebugStatusEnabled)

                        TextField("网关令牌", text: self.$gatewayToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        SecureField("网关密码", text: self.$gatewayPassword)
                    }
                }

                Section("语音") {
                    Toggle("语音唤醒", isOn: self.$voiceWakeEnabled)
                        .onChange(of: self.voiceWakeEnabled) { _, newValue in
                            self.appModel.setVoiceWakeEnabled(newValue)
                        }
                    Toggle("对话模式", isOn: self.$talkEnabled)
                        .onChange(of: self.talkEnabled) { _, newValue in
                            self.appModel.setTalkEnabled(newValue)
                        }
                    // 保持此选项独立，以便用户可以隐藏侧边气泡而不禁用对话模式。
                    Toggle("显示对话按钮", isOn: self.$talkButtonEnabled)

                    NavigationLink {
                        VoiceWakeWordsSettingsView()
                    } label: {
                        LabeledContent(
                            "唤醒词",
                            value: VoiceWakePreferences.displayString(for: self.voiceWake.triggerWords))
                    }
                }

                Section("相机") {
                    Toggle("允许相机", isOn: self.$cameraEnabled)
                    Text("允许网关请求照片或短视频片段（仅前台）。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("位置") {
                    Picker("位置访问", selection: self.$locationEnabledModeRaw) {
                        Text("关闭").tag(MoltbotLocationMode.off.rawValue)
                        Text("使用时").tag(MoltbotLocationMode.whileUsing.rawValue)
                        Text("始终").tag(MoltbotLocationMode.always.rawValue)
                    }
                    .pickerStyle(.segmented)

                    Toggle("精确位置", isOn: self.$locationPreciseEnabled)
                        .disabled(self.locationMode == .off)

                    Text("始终需要系统权限，可能会提示打开设置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("屏幕") {
                    Toggle("防止睡眠", isOn: self.$preventSleep)
                    Text("在 Moltbot 打开时保持屏幕唤醒。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        self.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .onAppear {
                self.localIPAddress = Self.primaryIPv4Address()
                self.lastLocationModeRaw = self.locationEnabledModeRaw
                let trimmedInstanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedInstanceId.isEmpty {
                    self.gatewayToken = GatewaySettingsStore.loadGatewayToken(instanceId: trimmedInstanceId) ?? ""
                    self.gatewayPassword = GatewaySettingsStore.loadGatewayPassword(instanceId: trimmedInstanceId) ?? ""
                }
            }
            .onChange(of: self.preferredGatewayStableID) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                GatewaySettingsStore.savePreferredGatewayStableID(trimmed)
            }
            .onChange(of: self.gatewayToken) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let instanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instanceId.isEmpty else { return }
                GatewaySettingsStore.saveGatewayToken(trimmed, instanceId: instanceId)
            }
            .onChange(of: self.gatewayPassword) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                let instanceId = self.instanceId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instanceId.isEmpty else { return }
                GatewaySettingsStore.saveGatewayPassword(trimmed, instanceId: instanceId)
            }
            .onChange(of: self.appModel.gatewayServerName) { _, _ in
                self.connectStatus.text = nil
            }
            .onChange(of: self.locationEnabledModeRaw) { _, newValue in
                let previous = self.lastLocationModeRaw
                self.lastLocationModeRaw = newValue
                guard let mode = MoltbotLocationMode(rawValue: newValue) else { return }
                Task {
                    let granted = await self.appModel.requestLocationPermissions(mode: mode)
                    if !granted {
                        await MainActor.run {
                            self.locationEnabledModeRaw = previous
                            self.lastLocationModeRaw = previous
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func gatewayList(showing: GatewayListMode) -> some View {
        if self.gatewayController.gateways.isEmpty {
            Text("尚未发现网关。")
                .foregroundStyle(.secondary)
        } else {
            let connectedID = self.appModel.connectedGatewayID
            let rows = self.gatewayController.gateways.filter { gateway in
                let isConnected = gateway.stableID == connectedID
                switch showing {
                case .all:
                    return true
                case .availableOnly:
                    return !isConnected
                }
            }

            if rows.isEmpty, showing == .availableOnly {
                Text("未发现其他网关。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { gateway in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(gateway.name)
                            let detailLines = self.gatewayDetailLines(gateway)
                            ForEach(detailLines, id: \.self) { line in
                                Text(line)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()

                        Button {
                            Task { await self.connect(gateway) }
                        } label: {
                            if self.connectingGatewayID == gateway.id {
                                ProgressView()
                                    .progressViewStyle(.circular)
                            } else {
                                Text("连接")
                            }
                        }
                        .disabled(self.connectingGatewayID != nil)
                    }
                }
            }
        }
    }

    private enum GatewayListMode: Equatable {
        case all
        case availableOnly
    }

    private func platformString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var locationMode: MoltbotLocationMode {
        MoltbotLocationMode(rawValue: self.locationEnabledModeRaw) ?? .off
    }

    private func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

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

    private func modelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { ptr in
            String(bytes: ptr.prefix { $0 != 0 }, encoding: .utf8)
        }
        let trimmed = machine?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    private func connect(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) async {
        self.connectingGatewayID = gateway.id
        self.manualGatewayEnabled = false
        self.preferredGatewayStableID = gateway.stableID
        GatewaySettingsStore.savePreferredGatewayStableID(gateway.stableID)
        self.lastDiscoveredGatewayStableID = gateway.stableID
        GatewaySettingsStore.saveLastDiscoveredGatewayStableID(gateway.stableID)
        defer { self.connectingGatewayID = nil }

        await self.gatewayController.connect(gateway)
    }

    private func connectManual() async {
        let host = self.manualGatewayHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            self.connectStatus.text = "失败：需要主机"
            return
        }
        guard self.manualGatewayPort > 0, self.manualGatewayPort <= 65535 else {
            self.connectStatus.text = "失败：无效端口"
            return
        }

        self.connectingGatewayID = "manual"
        self.manualGatewayEnabled = true
        defer { self.connectingGatewayID = nil }

        await self.gatewayController.connectManual(
            host: host,
            port: self.manualGatewayPort,
            useTLS: self.manualGatewayTLS)
    }

    private static func primaryIPv4Address() -> String? {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
        defer { freeifaddrs(addrList) }

        var fallback: String?
        var en0: String?

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let name = String(cString: ptr.pointee.ifa_name)
            let family = ptr.pointee.ifa_addr.pointee.sa_family
            if !isUp || isLoopback || family != UInt8(AF_INET) { continue }

            var addr = ptr.pointee.ifa_addr.pointee
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                &addr,
                socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                &buffer,
                socklen_t(buffer.count),
                nil,
                0,
                NI_NUMERICHOST)
            guard result == 0 else { continue }
            let len = buffer.prefix { $0 != 0 }
            let bytes = len.map { UInt8(bitPattern: $0) }
            guard let ip = String(bytes: bytes, encoding: .utf8) else { continue }

            if name == "en0" { en0 = ip; break }
            if fallback == nil { fallback = ip }
        }

        return en0 ?? fallback
    }

    private static func parseHostPort(from address: String) -> SettingsHostPort? {
        SettingsNetworkingHelpers.parseHostPort(from: address)
    }

    private static func httpURLString(host: String?, port: Int?, fallback: String) -> String {
        SettingsNetworkingHelpers.httpURLString(host: host, port: port, fallback: fallback)
    }

    private func gatewayDetailLines(_ gateway: GatewayDiscoveryModel.DiscoveredGateway) -> [String] {
        var lines: [String] = []
        if let lanHost = gateway.lanHost { lines.append("局域网: \(lanHost)") }
        if let tailnet = gateway.tailnetDns { lines.append("Tailnet: \(tailnet)") }

        let gatewayPort = gateway.gatewayPort
        let canvasPort = gateway.canvasPort
        if gatewayPort != nil || canvasPort != nil {
            let gw = gatewayPort.map(String.init) ?? "—"
            let canvas = canvasPort.map(String.init) ?? "—"
            lines.append("端口: 网关 \(gw) · 画布 \(canvas)")
        }

        if lines.isEmpty {
            lines.append(gateway.debugID)
        }

        return lines
    }
}

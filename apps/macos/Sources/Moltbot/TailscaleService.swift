import AppKit
import Foundation
import Observation
import os
#if canImport(Darwin)
import Darwin
#endif

/// 管理 Tailscale 集成和状态检查
@Observable
@MainActor
final class TailscaleService {
    static let shared = TailscaleService()

    /// Tailscale 本地 API 端点
    private static let tailscaleAPIEndpoint = "http://100.100.100.100/api/data"

    /// API 请求超时时间（秒）
    private static let apiTimeoutInterval: TimeInterval = 5.0

    private let logger = Logger(subsystem: "bot.molt", category: "tailscale")

    /// 指示系统上是否安装了 Tailscale 应用
    private(set) var isInstalled = false

    /// 指示 Tailscale 当前是否正在运行
    private(set) var isRunning = false

    /// 此设备的 Tailscale 主机名（例如 "my-mac.tailnet.ts.net"）
    private(set) var tailscaleHostname: String?

    /// 此设备的 Tailscale IPv4 地址
    private(set) var tailscaleIP: String?

    /// 状态检查失败时的错误消息
    private(set) var statusError: String?

    private init() {
        Task { await self.checkTailscaleStatus() }
    }

    #if DEBUG
    init(
        isInstalled: Bool,
        isRunning: Bool,
        tailscaleHostname: String? = nil,
        tailscaleIP: String? = nil,
        statusError: String? = nil)
    {
        self.isInstalled = isInstalled
        self.isRunning = isRunning
        self.tailscaleHostname = tailscaleHostname
        self.tailscaleIP = tailscaleIP
        self.statusError = statusError
    }
    #endif

    /// 检查应用是否已安装
    func checkAppInstallation() -> Bool {
        let installed = FileManager().fileExists(atPath: "/Applications/Tailscale.app")
        self.logger.info("Tailscale app installed: \(installed)")
        return installed
    }

    /// Tailscale API 响应结构
    private struct TailscaleAPIResponse: Codable {
        let status: String
        let deviceName: String
        let tailnetName: String
        let iPv4: String?

        private enum CodingKeys: String, CodingKey {
            case status = "Status"
            case deviceName = "DeviceName"
            case tailnetName = "TailnetName"
            case iPv4 = "IPv4"
        }
    }

    /// 获取 Tailscale 状态
    private func fetchTailscaleStatus() async -> TailscaleAPIResponse? {
        guard let url = URL(string: Self.tailscaleAPIEndpoint) else {
            self.logger.error("Invalid Tailscale API URL")
            return nil
        }

        do {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = Self.apiTimeoutInterval
            let session = URLSession(configuration: configuration)

            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                self.logger.warning("Tailscale API returned non-200 status")
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(TailscaleAPIResponse.self, from: data)
        } catch {
            self.logger.debug("Failed to fetch Tailscale status: \(String(describing: error))")
            return nil
        }
    }

    /// 检查 Tailscale 状态
    func checkTailscaleStatus() async {
        let previousIP = self.tailscaleIP
        self.isInstalled = self.checkAppInstallation()
        if !self.isInstalled {
            self.isRunning = false
            self.tailscaleHostname = nil
            self.tailscaleIP = nil
            self.statusError = "未安装 Tailscale"
        } else if let apiResponse = await fetchTailscaleStatus() {
            self.isRunning = apiResponse.status.lowercased() == "running"

            if self.isRunning {
                let deviceName = apiResponse.deviceName
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "-")
                let tailnetName = apiResponse.tailnetName
                    .replacingOccurrences(of: ".ts.net", with: "")
                    .replacingOccurrences(of: ".tailscale.net", with: "")

                self.tailscaleHostname = "\(deviceName).\(tailnetName).ts.net"
                self.tailscaleIP = apiResponse.iPv4
                self.statusError = nil

                self.logger.info(
                    "Tailscale running host=\(self.tailscaleHostname ?? "nil") ip=\(self.tailscaleIP ?? "nil")")
            } else {
                self.tailscaleHostname = nil
                self.tailscaleIP = nil
                self.statusError = "Tailscale 未运行"
            }
        } else {
            self.isRunning = false
            self.tailscaleHostname = nil
            self.tailscaleIP = nil
            self.statusError = "请启动 Tailscale 应用"
            self.logger.info("Tailscale API not responding; app likely not running")
        }

        if self.tailscaleIP == nil, let fallback = Self.detectTailnetIPv4() {
            self.tailscaleIP = fallback
            if !self.isRunning {
                self.isRunning = true
            }
            self.statusError = nil
            self.logger.info("Tailscale interface IP detected (fallback) ip=\(fallback, privacy: .public)")
        }

        if previousIP != self.tailscaleIP {
            await GatewayEndpointStore.shared.refresh()
        }
    }

    /// 打开 Tailscale 应用
    func openTailscaleApp() {
        if let url = URL(string: "file:///Applications/Tailscale.app") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开 App Store
    func openAppStore() {
        if let url = URL(string: "https://apps.apple.com/us/app/tailscale/id1475387142") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开下载页面
    func openDownloadPage() {
        if let url = URL(string: "https://tailscale.com/download/macos") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 打开设置指南
    func openSetupGuide() {
        if let url = URL(string: "https://tailscale.com/kb/1017/install/") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 检查是否为 Tailnet IPv4 地址
    private nonisolated static func isTailnetIPv4(_ address: String) -> Bool {
        let parts = address.split(separator: ".")
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        let a = octets[0]
        let b = octets[1]
        return a == 100 && b >= 64 && b <= 127
    }

    /// 检测 Tailnet IPv4 地址
    private nonisolated static func detectTailnetIPv4() -> String? {
        var addrList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrList) == 0, let first = addrList else { return nil }
        defer { freeifaddrs(addrList) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
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
            if Self.isTailnetIPv4(ip) { return ip }
        }

        return nil
    }

    /// 备用 Tailnet IPv4 地址
    nonisolated static func fallbackTailnetIPv4() -> String? {
        self.detectTailnetIPv4()
    }
}

import Cocoa
import Darwin
import Foundation
import OSLog

/// 在线状态报告器
/// 定期向控制通道发送在线状态信息
@MainActor
final class PresenceReporter {
    static let shared = PresenceReporter()

    private let logger = Logger(subsystem: "bot.molt", category: "presence")
    private var task: Task<Void, Never>?
    private let interval: TimeInterval = 180 // 几分钟
    private let instanceId: String = InstanceIdentity.instanceId

    /// 启动在线状态报告
    func start() {
        guard self.task == nil else { return }
        self.task = Task.detached { [weak self] in
            guard let self else { return }
            await self.push(reason: "launch")
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                await self.push(reason: "periodic")
            }
        }
    }

    /// 停止在线状态报告
    func stop() {
        self.task?.cancel()
        self.task = nil
    }

    /// 推送在线状态
    @Sendable
    private func push(reason: String) async {
        let mode = await MainActor.run { AppStateStore.shared.connectionMode.rawValue }
        let host = InstanceIdentity.displayName
        let ip = Self.primaryIPv4Address() ?? "ip-unknown"
        let version = Self.appVersionString()
        let platform = Self.platformString()
        let lastInput = Self.lastInputSeconds()
        let text = Self.composePresenceSummary(mode: mode, reason: reason)
        var params: [String: AnyHashable] = [
            "instanceId": AnyHashable(self.instanceId),
            "host": AnyHashable(host),
            "ip": AnyHashable(ip),
            "mode": AnyHashable(mode),
            "version": AnyHashable(version),
            "platform": AnyHashable(platform),
            "deviceFamily": AnyHashable("Mac"),
            "reason": AnyHashable(reason),
        ]
        if let model = InstanceIdentity.modelIdentifier { params["modelIdentifier"] = AnyHashable(model) }
        if let lastInput { params["lastInputSeconds"] = AnyHashable(lastInput) }
        do {
            try await ControlChannel.shared.sendSystemEvent(text, params: params)
        } catch {
            self.logger.error("presence send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 立即发送在线状态信标(例如,连接后立即发送)
    func sendImmediate(reason: String = "connect") {
        Task { await self.push(reason: reason) }
    }

    /// 组合在线状态摘要
    private static func composePresenceSummary(mode: String, reason: String) -> String {
        let host = InstanceIdentity.displayName
        let ip = Self.primaryIPv4Address() ?? "ip-unknown"
        let version = Self.appVersionString()
        let lastInput = Self.lastInputSeconds()
        let lastLabel = lastInput.map { "last input \($0)s ago" } ?? "last input unknown"
        return "Node: \(host) (\(ip)) · app \(version) · \(lastLabel) · mode \(mode) · reason \(reason)"
    }

    /// 获取应用版本字符串
    private static func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            let trimmed = build.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != version {
                return "\(version) (\(trimmed))"
            }
        }
        return version
    }

    /// 获取平台字符串
    private static func platformString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macos \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 获取最后输入时间(秒)
    private static func lastInputSeconds() -> Int? {
        let anyEvent = CGEventType(rawValue: UInt32.max) ?? .null
        let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
        if seconds.isNaN || seconds.isInfinite || seconds < 0 { return nil }
        return Int(seconds.rounded())
    }

    /// 获取主IPv4地址
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
}

#if DEBUG
extension PresenceReporter {
    /// 测试组合在线状态摘要
    static func _testComposePresenceSummary(mode: String, reason: String) -> String {
        self.composePresenceSummary(mode: mode, reason: reason)
    }

    /// 测试获取应用版本字符串
    static func _testAppVersionString() -> String {
        self.appVersionString()
    }

    /// 测试获取平台字符串
    static func _testPlatformString() -> String {
        self.platformString()
    }

    /// 测试获取最后输入时间
    static func _testLastInputSeconds() -> Int? {
        self.lastInputSeconds()
    }

    /// 测试获取主IPv4地址
    static func _testPrimaryIPv4Address() -> String? {
        self.primaryIPv4Address()
    }
}
#endif

import MoltbotKit
import CoreLocation
import Foundation

/// 位置服务类，用于管理位置授权和获取位置信息
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// 位置服务错误类型
    enum Error: Swift.Error {
        /// 超时错误
        case timeout
        /// 位置不可用错误
        case unavailable
    }

    /// 位置管理器实例
    private let manager = CLLocationManager()
    /// 授权状态续体
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    /// 位置续体
    private var locationContinuation: CheckedContinuation<CLLocation, Swift.Error>?

    /// 初始化方法
    override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// 获取当前授权状态
    /// - Returns: 当前的位置授权状态
    func authorizationStatus() -> CLAuthorizationStatus {
        self.manager.authorizationStatus
    }

    /// 获取精度授权状态
    /// - Returns: 当前的精度授权状态
    func accuracyAuthorization() -> CLAccuracyAuthorization {
        if #available(iOS 14.0, *) {
            return self.manager.accuracyAuthorization
        }
        return .fullAccuracy
    }

    /// 确保位置授权
    /// - Parameter mode: 位置模式
    /// - Returns: 更新后的授权状态
    func ensureAuthorization(mode: MoltbotLocationMode) async -> CLAuthorizationStatus {
        // 检查位置服务是否启用
        guard CLLocationManager.locationServicesEnabled() else { return .denied }

        let status = self.manager.authorizationStatus
        if status == .notDetermined {
            // 请求使用时授权
            self.manager.requestWhenInUseAuthorization()
            let updated = await self.awaitAuthorizationChange()
            if mode != .always { return updated }
        }

        if mode == .always {
            let current = self.manager.authorizationStatus
            if current == .authorizedWhenInUse {
                // 请求始终授权
                self.manager.requestAlwaysAuthorization()
                return await self.awaitAuthorizationChange()
            }
            return current
        }

        return self.manager.authorizationStatus
    }

    /// 获取当前位置
    /// - Parameters:
    ///   - params: 位置获取参数
    ///   - desiredAccuracy: 期望的位置精度
    ///   - maxAgeMs: 缓存位置的最大年龄（毫秒）
    ///   - timeoutMs: 超时时间（毫秒）
    /// - Returns: 当前位置
    /// - Throws: 位置获取错误
    func currentLocation(
        params: MoltbotLocationGetParams,
        desiredAccuracy: MoltbotLocationAccuracy,
        maxAgeMs: Int?,
        timeoutMs: Int?) async throws -> CLLocation
    {
        let now = Date()
        // 检查是否有有效的缓存位置
        if let maxAgeMs,
           let cached = self.manager.location,
           now.timeIntervalSince(cached.timestamp) * 1000 <= Double(maxAgeMs)
        {
            return cached
        }

        // 设置期望的精度
        self.manager.desiredAccuracy = Self.accuracyValue(desiredAccuracy)
        let timeout = max(0, timeoutMs ?? 10000)
        // 带超时的位置请求
        return try await self.withTimeout(timeoutMs: timeout) {
            try await self.requestLocation()
        }
    }

    /// 请求位置信息
    /// - Returns: 获取到的位置
    /// - Throws: 位置获取错误
    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { cont in
            self.locationContinuation = cont
            self.manager.requestLocation()
        }
    }

    /// 等待授权状态变更
    /// - Returns: 更新后的授权状态
    private func awaitAuthorizationChange() async -> CLAuthorizationStatus {
        await withCheckedContinuation { cont in
            self.authContinuation = cont
        }
    }

    /// 带超时的异步操作
    /// - Parameters:
    ///   - timeoutMs: 超时时间（毫秒）
    ///   - operation: 要执行的异步操作
    /// - Returns: 操作结果
    /// - Throws: 操作错误或超时错误
    private func withTimeout<T: Sendable>(
        timeoutMs: Int,
        operation: @escaping @Sendable () async throws -> T) async throws -> T
    {
        try await AsyncTimeout.withTimeoutMs(timeoutMs: timeoutMs, onTimeout: { Error.timeout }, operation: operation)
    }

    /// 将Moltbot位置精度转换为Core Location精度
    /// - Parameter accuracy: Moltbot位置精度
    /// - Returns: 对应的Core Location精度
    private static func accuracyValue(_ accuracy: MoltbotLocationAccuracy) -> CLLocationAccuracy {
        switch accuracy {
        case .coarse:
            kCLLocationAccuracyKilometer
        case .balanced:
            kCLLocationAccuracyHundredMeters
        case .precise:
            kCLLocationAccuracyBest
        }
    }

    /// 位置管理器授权状态变更回调
    /// - Parameter manager: 位置管理器
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if let cont = self.authContinuation {
                self.authContinuation = nil
                cont.resume(returning: status)
            }
        }
    }

    /// 位置管理器更新位置回调
    /// - Parameters:
    ///   - manager: 位置管理器
    ///   - locations: 位置数组
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let locs = locations
        Task { @MainActor in
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            if let latest = locs.last {
                cont.resume(returning: latest)
            } else {
                cont.resume(throwing: Error.unavailable)
            }
        }
    }

    /// 位置管理器错误回调
    /// - Parameters:
    ///   - manager: 位置管理器
    ///   - error: 错误信息
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Swift.Error) {
        let err = error
        Task { @MainActor in
            guard let cont = self.locationContinuation else { return }
            self.locationContinuation = nil
            cont.resume(throwing: err)
        }
    }
}

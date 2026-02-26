import Foundation

/// 异步操作超时处理工具
/// 
/// 提供了两个静态方法，用于在异步操作中添加超时功能，当操作超过指定时间时会抛出超时错误
public enum AsyncTimeout {
    /// 执行异步操作并设置超时时间（秒）
    /// 
    /// - Parameters:
    ///   - seconds: 超时时间，单位为秒
    ///   - onTimeout: 超时时执行的闭包，返回一个Error
    ///   - operation: 要执行的异步操作闭包，返回类型为T
    /// - Returns: 异步操作的结果，类型为T
    /// - Throws: 如果操作超时或操作本身抛出错误，则抛出相应的错误
    public static func withTimeout<T: Sendable>(
        seconds: Double,
        onTimeout: @escaping @Sendable () -> Error,
        operation: @escaping @Sendable () async throws -> T) async throws -> T
    {
        // 确保超时时间不为负数
        let clamped = max(0, seconds)
        // 如果超时时间为0，则直接执行操作，不设置超时
        if clamped == 0 {
            return try await operation()
        }

        // 使用任务组实现超时功能
        return try await withThrowingTaskGroup(of: T.self) { group in
            // 添加执行操作的任务
            group.addTask { try await operation() }
            // 添加超时任务
            group.addTask {
                // 等待指定的时间
                try await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
                // 超时后抛出错误
                throw onTimeout()
            }
            // 获取第一个完成的任务结果
            let result = try await group.next()
            // 取消所有任务
            group.cancelAll()
            // 如果有结果，则返回
            if let result { return result }
            // 如果没有结果（可能是因为所有任务都被取消），则抛出超时错误
            throw onTimeout()
        }
    }

    /// 执行异步操作并设置超时时间（毫秒）
    /// 
    /// - Parameters:
    ///   - timeoutMs: 超时时间，单位为毫秒
    ///   - onTimeout: 超时时执行的闭包，返回一个Error
    ///   - operation: 要执行的异步操作闭包，返回类型为T
    /// - Returns: 异步操作的结果，类型为T
    /// - Throws: 如果操作超时或操作本身抛出错误，则抛出相应的错误
    public static func withTimeoutMs<T: Sendable>(
        timeoutMs: Int,
        onTimeout: @escaping @Sendable () -> Error,
        operation: @escaping @Sendable () async throws -> T) async throws -> T
    {
        // 确保超时时间不为负数
        let clamped = max(0, timeoutMs)
        // 将毫秒转换为秒
        let seconds = Double(clamped) / 1000.0
        // 调用withTimeout方法
        return try await self.withTimeout(seconds: seconds, onTimeout: onTimeout, operation: operation)
    }
}

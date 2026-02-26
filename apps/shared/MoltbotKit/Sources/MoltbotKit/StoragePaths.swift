import Foundation

/// Moltbot 节点存储路径管理枚举
/// 
/// 此枚举提供了获取 Moltbot 应用各种存储路径的静态方法，
/// 包括应用支持目录、画布根目录、缓存目录和画布快照根目录。
public enum MoltbotNodeStorage {
    /// 获取应用支持目录路径
    /// 
    /// - Returns: 指向 Moltbot 应用支持目录的 URL
    /// - Throws: 当应用支持目录不可用时抛出错误
    public static func appSupportDir() throws -> URL {
        // 获取系统应用支持目录路径
        let base = FileManager().urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else {
            // 如果无法获取应用支持目录，抛出错误
            throw NSError(domain: "MoltbotNodeStorage", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "应用支持目录不可用",
            ])
        }
        // 返回指向 Moltbot 子目录的 URL
        return base.appendingPathComponent("Moltbot", isDirectory: true)
    }

    /// 获取画布根目录路径
    /// 
    /// - Parameter sessionKey: 会话密钥，用于标识不同的画布会话
    /// - Returns: 指向指定会话画布根目录的 URL
    /// - Throws: 当应用支持目录不可用时抛出错误
    public static func canvasRoot(sessionKey: String) throws -> URL {
        // 首先获取应用支持目录，然后添加 canvas 子目录
        let root = try appSupportDir().appendingPathComponent("canvas", isDirectory: true)
        // 清理会话密钥中的空白字符
        let safe = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果会话密钥为空，使用 "main" 作为默认值
        let session = safe.isEmpty ? "main" : safe
        // 返回指向会话子目录的 URL
        return root.appendingPathComponent(session, isDirectory: true)
    }

    /// 获取缓存目录路径
    /// 
    /// - Returns: 指向 Moltbot 缓存目录的 URL
    /// - Throws: 当缓存目录不可用时抛出错误
    public static func cachesDir() throws -> URL {
        // 获取系统缓存目录路径
        let base = FileManager().urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let base else {
            // 如果无法获取缓存目录，抛出错误
            throw NSError(domain: "MoltbotNodeStorage", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "缓存目录不可用",
            ])
        }
        // 返回指向 Moltbot 子目录的 URL
        return base.appendingPathComponent("Moltbot", isDirectory: true)
    }

    /// 获取画布快照根目录路径
    /// 
    /// - Parameter sessionKey: 会话密钥，用于标识不同的画布会话
    /// - Returns: 指向指定会话画布快照根目录的 URL
    /// - Throws: 当缓存目录不可用时抛出错误
    public static func canvasSnapshotsRoot(sessionKey: String) throws -> URL {
        // 首先获取缓存目录，然后添加 canvas-snapshots 子目录
        let root = try cachesDir().appendingPathComponent("canvas-snapshots", isDirectory: true)
        // 清理会话密钥中的空白字符
        let safe = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果会话密钥为空，使用 "main" 作为默认值
        let session = safe.isEmpty ? "main" : safe
        // 返回指向会话子目录的 URL
        return root.appendingPathComponent(session, isDirectory: true)
    }
}

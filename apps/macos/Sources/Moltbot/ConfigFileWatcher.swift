import CoreServices
import Foundation

/// 配置文件监视器
/// 
/// 用于监视指定配置文件的变化，并在文件发生变化时触发回调
final class ConfigFileWatcher: @unchecked Sendable {
    /// 要监视的文件URL
    private let url: URL
    /// 用于处理文件系统事件的队列
    private let queue: DispatchQueue
    /// 文件系统事件流引用
    private var stream: FSEventStreamRef?
    /// 标记是否有未处理的事件
    private var pending = false
    /// 文件变化时的回调闭包
    private let onChange: () -> Void
    /// 被监视的目录
    private let watchedDir: URL
    /// 目标文件路径
    private let targetPath: String
    /// 目标文件名
    private let targetName: String

    /// 初始化配置文件监视器
    /// - Parameters:
    ///   - url: 要监视的文件URL
    ///   - onChange: 文件变化时的回调闭包
    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = DispatchQueue(label: "bot.molt.configwatcher")
        self.onChange = onChange
        self.watchedDir = url.deletingLastPathComponent()
        self.targetPath = url.path
        self.targetName = url.lastPathComponent
    }

    /// 析构函数，停止监视
    deinit {
        self.stop()
    }

    /// 开始监视文件变化
    func start() {
        // 如果已经有流存在，直接返回
        guard self.stream == nil else { return }

        // 保留自身引用
        let retainedSelf = Unmanaged.passRetained(self)
        // 创建事件流上下文
        var context = FSEventStreamContext(
            version: 0,
            info: retainedSelf.toOpaque(),
            retain: nil,
            release: { pointer in
                guard let pointer else { return }
                Unmanaged<ConfigFileWatcher>.fromOpaque(pointer).release()
            },
            copyDescription: nil)

        // 要监视的路径数组
        let paths = [self.watchedDir.path] as CFArray
        // 事件流创建标志
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer)

        // 创建事件流
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.05,
            flags)
        else {
            retainedSelf.release()
            return
        }

        // 保存流引用并设置调度队列
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, self.queue)
        // 启动事件流
        if FSEventStreamStart(stream) == false {
            self.stream = nil
            FSEventStreamSetDispatchQueue(stream, nil)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// 停止监视文件变化
    func stop() {
        guard let stream = self.stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

extension ConfigFileWatcher {
    /// 事件流回调函数
    private static let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<ConfigFileWatcher>.fromOpaque(info).takeUnretainedValue()
        watcher.handleEvents(
            numEvents: numEvents,
            eventPaths: eventPaths,
            eventFlags: eventFlags)
    }

    /// 处理文件系统事件
    /// - Parameters:
    ///   - numEvents: 事件数量
    ///   - eventPaths: 事件路径
    ///   - eventFlags: 事件标志
    private func handleEvents(
        numEvents: Int,
        eventPaths: UnsafeMutableRawPointer?,
        eventFlags: UnsafePointer<FSEventStreamEventFlags>?
    ) {
        // 检查事件数量
        guard numEvents > 0 else { return }
        // 检查事件标志
        guard eventFlags != nil else { return }
        // 检查是否匹配目标文件
        guard self.matchesTarget(eventPaths: eventPaths) else { return }

        // 如果已经有未处理的事件，直接返回
        if self.pending { return }
        self.pending = true
        // 延迟执行回调，避免频繁触发
        self.queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.pending = false
            self.onChange()
        }
    }

    /// 检查事件路径是否匹配目标文件
    /// - Parameter eventPaths: 事件路径
    /// - Returns: 是否匹配
    private func matchesTarget(eventPaths: UnsafeMutableRawPointer?) -> Bool {
        guard let eventPaths else { return true }
        let paths = unsafeBitCast(eventPaths, to: NSArray.self)
        for case let path as String in paths {
            // 检查是否与目标路径完全匹配
            if path == self.targetPath { return true }
            // 检查是否以目标文件名结尾
            if path.hasSuffix("/\(self.targetName)") { return true }
            // 检查是否与监视目录匹配
            if path == self.watchedDir.path { return true }
        }
        return false
    }
}

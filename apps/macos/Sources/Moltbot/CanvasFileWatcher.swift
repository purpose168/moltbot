import CoreServices
import Foundation

/// 文件系统监视器类，用于监控指定URL路径的文件变化
/// 实现了 @unchecked Sendable 协议，允许在并发环境中安全使用
final class CanvasFileWatcher: @unchecked Sendable {
    /// 要监控的文件URL路径
    private let url: URL
    /// 用于处理文件系统事件的调度队列
    private let queue: DispatchQueue
    /// 文件系统事件流引用
    private var stream: FSEventStreamRef?
    /// 标记是否有挂起的事件处理
    private var pending = false
    /// 文件变化时的回调闭包
    private let onChange: () -> Void

    /// 初始化文件监视器
    /// - Parameters:
    ///   - url: 要监控的文件URL路径
    ///   - onChange: 文件变化时的回调闭包
    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = DispatchQueue(label: "bot.molt.canvaswatcher")
        self.onChange = onChange
    }

    /// 析构函数，在对象销毁时停止监控
    deinit {
        self.stop()
    }

    /// 开始监控文件变化
    func start() {
        // 如果已经有事件流存在，则直接返回
        guard self.stream == nil else { return }

        // 保存self的引用，用于回调中使用
        let retainedSelf = Unmanaged.passRetained(self)
        // 创建FSEventStream上下文
        var context = FSEventStreamContext(
            version: 0,
            info: retainedSelf.toOpaque(),
            retain: nil,
            release: { pointer in
                guard let pointer else { return }
                // 释放self的引用
                Unmanaged<CanvasFileWatcher>.fromOpaque(pointer).release()
            },
            copyDescription: nil)

        // 要监控的路径数组
        let paths = [self.url.path] as CFArray
        // 创建事件流的标志
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents |  // 监控文件级别的事件
                kFSEventStreamCreateFlagUseCFTypes |  // 使用CF类型
                kFSEventStreamCreateFlagNoDefer)  // 不延迟事件通知

        // 创建事件流
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),  // 从现在开始监控
            0.05,  // 事件检查间隔（秒）
            flags)
        else {
            // 创建失败时释放self的引用
            retainedSelf.release()
            return
        }

        // 保存事件流引用
        self.stream = stream
        // 设置事件流的调度队列
        FSEventStreamSetDispatchQueue(stream, self.queue)
        // 启动事件流
        if FSEventStreamStart(stream) == false {
            // 启动失败时清理资源
            self.stream = nil
            FSEventStreamSetDispatchQueue(stream, nil)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// 停止监控文件变化
    func stop() {
        // 如果没有事件流存在，则直接返回
        guard let stream = self.stream else { return }
        // 清空事件流引用
        self.stream = nil
        // 停止事件流
        FSEventStreamStop(stream)
        // 移除事件流的调度队列
        FSEventStreamSetDispatchQueue(stream, nil)
        // 使事件流无效
        FSEventStreamInvalidate(stream)
        // 释放事件流
        FSEventStreamRelease(stream)
    }
}

extension CanvasFileWatcher {
    /// 文件系统事件回调函数
    private static let callback: FSEventStreamCallback = { _, info, numEvents, _, eventFlags, _ in
        guard let info else { return }
        // 从指针中获取CanvasFileWatcher实例
        let watcher = Unmanaged<CanvasFileWatcher>.fromOpaque(info).takeUnretainedValue()
        // 处理事件
        watcher.handleEvents(numEvents: numEvents, eventFlags: eventFlags)
    }

    /// 处理文件系统事件
    /// - Parameters:
    ///   - numEvents: 事件数量
    ///   - eventFlags: 事件标志指针
    private func handleEvents(numEvents: Int, eventFlags: UnsafePointer<FSEventStreamEventFlags>?) {
        // 确保有事件且事件标志不为nil
        guard numEvents > 0 else { return }
        guard eventFlags != nil else { return }

        // 合并快速连续的变化（在构建/原子保存期间常见）
        if self.pending { return }
        self.pending = true
        // 延迟执行回调，以合并快速连续的变化
        self.queue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.pending = false
            // 调用文件变化回调
            self.onChange()
        }
    }
}

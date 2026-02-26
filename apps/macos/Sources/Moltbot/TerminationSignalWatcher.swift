import AppKit
import Foundation
import OSLog

/// 终止信号监视器
/// 监听系统终止信号并优雅地关闭应用
@MainActor
final class TerminationSignalWatcher {
    static let shared = TerminationSignalWatcher()

    private let logger = Logger(subsystem: "bot.molt", category: "lifecycle")
    private var sources: [DispatchSourceSignal] = []
    private var terminationRequested = false

    /// 启动监视
    func start() {
        guard self.sources.isEmpty else { return }
        self.install(SIGTERM)
        self.install(SIGINT)
    }

    /// 停止监视
    func stop() {
        for s in self.sources {
            s.cancel()
        }
        self.sources.removeAll(keepingCapacity: false)
        self.terminationRequested = false
    }

    /// 安装信号处理器
    private func install(_ sig: Int32) {
        // 确保默认操作不会在我们优雅关闭之前杀死进程
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { [weak self] in
            self?.handle(sig)
        }
        source.resume()
        self.sources.append(source)
    }

    /// 处理信号
    private func handle(_ sig: Int32) {
        guard !self.terminationRequested else { return }
        self.terminationRequested = true

        self.logger.info("received signal \(sig, privacy: .public); terminating")
        // 确保在关闭期间不会意外批准任何配对提示
        NodePairingApprovalPrompter.shared.stop()
        DevicePairingApprovalPrompter.shared.stop()
        NSApp.terminate(nil)

        // 安全网:如果某些操作阻止了终止,不要永远挂起
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            exit(0)
        }
    }
}

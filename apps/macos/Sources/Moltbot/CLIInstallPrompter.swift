import AppKit
import Foundation
import OSLog

/// CLI安装提示器，用于检查并提示用户安装Moltbot CLI工具
@MainActor
final class CLIInstallPrompter {
    /// 单例实例
    static let shared = CLIInstallPrompter()
    /// 日志记录器
    private let logger = Logger(subsystem: "bot.molt", category: "cli.prompt")
    /// 是否正在提示中
    private var isPrompting = false

    /// 检查并在需要时提示用户安装CLI
    /// - Parameter reason: 提示原因
    func checkAndPromptIfNeeded(reason: String) {
        // 检查是否应该提示
        guard self.shouldPrompt() else { return }
        // 获取应用版本
        guard let version = Self.appVersion() else { return }
        // 标记为正在提示
        self.isPrompting = true
        // 保存提示的版本号
        UserDefaults.standard.set(version, forKey: cliInstallPromptedVersionKey)

        // 创建提示对话框
        let alert = NSAlert()
        alert.messageText = "安装 Moltbot CLI？"
        alert.informativeText = "本地模式需要 CLI，以便 launchd 可以运行网关。"
        alert.addButton(withTitle: "安装 CLI")
        alert.addButton(withTitle: "暂不")
        alert.addButton(withTitle: "打开设置")
        // 运行对话框并获取响应
        let response = alert.runModal()

        // 处理用户响应
        switch response {
        case .alertFirstButtonReturn: // 安装 CLI
            Task { await self.installCLI() }
        case .alertThirdButtonReturn: // 打开设置
            self.openSettings(tab: .general)
        default: // 暂不安装
            break
        }

        // 记录日志并标记提示完成
        self.logger.debug("cli install prompt handled reason=\(reason, privacy: .public)")
        self.isPrompting = false
    }

    /// 检查是否应该提示用户安装CLI
    /// - Returns: 是否应该提示
    private func shouldPrompt() -> Bool {
        // 检查是否正在提示中
        guard !self.isPrompting else { return false }
        // 检查是否已完成引导
        guard AppStateStore.shared.onboardingSeen else { return false }
        // 检查是否为本地连接模式
        guard AppStateStore.shared.connectionMode == .local else { return false }
        // 检查CLI是否已安装
        guard CLIInstaller.installedLocation() == nil else { return false }
        // 检查应用版本
        guard let version = Self.appVersion() else { return false }
        // 检查上次提示的版本
        let lastPrompt = UserDefaults.standard.string(forKey: cliInstallPromptedVersionKey)
        // 只有当版本不同时才提示
        return lastPrompt != version
    }

    /// 安装CLI
    private func installCLI() async {
        // 创建状态盒子用于接收安装状态
        let status = StatusBox()
        // 执行CLI安装
        await CLIInstaller.install { message in
            await status.set(message)
        }
        // 安装完成后显示结果
        if let message = await status.get() {
            let alert = NSAlert()
            alert.messageText = "CLI 安装完成"
            alert.informativeText = message
            alert.runModal()
        }
    }

    /// 打开设置窗口
    /// - Parameter tab: 要打开的设置标签页
    private func openSettings(tab: SettingsTab) {
        // 请求打开指定标签页
        SettingsTabRouter.request(tab)
        // 打开设置窗口
        SettingsWindowOpener.shared.open()
        // 在主队列中发送通知，选择设置标签页
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .moltbotSelectSettingsTab, object: tab)
        }
    }

    /// 获取应用版本号
    /// - Returns: 应用版本号
    private static func appVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

/// 状态盒子，用于在异步任务中传递状态信息
private actor StatusBox {
    /// 存储的值
    private var value: String?

    /// 设置值
    /// - Parameter value: 要设置的值
    func set(_ value: String) {
        self.value = value
    }

    /// 获取值
    /// - Returns: 存储的值
    func get() -> String? {
        self.value
    }
}

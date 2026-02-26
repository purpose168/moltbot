import Foundation

/// 启动代理管理器
/// 管理macOS launchd代理的启动和停止
enum LaunchAgentManager {
    private static let legacyLaunchdLabels = [
        "com.steipete.clawdbot",
        "com.clawdbot.mac",
    ]
    private static var plistURL: URL {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/bot.molt.mac.plist")
    }

    private static var legacyPlistURLs: [URL] {
        self.legacyLaunchdLabels.map { label in
            FileManager().homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(label).plist")
        }
    }

    /// 获取状态
    static func status() async -> Bool {
        guard FileManager().fileExists(atPath: self.plistURL.path) else { return false }
        let result = await self.runLaunchctl(["print", "gui/\(getuid())/\(launchdLabel)"])
        return result == 0
    }

    /// 设置启用状态
    /// - Parameters:
    ///   - enabled: 是否启用
    ///   - bundlePath: 应用程序包路径
    static func set(enabled: Bool, bundlePath: String) async {
        if enabled {
            for legacyLabel in self.legacyLaunchdLabels {
                _ = await self.runLaunchctl(["bootout", "gui/\(getuid())/\(legacyLabel)"])
            }
            for legacyURL in self.legacyPlistURLs {
                try? FileManager().removeItem(at: legacyURL)
            }
            self.writePlist(bundlePath: bundlePath)
            _ = await self.runLaunchctl(["bootout", "gui/\(getuid())/\(launchdLabel)"])
            _ = await self.runLaunchctl(["bootstrap", "gui/\(getuid())", self.plistURL.path])
            _ = await self.runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(launchdLabel)"])
        } else {
            // 禁用自动启动,但保持当前应用运行
            // bootout会立即终止launchd任务(如果通过代理启动会导致应用崩溃)
            try? FileManager().removeItem(at: self.plistURL)
        }
    }

    /// 写入plist文件
    private static func writePlist(bundlePath: String) {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>bot.molt.mac</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(bundlePath)/Contents/MacOS/Moltbot</string>
          </array>
          <key>WorkingDirectory</key>
          <string>\(FileManager().homeDirectoryForCurrentUser.path)</string>
          <key>RunAtLoad</key>
          <true/>
          <key>KeepAlive</key>
          <true/>
          <key>EnvironmentVariables</key>
          <dict>
            <key>PATH</key>
            <string>\(CommandResolver.preferredPaths().joined(separator: ":"))</string>
          </dict>
          <key>StandardOutPath</key>
          <string>\(LogLocator.launchdLogPath)</string>
          <key>StandardErrorPath</key>
          <string>\(LogLocator.launchdLogPath)</string>
        </dict>
        </plist>
        """
        try? plist.write(to: self.plistURL, atomically: true, encoding: .utf8)
    }

    /// 运行launchctl命令
    @discardableResult
    private static func runLaunchctl(_ args: [String]) async -> Int32 {
        await Task.detached(priority: .utility) { () -> Int32 in
            let process = Process()
            process.launchPath = "/bin/launchctl"
            process.arguments = args
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                _ = try process.runAndReadToEnd(from: pipe)
                return process.terminationStatus
            } catch {
                return -1
            }
        }.value
    }
}

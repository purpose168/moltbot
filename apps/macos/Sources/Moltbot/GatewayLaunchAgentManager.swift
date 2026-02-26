import Foundation

/// 网关启动代理管理器
/// 管理网关守护进程的启动代理
enum GatewayLaunchAgentManager {
    private static let logger = Logger(subsystem: "bot.molt", category: "gateway.launchd")
    private static let disableLaunchAgentMarker = ".clawdbot/disable-launchagent"

    private static var disableLaunchAgentMarkerURL: URL {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(self.disableLaunchAgentMarker)
    }

    private static var plistURL: URL {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(gatewayLaunchdLabel).plist")
    }

    /// 检查启动代理写入是否被禁用
    static func isLaunchAgentWriteDisabled() -> Bool {
        FileManager().fileExists(atPath: self.disableLaunchAgentMarkerURL.path)
    }

    /// 设置启动代理写入禁用状态
    /// - Parameter disabled: 是否禁用
    /// - Returns: 错误消息(如果有)
    static func setLaunchAgentWriteDisabled(_ disabled: Bool) -> String? {
        let marker = self.disableLaunchAgentMarkerURL
        if disabled {
            do {
                try FileManager().createDirectory(
                    at: marker.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if !FileManager().fileExists(atPath: marker.path) {
                    FileManager().createFile(atPath: marker.path, contents: nil)
                }
            } catch {
                return error.localizedDescription
            }
            return nil
        }

        if FileManager().fileExists(atPath: marker.path) {
            do {
                try FileManager().removeItem(at: marker)
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    /// 检查是否已加载
    static func isLoaded() async -> Bool {
        guard let loaded = await self.readDaemonLoaded() else { return false }
        return loaded
    }

    /// 设置启用状态
    /// - Parameters:
    ///   - enabled: 是否启用
    ///   - bundlePath: 应用程序包路径
    ///   - port: 端口号
    /// - Returns: 错误消息(如果有)
    static func set(enabled: Bool, bundlePath: String, port: Int) async -> String? {
        _ = bundlePath
        guard !CommandResolver.connectionModeIsRemote() else {
            self.logger.info("launchd change skipped (remote mode)")
            return nil
        }
        if enabled, self.isLaunchAgentWriteDisabled() {
            self.logger.info("launchd enable skipped (disable marker set)")
            return nil
        }

        if enabled {
            self.logger.info("launchd enable requested via CLI port=\(port)")
            return await self.runDaemonCommand([
                "install",
                "--force",
                "--port",
                "\(port)",
                "--runtime",
                "node",
            ])
        }

        self.logger.info("launchd disable requested via CLI")
        return await self.runDaemonCommand(["uninstall"])
    }

    /// 重启
    static func kickstart() async {
        _ = await self.runDaemonCommand(["restart"], timeout: 20)
    }

    /// 获取launchd配置快照
    static func launchdConfigSnapshot() -> LaunchAgentPlistSnapshot? {
        LaunchAgentPlist.snapshot(url: self.plistURL)
    }

    /// 获取launchd网关日志路径
    static func launchdGatewayLogPath() -> String {
        let snapshot = self.launchdConfigSnapshot()
        if let stdout = snapshot?.stdoutPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stdout.isEmpty
        {
            return stdout
        }
        if let stderr = snapshot?.stderrPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stderr.isEmpty
        {
            return stderr
        }
        return LogLocator.launchdGatewayLogPath
    }
}

extension GatewayLaunchAgentManager {
    /// 读取守护进程加载状态
    private static func readDaemonLoaded() async -> Bool? {
        let result = await self.runDaemonCommandResult(
            ["status", "--json", "--no-probe"],
            timeout: 15,
            quiet: true)
        guard result.success, let payload = result.payload else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
            let service = json["service"] as? [String: Any],
            let loaded = service["loaded"] as? Bool
        else {
            return nil
        }
        return loaded
    }

    /// 命令结果
    private struct CommandResult {
        let success: Bool
        let payload: Data?
        let message: String?
    }

    /// 解析的守护进程JSON
    private struct ParsedDaemonJson {
        let text: String
        let object: [String: Any]
    }

    /// 运行守护进程命令
    private static func runDaemonCommand(
        _ args: [String],
        timeout: Double = 15,
        quiet: Bool = false) async -> String?
    {
        let result = await self.runDaemonCommandResult(args, timeout: timeout, quiet: quiet)
        if result.success { return nil }
        return result.message ?? "Gateway daemon command failed"
    }

    /// 运行守护进程命令并获取结果
    private static func runDaemonCommandResult(
        _ args: [String],
        timeout: Double,
        quiet: Bool) async -> CommandResult
    {
        let command = CommandResolver.moltbotCommand(
            subcommand: "gateway",
            extraArgs: self.withJsonFlag(args),
            // Launchd管理必须始终在本地运行,即使配置了远程模式
            configRoot: ["gateway": ["mode": "local"]])
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = CommandResolver.preferredPaths().joined(separator: ":")
        let response = await ShellExecutor.runDetailed(command: command, cwd: nil, env: env, timeout: timeout)
        let parsed = self.parseDaemonJson(from: response.stdout) ?? self.parseDaemonJson(from: response.stderr)
        let ok = parsed?.object["ok"] as? Bool
        let message = (parsed?.object["error"] as? String) ?? (parsed?.object["message"] as? String)
        let payload = parsed?.text.data(using: .utf8)
            ?? (response.stdout.isEmpty ? response.stderr : response.stdout).data(using: .utf8)
        let success = ok ?? response.success
        if success {
            return CommandResult(success: true, payload: payload, message: nil)
        }

        if quiet {
            return CommandResult(success: false, payload: payload, message: message)
        }

        let detail = message ?? self.summarize(response.stderr) ?? self.summarize(response.stdout)
        let exit = response.exitCode.map { "exit \($0)" } ?? (response.errorMessage ?? "failed")
        let fullMessage = detail.map { "Gateway daemon command failed (\(exit)): \($0)" }
            ?? "Gateway daemon command failed (\(exit))"
        self.logger.error("\(fullMessage, privacy: .public)")
        return CommandResult(success: false, payload: payload, message: detail)
    }

    /// 添加JSON标志
    private static func withJsonFlag(_ args: [String]) -> [String] {
        if args.contains("--json") { return args }
        return args + ["--json"]
    }

    /// 解析守护进程JSON
    private static func parseDaemonJson(from raw: String) -> ParsedDaemonJson? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}")
        else {
            return nil
        }
        let jsonText = String(trimmed[start...end])
        guard let data = jsonText.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return ParsedDaemonJson(text: jsonText, object: object)
    }

    /// 摘要文本
    private static func summarize(_ text: String) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = lines.last else { return nil }
        let normalized = last.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return normalized.count > 200 ? String(normalized.prefix(199)) + "…" : normalized
    }
}

import Foundation

/// CLI 安装器，用于管理 moltbot 命令行工具的安装和检测
@MainActor
enum CLIInstaller {
    /// 获取已安装的 moltbot CLI 工具的位置
    /// - Returns: 已安装的 moltbot CLI 工具的路径，如果未安装则返回 nil
    static func installedLocation() -> String? {
        self.installedLocation(
            searchPaths: CommandResolver.preferredPaths(),
            fileManager: .default)
    }

    /// 获取已安装的 moltbot CLI 工具的位置
    /// - Parameters:
    ///   - searchPaths: 搜索路径数组
    ///   - fileManager: 文件管理器实例
    /// - Returns: 已安装的 moltbot CLI 工具的路径，如果未安装则返回 nil
    static func installedLocation(
        searchPaths: [String],
        fileManager: FileManager) -> String?
    {
        // 遍历所有搜索路径
        for basePath in searchPaths {
            // 构建候选路径
            let candidate = URL(fileURLWithPath: basePath).appendingPathComponent("moltbot").path
            var isDirectory: ObjCBool = false

            // 检查文件是否存在且不是目录
            guard fileManager.fileExists(atPath: candidate, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else {
                continue
            }

            // 检查文件是否可执行
            guard fileManager.isExecutableFile(atPath: candidate) else { continue }

            return candidate
        }

        return nil
    }

    /// 检查 moltbot CLI 工具是否已安装
    /// - Returns: 如果已安装返回 true，否则返回 false
    static func isInstalled() -> Bool {
        self.installedLocation() != nil
    }

    /// 安装 moltbot CLI 工具
    /// - Parameter statusHandler: 状态处理闭包，用于接收安装过程中的状态信息
    static func install(statusHandler: @escaping @MainActor @Sendable (String) async -> Void) async {
        // 获取预期的网关版本
        let expected = GatewayEnvironment.expectedGatewayVersionString() ?? "latest"
        // 获取安装前缀路径
        let prefix = Self.installPrefix()
        // 发送安装开始状态
        await statusHandler("正在安装 moltbot CLI…")
        // 生成安装脚本命令
        let cmd = self.installScriptCommand(version: expected, prefix: prefix)
        // 执行安装脚本，设置超时为 900 秒
        let response = await ShellExecutor.runDetailed(command: cmd, cwd: nil, env: nil, timeout: 900)

        // 检查安装是否成功
        if response.success {
            // 解析安装事件
            let parsed = self.parseInstallEvents(response.stdout)
            // 获取安装的版本号
            let installedVersion = parsed.last { $0.event == "done" }?.version
            // 生成安装成功的摘要信息
            let summary = installedVersion.map { "已安装 moltbot \($0)。" } ?? "已安装 moltbot。"
            // 发送安装成功状态
            await statusHandler(summary)
            return
        }

        // 解析安装事件，查找错误信息
        let parsed = self.parseInstallEvents(response.stdout)
        if let error = parsed.last(where: { $0.event == "error" })?.message {
            // 发送安装失败状态，包含错误信息
            await statusHandler("安装失败: \(error)")
            return
        }

        // 处理其他失败情况
        let detail = response.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = response.errorMessage ?? "安装失败"
        await statusHandler("安装失败: \(detail.isEmpty ? fallback : detail)")
    }

    /// 获取安装前缀路径
    /// - Returns: 安装前缀路径
    private static func installPrefix() -> String {
        FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(".clawdbot")
            .path
    }

    /// 生成安装脚本命令
    /// - Parameters:
    ///   - version: 要安装的版本
    ///   - prefix: 安装前缀路径
    /// - Returns: 安装脚本命令数组
    private static func installScriptCommand(version: String, prefix: String) -> [String] {
        // 对版本和前缀进行 shell 转义
        let escapedVersion = self.shellEscape(version)
        let escapedPrefix = self.shellEscape(prefix)
        // 构建安装脚本
        let script = """
        curl -fsSL https://molt.bot/install-cli.sh | \
        bash -s -- --json --no-onboard --prefix \(escapedPrefix) --version \(escapedVersion)
        """
        // 返回 bash 命令数组
        return ["/bin/bash", "-lc", script]
    }

    /// 解析安装事件
    /// - Parameter output: 安装脚本的输出
    /// - Returns: 安装事件数组
    private static func parseInstallEvents(_ output: String) -> [InstallEvent] {
        let decoder = JSONDecoder()
        // 按换行符分割输出
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
        var events: [InstallEvent] = []
        // 遍历每一行，尝试解析为 InstallEvent
        for line in lines {
            guard let data = line.data(using: .utf8) else { continue }
            if let event = try? decoder.decode(InstallEvent.self, from: data) {
                events.append(event)
            }
        }
        return events
    }

    /// 对字符串进行 shell 转义
    /// - Parameter raw: 原始字符串
    /// - Returns: 转义后的字符串
    private static func shellEscape(_ raw: String) -> String {
        "'" + raw.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

/// 安装事件结构，用于解析安装脚本的输出
private struct InstallEvent: Decodable {
    /// 事件类型
    let event: String
    /// 版本号
    let version: String?
    /// 消息
    let message: String?
}

import Foundation

/// 命令解析器，负责解析和构建 moltbot 相关的命令
enum CommandResolver {
    private static let projectRootDefaultsKey = "moltbot.gatewayProjectRootPath"
    private static let helperName = "moltbot"

    /// 查找网关入口点
    /// - Parameter root: 项目根目录 URL
    /// - Returns: 入口点路径，如果找不到则返回 nil
    static func gatewayEntrypoint(in root: URL) -> String? {
        let distEntry = root.appendingPathComponent("dist/index.js").path
        if FileManager().isReadableFile(atPath: distEntry) { return distEntry }  // 检查 dist/index.js 是否存在
        let binEntry = root.appendingPathComponent("bin/moltbot.js").path
        if FileManager().isReadableFile(atPath: binEntry) { return binEntry }  // 检查 bin/moltbot.js 是否存在
        return nil
    }

    /// 解析运行时环境
    /// - Returns: 运行时解析结果
    static func runtimeResolution() -> Result<RuntimeResolution, RuntimeResolutionError> {
        RuntimeLocator.resolve(searchPaths: self.preferredPaths())
    }

    /// 解析运行时环境（带搜索路径）
    /// - Parameter searchPaths: 自定义搜索路径
    /// - Returns: 运行时解析结果
    static func runtimeResolution(searchPaths: [String]?) -> Result<RuntimeResolution, RuntimeResolutionError> {
        RuntimeLocator.resolve(searchPaths: searchPaths ?? self.preferredPaths())
    }

    /// 构建运行时命令
    /// - Parameters:
    ///   - runtime: 运行时环境
    ///   - entrypoint: 入口点路径
    ///   - subcommand: 子命令
    ///   - extraArgs: 额外参数
    /// - Returns: 命令数组
    static func makeRuntimeCommand(
        runtime: RuntimeResolution,
        entrypoint: String,
        subcommand: String,
        extraArgs: [String]) -> [String]
    {
        [runtime.path, entrypoint, subcommand] + extraArgs
    }

    /// 构建运行时错误命令
    /// - Parameter error: 运行时解析错误
    /// - Returns: 错误命令数组
    static func runtimeErrorCommand(_ error: RuntimeResolutionError) -> [String] {
        let message = RuntimeLocator.describeFailure(error)
        return self.errorCommand(with: message)
    }

    /// 构建错误命令
    /// - Parameter message: 错误信息
    /// - Returns: 错误命令数组
    static func errorCommand(with message: String) -> [String] {
        let script = """
        cat <<'__CLAWDBOT_ERR__' >&2
        \(message)
        __CLAWDBOT_ERR__
        exit 1
        """
        return ["/bin/sh", "-c", script]  // 执行 shell 脚本输出错误信息
    }

    /// 获取项目根目录
    /// - Returns: 项目根目录 URL
    static func projectRoot() -> URL {
        if let stored = UserDefaults.standard.string(forKey: self.projectRootDefaultsKey),
           let url = self.expandPath(stored),
           FileManager().fileExists(atPath: url.path)
        {
            return url  // 使用存储的项目根目录
        }
        let fallback = FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/moltbot")
        if FileManager().fileExists(atPath: fallback.path) {
            return fallback  // 使用默认的项目根目录
        }
        return FileManager().homeDirectoryForCurrentUser  // 回退到用户主目录
    }

    /// 设置项目根目录
    /// - Parameter path: 项目根目录路径
    static func setProjectRoot(_ path: String) {
        UserDefaults.standard.set(path, forKey: self.projectRootDefaultsKey)
    }

    /// 获取项目根目录路径
    /// - Returns: 项目根目录路径字符串
    static func projectRootPath() -> String {
        self.projectRoot().path
    }

    /// 获取首选搜索路径
    /// - Returns: 搜索路径数组
    static func preferredPaths() -> [String] {
        let current = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":").map(String.init) ?? []
        let home = FileManager().homeDirectoryForCurrentUser
        let projectRoot = self.projectRoot()
        return self.preferredPaths(home: home, current: current, projectRoot: projectRoot)
    }

    /// 获取首选搜索路径（带参数）
    /// - Parameters:
    ///   - home: 用户主目录
    ///   - current: 当前 PATH 环境变量中的路径
    ///   - projectRoot: 项目根目录
    /// - Returns: 搜索路径数组
    static func preferredPaths(home: URL, current: [String], projectRoot: URL) -> [String] {
        var extras = [
            home.appendingPathComponent("Library/pnpm").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        #if DEBUG
        // 开发模式下的便捷设置，避免在发布版本中被项目本地 PATH 劫持
        extras.insert(projectRoot.appendingPathComponent("node_modules/.bin").path, at: 0)
        #endif
        let moltbotPaths = self.moltbotManagedPaths(home: home)
        if !moltbotPaths.isEmpty {
            extras.insert(contentsOf: moltbotPaths, at: 1)
        }
        extras.insert(contentsOf: self.nodeManagerBinPaths(home: home), at: 1 + moltbotPaths.count)
        var seen = Set<String>()
        // 保持顺序同时去除重复项，确保 PATH 查找保持确定性
        return (extras + current).filter { seen.insert($0).inserted }
    }

    /// 获取 moltbot 管理的路径
    /// - Parameter home: 用户主目录
    /// - Returns: 路径数组
    private static func moltbotManagedPaths(home: URL) -> [String] {
        let base = home.appendingPathComponent(".clawdbot")
        let bin = base.appendingPathComponent("bin")
        let nodeBin = base.appendingPathComponent("tools/node/bin")
        var paths: [String] = []
        if FileManager().fileExists(atPath: bin.path) {
            paths.append(bin.path)
        }
        if FileManager().fileExists(atPath: nodeBin.path) {
            paths.append(nodeBin.path)
        }
        return paths
    }

    /// 获取 Node 版本管理器的二进制路径
    /// - Parameter home: 用户主目录
    /// - Returns: 路径数组
    private static func nodeManagerBinPaths(home: URL) -> [String] {
        var bins: [String] = []

        // Volta
        let volta = home.appendingPathComponent(".volta/bin")
        if FileManager().fileExists(atPath: volta.path) {
            bins.append(volta.path)
        }

        // asdf
        let asdf = home.appendingPathComponent(".asdf/shims")
        if FileManager().fileExists(atPath: asdf.path) {
            bins.append(asdf.path)
        }

        // fnm
        bins.append(contentsOf: self.versionedNodeBinPaths(
            base: home.appendingPathComponent(".local/share/fnm/node-versions"),
            suffix: "installation/bin"))

        // nvm
        bins.append(contentsOf: self.versionedNodeBinPaths(
            base: home.appendingPathComponent(".nvm/versions/node"),
            suffix: "bin"))

        return bins
    }

    /// 获取版本化的 Node 二进制路径
    /// - Parameters:
    ///   - base: 基础目录
    ///   - suffix: 路径后缀
    /// - Returns: 路径数组
    private static func versionedNodeBinPaths(base: URL, suffix: String) -> [String] {
        guard FileManager().fileExists(atPath: base.path) else { return [] }
        let entries: [String]
        do {
            entries = try FileManager().contentsOfDirectory(atPath: base.path)
        } catch {
            return []
        }

        /// 解析版本号
        func parseVersion(_ name: String) -> [Int] {
            let trimmed = name.hasPrefix("v") ? String(name.dropFirst()) : name
            return trimmed.split(separator: ".").compactMap { Int($0) }
        }

        // 按版本号降序排序
        let sorted = entries.sorted { a, b in
            let va = parseVersion(a)
            let vb = parseVersion(b)
            let maxCount = max(va.count, vb.count)
            for i in 0..<maxCount {
                let ai = i < va.count ? va[i] : 0
                let bi = i < vb.count ? vb[i] : 0
                if ai != bi { return ai > bi }
            }
            // 如果版本号数值相同，保持稳定排序
            return a > b
        }

        var paths: [String] = []
        for entry in sorted {
            let binDir = base.appendingPathComponent(entry).appendingPathComponent(suffix)
            let node = binDir.appendingPathComponent("node")
            if FileManager().isExecutableFile(atPath: node.path) {
                paths.append(binDir.path)
            }
        }
        return paths
    }

    /// 查找可执行文件
    /// - Parameters:
    ///   - name: 可执行文件名
    ///   - searchPaths: 搜索路径
    /// - Returns: 可执行文件路径，如果找不到则返回 nil
    static func findExecutable(named name: String, searchPaths: [String]? = nil) -> String? {
        for dir in searchPaths ?? self.preferredPaths() {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager().isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 查找 moltbot 可执行文件
    /// - Parameter searchPaths: 搜索路径
    /// - Returns: moltbot 可执行文件路径，如果找不到则返回 nil
    static func moltbotExecutable(searchPaths: [String]? = nil) -> String? {
        self.findExecutable(named: self.helperName, searchPaths: searchPaths)
    }

    /// 查找项目本地的 moltbot 可执行文件
    /// - Parameter projectRoot: 项目根目录
    /// - Returns: moltbot 可执行文件路径，如果找不到则返回 nil
    static func projectMoltbotExecutable(projectRoot: URL? = nil) -> String? {
        #if DEBUG
        let root = projectRoot ?? self.projectRoot()
        let candidate = root.appendingPathComponent("node_modules/.bin").appendingPathComponent(self.helperName).path
        return FileManager().isExecutableFile(atPath: candidate) ? candidate : nil
        #else
        return nil
        #endif
    }

    /// 获取 Node CLI 路径
    /// - Returns: Node CLI 路径，如果找不到则返回 nil
    static func nodeCliPath() -> String? {
        let candidate = self.projectRoot().appendingPathComponent("bin/moltbot.js").path
        return FileManager().isReadableFile(atPath: candidate) ? candidate : nil
    }

    /// 检查是否有任何 moltbot 调用器
    /// - Parameter searchPaths: 搜索路径
    /// - Returns: 是否存在 moltbot 调用器
    static func hasAnyMoltbotInvoker(searchPaths: [String]? = nil) -> Bool {
        if self.moltbotExecutable(searchPaths: searchPaths) != nil { return true }
        if self.findExecutable(named: "pnpm", searchPaths: searchPaths) != nil { return true }
        if self.findExecutable(named: "node", searchPaths: searchPaths) != nil,
           self.nodeCliPath() != nil
        {
            return true
        }
        return false
    }

    /// 构建 moltbot Node 命令
    /// - Parameters:
    ///   - subcommand: 子命令
    ///   - extraArgs: 额外参数
    ///   - defaults: 用户默认设置
    ///   - configRoot: 配置根目录
    ///   - searchPaths: 搜索路径
    /// - Returns: 命令数组
    static func moltbotNodeCommand(
        subcommand: String,
        extraArgs: [String] = [],
        defaults: UserDefaults = .standard,
        configRoot: [String: Any]? = nil,
        searchPaths: [String]? = nil) -> [String]
    {
        let settings = self.connectionSettings(defaults: defaults, configRoot: configRoot)
        if settings.mode == .remote, let ssh = self.sshNodeCommand(
            subcommand: subcommand,
            extraArgs: extraArgs,
            settings: settings)
        {
            return ssh
        }

        let runtimeResult = self.runtimeResolution(searchPaths: searchPaths)

        switch runtimeResult {
        case let .success(runtime):
            let root = self.projectRoot()
            if let moltbotPath = self.projectMoltbotExecutable(projectRoot: root) {
                return [moltbotPath, subcommand] + extraArgs
            }

            if let entry = self.gatewayEntrypoint(in: root) {
                return self.makeRuntimeCommand(
                    runtime: runtime,
                    entrypoint: entry,
                    subcommand: subcommand,
                    extraArgs: extraArgs)
            }
            if let pnpm = self.findExecutable(named: "pnpm", searchPaths: searchPaths) {
                // 使用 --silent 避免 pnpm 生命周期横幅干扰 JSON 输出
                return [pnpm, "--silent", "moltbot", subcommand] + extraArgs
            }
            if let moltbotPath = self.moltbotExecutable(searchPaths: searchPaths) {
                return [moltbotPath, subcommand] + extraArgs
            }

            let missingEntry = """
moltbot 入口点缺失（查找了 dist/index.js 或 bin/moltbot.js）；请运行 pnpm build。
            """
            return self.errorCommand(with: missingEntry)

        case let .failure(error):
            return self.runtimeErrorCommand(error)
        }
    }

    // 现有调用者仍引用 moltbotCommand；保持作为 node 别名
    /// 构建 moltbot 命令（与 moltbotNodeCommand 相同）
    /// - Parameters:
    ///   - subcommand: 子命令
    ///   - extraArgs: 额外参数
    ///   - defaults: 用户默认设置
    ///   - configRoot: 配置根目录
    ///   - searchPaths: 搜索路径
    /// - Returns: 命令数组
    static func moltbotCommand(
        subcommand: String,
        extraArgs: [String] = [],
        defaults: UserDefaults = .standard,
        configRoot: [String: Any]? = nil,
        searchPaths: [String]? = nil) -> [String]
    {
        self.moltbotNodeCommand(
            subcommand: subcommand,
            extraArgs: extraArgs,
            defaults: defaults,
            configRoot: configRoot,
            searchPaths: searchPaths)
    }

    // MARK: - SSH 辅助方法

    /// 构建 SSH Node 命令
    /// - Parameters:
    ///   - subcommand: 子命令
    ///   - extraArgs: 额外参数
    ///   - settings: 远程设置
    /// - Returns: SSH 命令数组
    private static func sshNodeCommand(subcommand: String, extraArgs: [String], settings: RemoteSettings) -> [String]? {
        guard !settings.target.isEmpty else { return nil }
        guard let parsed = self.parseSSHTarget(settings.target) else { return nil }

        // 在远程主机上运行真正的 moltbot CLI
        let exportedPath = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "$HOME/Library/pnpm",
            "$PATH",
        ].joined(separator: ":")
        let quotedArgs = ([subcommand] + extraArgs).map(self.shellQuote).joined(separator: " ")
        let userPRJ = settings.projectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        let userCLI = settings.cliPath.trimmingCharacters(in: .whitespacesAndNewlines)

        let projectSection = if userPRJ.isEmpty {
            """
            DEFAULT_PRJ="$HOME/Projects/moltbot"
            if [ -d "$DEFAULT_PRJ" ]; then
              PRJ="$DEFAULT_PRJ"
              cd "$PRJ" || { echo "Project root not found: $PRJ"; exit 127; }
            fi
            """
        } else {
            """
            PRJ=\(self.shellQuote(userPRJ))
            cd "$PRJ" || { echo "Project root not found: $PRJ"; exit 127; }
            """
        }

        let cliSection = if userCLI.isEmpty {
            ""
        } else {
            """
            CLI_HINT=\(self.shellQuote(userCLI))
            if [ -n "$CLI_HINT" ]; then
              if [ -x "$CLI_HINT" ]; then
                CLI="$CLI_HINT"
                "$CLI_HINT" \(quotedArgs);
                exit $?;
              elif [ -f "$CLI_HINT" ]; then
                if command -v node >/dev/null 2>&1; then
                  CLI="node $CLI_HINT"
                  node "$CLI_HINT" \(quotedArgs);
                  exit $?;
                fi
              fi
            fi
            """
        }

        let scriptBody = """
        PATH=\(exportedPath);
        CLI="";
        \(cliSection)
        \(projectSection)
        if command -v moltbot >/dev/null 2>&1; then
          CLI="$(command -v moltbot)"
          moltbot \(quotedArgs);
        elif [ -n "${PRJ:-}" ] && [ -f "$PRJ/dist/index.js" ]; then
          if command -v node >/dev/null 2>&1; then
            CLI="node $PRJ/dist/index.js"
            node "$PRJ/dist/index.js" \(quotedArgs);
          else
            echo "Node >=22 required on remote host"; exit 127;
          fi
        elif [ -n "${PRJ:-}" ] && [ -f "$PRJ/bin/moltbot.js" ]; then
          if command -v node >/dev/null 2>&1; then
            CLI="node $PRJ/bin/moltbot.js"
            node "$PRJ/bin/moltbot.js" \(quotedArgs);
          else
            echo "Node >=22 required on remote host"; exit 127;
          fi
        elif command -v pnpm >/dev/null 2>&1; then
          CLI="pnpm --silent moltbot"
          pnpm --silent moltbot \(quotedArgs);
        else
          echo "moltbot CLI missing on remote host"; exit 127;
        fi
        """
        let options: [String] = [
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UpdateHostKeys=yes",
        ]
        let args = self.sshArguments(
            target: parsed,
            identity: settings.identity,
            options: options,
            remoteCommand: ["/bin/sh", "-c", scriptBody])
        return ["/usr/bin/ssh"] + args
    }

    /// 远程设置结构体
    struct RemoteSettings {
        let mode: AppState.ConnectionMode
        let target: String
        let identity: String
        let projectRoot: String
        let cliPath: String
    }

    /// 获取连接设置
    /// - Parameters:
    ///   - defaults: 用户默认设置
    ///   - configRoot: 配置根目录
    /// - Returns: 远程设置
    static func connectionSettings(
        defaults: UserDefaults = .standard,
        configRoot: [String: Any]? = nil) -> RemoteSettings
    {
        let root = configRoot ?? MoltbotConfigFile.loadDict()
        let mode = ConnectionModeResolver.resolve(root: root, defaults: defaults).mode
        let target = defaults.string(forKey: remoteTargetKey) ?? ""
        let identity = defaults.string(forKey: remoteIdentityKey) ?? ""
        let projectRoot = defaults.string(forKey: remoteProjectRootKey) ?? ""
        let cliPath = defaults.string(forKey: remoteCliPathKey) ?? ""
        return RemoteSettings(
            mode: mode,
            target: self.sanitizedTarget(target),
            identity: identity,
            projectRoot: projectRoot,
            cliPath: cliPath)
    }

    /// 检查连接模式是否为远程
    /// - Parameter defaults: 用户默认设置
    /// - Returns: 是否为远程模式
    static func connectionModeIsRemote(defaults: UserDefaults = .standard) -> Bool {
        self.connectionSettings(defaults: defaults).mode == .remote
    }

    /// 清理 SSH 目标字符串
    /// - Parameter raw: 原始目标字符串
    /// - Returns: 清理后的目标字符串
    private static func sanitizedTarget(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ssh ") {
            return trimmed.replacingOccurrences(of: "ssh ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// SSH 解析目标结构体
    struct SSHParsedTarget {
        let user: String?
        let host: String
        let port: Int
    }

    /// 解析 SSH 目标
    /// - Parameter target: 目标字符串
    /// - Returns: 解析后的 SSH 目标，如果解析失败则返回 nil
    static func parseSSHTarget(_ target: String) -> SSHParsedTarget? {
        let trimmed = self.normalizeSSHTargetInput(target)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) != nil {
            return nil
        }
        let userHostPort: String
        let user: String?
        if let atRange = trimmed.range(of: "@") {
            user = String(trimmed[..<atRange.lowerBound])
            userHostPort = String(trimmed[atRange.upperBound...])
        } else {
            user = nil
            userHostPort = trimmed
        }

        let host: String
        let port: Int
        if let colon = userHostPort.lastIndex(of: ":"), colon != userHostPort.startIndex {
            host = String(userHostPort[..<colon])
            let portStr = String(userHostPort[userHostPort.index(after: colon)...])
            guard let parsedPort = Int(portStr), parsedPort > 0, parsedPort <= 65535 else {
                return nil
            }
            port = parsedPort
        } else {
            host = userHostPort
            port = 22
        }

        return self.makeSSHTarget(user: user, host: host, port: port)
    }

    /// 获取 SSH 目标验证消息
    /// - Parameter target: 目标字符串
    /// - Returns: 验证错误消息，如果验证通过则返回 nil
    static func sshTargetValidationMessage(_ target: String) -> String? {
        let trimmed = self.normalizeSSHTargetInput(target)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("-") {
            return "SSH 目标不能以 '-' 开头"
        }
        if trimmed.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) != nil {
            return "SSH 目标不能包含空格"
        }
        if self.parseSSHTarget(trimmed) == nil {
            return "SSH 目标必须形如 user@host[:port]"
        }
        return nil
    }

    /// 对字符串进行 shell 引用
    /// - Parameter text: 原始文本
    /// - Returns: 引用后的文本
    private static func shellQuote(_ text: String) -> String {
        if text.isEmpty { return "''" }
        let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// 展开路径
    /// - Parameter path: 原始路径
    /// - Returns: 展开后的 URL，如果展开失败则返回 nil
    private static func expandPath(_ path: String) -> URL? {
        var expanded = path
        if expanded.hasPrefix("~") {
            let home = FileManager().homeDirectoryForCurrentUser.path
            expanded.replaceSubrange(expanded.startIndex...expanded.startIndex, with: home)
        }
        return URL(fileURLWithPath: expanded)
    }

    /// 标准化 SSH 目标输入
    /// - Parameter target: 原始目标字符串
    /// - Returns: 标准化后的目标字符串
    private static func normalizeSSHTargetInput(_ target: String) -> String {
        var trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ssh ") {
            trimmed = trimmed.replacingOccurrences(of: "ssh ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// 验证 SSH 组件是否有效
    /// - Parameters:
    ///   - value: 组件值
    ///   - allowLeadingDash: 是否允许以 '-' 开头
    /// - Returns: 是否有效
    private static func isValidSSHComponent(_ value: String, allowLeadingDash: Bool = false) -> Bool {
        if value.isEmpty { return false }
        if !allowLeadingDash, value.hasPrefix("-") { return false }
        let invalid = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        return value.rangeOfCharacter(from: invalid) == nil
    }

    /// 构建 SSH 目标
    /// - Parameters:
    ///   - user: 用户名
    ///   - host: 主机名
    ///   - port: 端口号
    /// - Returns: SSH 目标，如果构建失败则返回 nil
    static func makeSSHTarget(user: String?, host: String, port: Int) -> SSHParsedTarget? {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.isValidSSHComponent(trimmedHost) else { return nil }
        let trimmedUser = user?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUser: String?
        if let trimmedUser {
            guard self.isValidSSHComponent(trimmedUser) else { return nil }
            normalizedUser = trimmedUser.isEmpty ? nil : trimmedUser
        } else {
            normalizedUser = nil
        }
        guard port > 0, port <= 65535 else { return nil }
        return SSHParsedTarget(user: normalizedUser, host: trimmedHost, port: port)
    }

    /// 获取 SSH 目标字符串
    /// - Parameter target: SSH 目标
    /// - Returns: 目标字符串
    private static func sshTargetString(_ target: SSHParsedTarget) -> String {
        target.user.map { "\($0)@\(target.host)" } ?? target.host
    }

    /// 构建 SSH 参数
    /// - Parameters:
    ///   - target: SSH 目标
    ///   - identity: 身份文件路径
    ///   - options: SSH 选项
    ///   - remoteCommand: 远程命令
    /// - Returns: SSH 参数数组
    static func sshArguments(
        target: SSHParsedTarget,
        identity: String,
        options: [String],
        remoteCommand: [String] = []) -> [String]
    {
        var args = options
        if target.port > 0 {
            args.append(contentsOf: ["-p", String(target.port)])
        }
        let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedIdentity.isEmpty {
            // 仅当提供了显式身份文件时使用 IdentitiesOnly
            // 这允许 1Password SSH agent 和其他 SSH agent 提供密钥
            args.append(contentsOf: ["-o", "IdentitiesOnly=yes"])
            args.append(contentsOf: ["-i", trimmedIdentity])
        }
        args.append("--")
        args.append(self.sshTargetString(target))
        args.append(contentsOf: remoteCommand)
        return args
    }

    #if SWIFT_PACKAGE
    /// 测试方法：获取 Node 版本管理器的二进制路径
    /// - Parameter home: 用户主目录
    /// - Returns: 路径数组
    static func _testNodeManagerBinPaths(home: URL) -> [String] {
        self.nodeManagerBinPaths(home: home)
    }
    #endif
}

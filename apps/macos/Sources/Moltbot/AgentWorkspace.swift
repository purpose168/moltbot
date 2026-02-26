import Foundation
import OSLog

/// AgentWorkspace 枚举：管理 Moltbot 工作区的核心功能
/// 负责工作区的初始化、模板管理、安全检查等操作
enum AgentWorkspace {
    private static let logger = Logger(subsystem: "bot.molt", category: "workspace")
    /// 工作区文件名称常量
    static let agentsFilename = "AGENTS.md"         // 工作区主文件
    static let soulFilename = "SOUL.md"             // 人格与边界定义文件
    static let identityFilename = "IDENTITY.md"     // 代理身份文件
    static let userFilename = "USER.md"             // 用户配置文件
    static let bootstrapFilename = "BOOTSTRAP.md"   // 首次运行引导文件
    private static let templateDirname = "templates" // 模板目录名称
    /// 需要忽略的目录/文件
    private static let ignoredEntries: Set<String> = [".DS_Store", ".git", ".gitignore"]
    /// 模板文件集合
    private static let templateEntries: Set<String> = [
        AgentWorkspace.agentsFilename,
        AgentWorkspace.soulFilename,
        AgentWorkspace.identityFilename,
        AgentWorkspace.userFilename,
        AgentWorkspace.bootstrapFilename,
    ]
    /// 引导安全状态枚举
    enum BootstrapSafety: Equatable {
        case safe           // 安全状态
        case unsafe(reason: String) // 不安全状态及原因
    }

    /// 将 URL 转换为用户友好的显示路径
    /// - Parameter url: 要转换的 URL
    /// - Returns: 格式化后的路径字符串，包含波浪号(~)表示主目录
    static func displayPath(for url: URL) -> String {
        let home = FileManager().homeDirectoryForCurrentUser.path
        let path = url.path
        if path == home { return "~" } // 如果是主目录，返回波浪号
        if path.hasPrefix(home + "/") {
            // 如果路径以主目录开头，将主目录替换为波浪号
            return "~/" + String(path.dropFirst(home.count + 1))
        }
        return path // 其他情况返回原始路径
    }

    /// 解析用户输入的工作区路径
    /// - Parameter userInput: 用户输入的路径字符串
    /// - Returns: 解析后的工作区 URL
    static func resolveWorkspaceURL(from userInput: String?) -> URL {
        let trimmed = userInput?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return MoltbotConfigFile.defaultWorkspaceURL() } // 如果输入为空，返回默认工作区
        let expanded = (trimmed as NSString).expandingTildeInPath // 展开波浪号路径
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    /// 获取工作区中的 AGENTS.md 文件 URL
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: AGENTS.md 文件的 URL
    static func agentsURL(workspaceURL: URL) -> URL {
        workspaceURL.appendingPathComponent(self.agentsFilename)
    }

    /// 获取工作区中的条目列表
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: 工作区中的文件和目录列表（排除忽略项）
    /// - Throws: 如果无法读取目录内容
    static func workspaceEntries(workspaceURL: URL) throws -> [String] {
        let contents = try FileManager().contentsOfDirectory(atPath: workspaceURL.path)
        return contents.filter { !self.ignoredEntries.contains($0) } // 过滤掉需要忽略的条目
    }

    /// 检查工作区是否为空
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: 如果工作区不存在或为空目录则返回 true，否则返回 false
    static func isWorkspaceEmpty(workspaceURL: URL) -> Bool {
        let fm = FileManager()
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: workspaceURL.path, isDirectory: &isDir) {
            return true // 目录不存在视为空
        }
        guard isDir.boolValue else { return false } // 如果不是目录，返回 false
        guard let entries = try? self.workspaceEntries(workspaceURL: workspaceURL) else { return false }
        return entries.isEmpty // 检查是否有条目
    }

    /// 检查工作区是否只包含模板文件
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: 如果工作区只包含模板文件则返回 true，否则返回 false
    static func isTemplateOnlyWorkspace(workspaceURL: URL) -> Bool {
        guard let entries = try? self.workspaceEntries(workspaceURL: workspaceURL) else { return false }
        guard !entries.isEmpty else { return true } // 空目录视为仅模板
        return Set(entries).isSubset(of: self.templateEntries) // 检查所有条目是否都是模板文件
    }

    /// 检查工作区的引导安全性
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: 引导安全状态
    static func bootstrapSafety(for workspaceURL: URL) -> BootstrapSafety {
        let fm = FileManager()
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: workspaceURL.path, isDirectory: &isDir) {
            return .safe // 目录不存在视为安全
        }
        if !isDir.boolValue {
            return .unsafe(reason: "工作区路径指向一个文件。")
        }
        let agentsURL = self.agentsURL(workspaceURL: workspaceURL)
        if fm.fileExists(atPath: agentsURL.path) {
            return .safe // 存在 AGENTS.md 视为安全
        }
        do {
            let entries = try self.workspaceEntries(workspaceURL: workspaceURL)
            return entries.isEmpty
                ? .safe
                : .unsafe(reason: "文件夹不为空。请选择一个新文件夹或先添加 AGENTS.md。")
        } catch {
            return .unsafe(reason: "无法检查工作区文件夹。")
        }
    }

    /// 引导工作区，创建必要的模板文件
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: AGENTS.md 文件的 URL
    /// - Throws: 如果无法创建目录或写入文件
    static func bootstrap(workspaceURL: URL) throws -> URL {
        let shouldSeedBootstrap = self.isWorkspaceEmpty(workspaceURL: workspaceURL)
        // 创建工作区目录（如果不存在）
        try FileManager().createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        
        // 创建 AGENTS.md 文件
        let agentsURL = self.agentsURL(workspaceURL: workspaceURL)
        if !FileManager().fileExists(atPath: agentsURL.path) {
            try self.defaultTemplate().write(to: agentsURL, atomically: true, encoding: .utf8)
            self.logger.info("Created AGENTS.md at \(agentsURL.path, privacy: .public)")
        }
        
        // 创建 SOUL.md 文件
        let soulURL = workspaceURL.appendingPathComponent(self.soulFilename)
        if !FileManager().fileExists(atPath: soulURL.path) {
            try self.defaultSoulTemplate().write(to: soulURL, atomically: true, encoding: .utf8)
            self.logger.info("Created SOUL.md at \(soulURL.path, privacy: .public)")
        }
        
        // 创建 IDENTITY.md 文件
        let identityURL = workspaceURL.appendingPathComponent(self.identityFilename)
        if !FileManager().fileExists(atPath: identityURL.path) {
            try self.defaultIdentityTemplate().write(to: identityURL, atomically: true, encoding: .utf8)
            self.logger.info("Created IDENTITY.md at \(identityURL.path, privacy: .public)")
        }
        
        // 创建 USER.md 文件
        let userURL = workspaceURL.appendingPathComponent(self.userFilename)
        if !FileManager().fileExists(atPath: userURL.path) {
            try self.defaultUserTemplate().write(to: userURL, atomically: true, encoding: .utf8)
            self.logger.info("Created USER.md at \(userURL.path, privacy: .public)")
        }
        
        // 如果工作区为空，创建 BOOTSTRAP.md 文件
        let bootstrapURL = workspaceURL.appendingPathComponent(self.bootstrapFilename)
        if shouldSeedBootstrap, !FileManager().fileExists(atPath: bootstrapURL.path) {
            try self.defaultBootstrapTemplate().write(to: bootstrapURL, atomically: true, encoding: .utf8)
            self.logger.info("Created BOOTSTRAP.md at \(bootstrapURL.path, privacy: .public)")
        }
        
        return agentsURL
    }

    /// 检查工作区是否需要引导
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: 如果需要引导则返回 true，否则返回 false
    static func needsBootstrap(workspaceURL: URL) -> Bool {
        let fm = FileManager()
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: workspaceURL.path, isDirectory: &isDir) {
            return true // 目录不存在需要引导
        }
        guard isDir.boolValue else { return true } // 不是目录需要引导
        if self.hasIdentity(workspaceURL: workspaceURL) {
            return false // 已有身份信息不需要引导
        }
        let bootstrapURL = workspaceURL.appendingPathComponent(self.bootstrapFilename)
        guard fm.fileExists(atPath: bootstrapURL.path) else { return false } // 没有引导文件不需要引导
        return self.isTemplateOnlyWorkspace(workspaceURL: workspaceURL) // 只有模板文件需要引导
    }

    /// 检查工作区是否有身份信息
    /// - Parameter workspaceURL: 工作区目录 URL
    /// - Returns: 如果 IDENTITY.md 文件存在且有值则返回 true，否则返回 false
    static func hasIdentity(workspaceURL: URL) -> Bool {
        let identityURL = workspaceURL.appendingPathComponent(self.identityFilename)
        guard let contents = try? String(contentsOf: identityURL, encoding: .utf8) else { return false }
        return self.identityLinesHaveValues(contents)
    }

    /// 检查身份文件内容是否有值
    /// - Parameter content: IDENTITY.md 文件内容
    /// - Returns: 如果有任何非空值则返回 true，否则返回 false
    private static func identityLinesHaveValues(_ content: String) -> Bool {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("-"), let colon = trimmed.firstIndex(of: ":") else { continue }
            let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return true // 找到非空值
            }
        }
        return false // 所有值都为空
    }

    /// 获取默认的 AGENTS.md 模板内容
    /// - Returns: AGENTS.md 模板字符串
    static func defaultTemplate() -> String {
        let fallback = """
        # AGENTS.md - Moltbot 工作区

        此文件夹是助手的工作目录。

        ## 首次运行（一次性）
        - 如果存在 BOOTSTRAP.md，请按照其步骤操作并在完成后删除它。
        - 你的代理身份存储在 IDENTITY.md 中。
        - 你的个人资料存储在 USER.md 中。

        ## 备份提示（推荐）
        如果你将此工作区视为代理的"记忆"，请将其设置为 git 仓库（理想情况下为私有），以便备份身份和笔记。

        ```bash
        git init
        git add AGENTS.md
        git commit -m "Add agent workspace"
        ```

        ## 安全默认值
        - 不要泄露秘密或私人数据。
        - 除非明确要求，否则不要运行破坏性命令。
        - 聊天中保持简洁；将较长的输出写入此工作区中的文件。

        ## 每日记忆（推荐）
        - 在 memory/YYYY-MM-DD.md 中保持简短的每日日志（必要时创建 memory/ 目录）。
        - 会话开始时，如果存在，阅读今天和昨天的日志。
        - 捕获持久事实、偏好和决策；避免记录秘密。

        ## 自定义
        - 在此处添加你喜欢的风格、规则和"记忆"。
        """
        return self.loadTemplate(named: self.agentsFilename, fallback: fallback)
    }

    /// 获取默认的 SOUL.md 模板内容
    /// - Returns: SOUL.md 模板字符串
    static func defaultSoulTemplate() -> String {
        let fallback = """
        # SOUL.md - 人格与边界

        描述助手是谁、语气和边界。

        - 保持回复简洁直接。
        - 在需要时提出澄清问题。
        - 永远不要向外部消息表面发送流式/部分回复。
        """
        return self.loadTemplate(named: self.soulFilename, fallback: fallback)
    }

    /// 获取默认的 IDENTITY.md 模板内容
    /// - Returns: IDENTITY.md 模板字符串
    static func defaultIdentityTemplate() -> String {
        let fallback = """
        # IDENTITY.md - 代理身份

        - 名称:
        - 生物类型:
        - 风格:
        - 表情符号:
        """
        return self.loadTemplate(named: self.identityFilename, fallback: fallback)
    }

    /// 获取默认的 USER.md 模板内容
    /// - Returns: USER.md 模板字符串
    static func defaultUserTemplate() -> String {
        let fallback = """
        # USER.md - 用户资料

        - 名称:
        - 首选称呼:
        - 代词 (可选):
        - 时区 (可选):
        - 备注:
        """
        return self.loadTemplate(named: self.userFilename, fallback: fallback)
    }

    /// 获取默认的 BOOTSTRAP.md 模板内容
    /// - Returns: BOOTSTRAP.md 模板字符串
    static func defaultBootstrapTemplate() -> String {
        let fallback = """
        # BOOTSTRAP.md - 首次运行仪式（完成后删除）

        你好。我刚刚诞生。

        ## 你的任务
        开始一个简短、有趣的对话并了解：
        - 我是谁？
        - 我是什么？
        - 你是谁？
        - 我应该如何称呼你？

        ## 如何询问（可爱 + 有帮助）
        说：
        "你好！我刚刚诞生。我是谁？我是什么？你是谁？我应该如何称呼你？"

        然后提供建议：
        - 3-5 个名字建议。
        - 3-5 个生物类型/风格组合。
        - 5 个表情符号建议。

        ## 写入这些文件
        在用户选择后，更新：

        1) IDENTITY.md
        - 名称
        - 生物类型
        - 风格
        - 表情符号

        2) USER.md
        - 名称
        - 首选称呼
        - 代词 (可选)
        - 时区 (可选)
        - 备注

        3) ~/.clawdbot/moltbot.json
        设置 identity.name, identity.theme, identity.emoji 以匹配 IDENTITY.md。

        ## 清理
        完成后删除 BOOTSTRAP.md。
        """
        return self.loadTemplate(named: self.bootstrapFilename, fallback: fallback)
    }

    /// 加载模板文件
    /// - Parameters:
    ///   - named: 模板文件名
    ///   - fallback: 当无法加载模板时使用的回退内容
    /// - Returns: 模板内容字符串
    private static func loadTemplate(named: String, fallback: String) -> String {
        for url in self.templateURLs(named: named) {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                let stripped = self.stripFrontMatter(content)
                if !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return stripped
                }
            }
        }
        return fallback
    }

    /// 获取模板文件的所有可能 URL
    /// - Parameter named: 模板文件名
    /// - Returns: 模板文件的 URL 数组
    private static func templateURLs(named: String) -> [URL] {
        var urls: [URL] = []
        // 尝试从主包中加载（不带扩展名）
        if let resource = Bundle.main.url(
            forResource: named.replacingOccurrences(of: ".md", with: ""),
            withExtension: "md",
            subdirectory: self.templateDirname)
        {
            urls.append(resource)
        }
        // 尝试从主包中加载（带扩展名）
        if let resource = Bundle.main.url(
            forResource: named,
            withExtension: nil,
            subdirectory: self.templateDirname)
        {
            urls.append(resource)
        }
        // 尝试加载开发模板
        if let dev = self.devTemplateURL(named: named) {
            urls.append(dev)
        }
        // 尝试从当前目录的 docs/templates 加载
        let cwd = URL(fileURLWithPath: FileManager().currentDirectoryPath)
        urls.append(cwd.appendingPathComponent("docs")
            .appendingPathComponent(self.templateDirname)
            .appendingPathComponent(named))
        return urls
    }

    /// 获取开发模板文件 URL
    /// - Parameter named: 模板文件名
    /// - Returns: 开发模板文件 URL（如果存在）
    private static func devTemplateURL(named: String) -> URL? {
        let sourceURL = URL(fileURLWithPath: #filePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent() // 向上导航到仓库根目录
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot.appendingPathComponent("docs")
            .appendingPathComponent(self.templateDirname)
            .appendingPathComponent(named)
    }

    /// 去除模板文件中的前端内容（front matter）
    /// - Parameter content: 模板文件内容
    /// - Returns: 去除前端内容后的字符串
    private static func stripFrontMatter(_ content: String) -> String {
        guard content.hasPrefix("---") else { return content }
        let start = content.index(content.startIndex, offsetBy: 3)
        guard let range = content.range(of: "\n---", range: start..<content.endIndex) else {
            return content
        }
        let remainder = content[range.upperBound...]
        let trimmed = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed + "\n"
    }

    // 身份信息由代理在引导仪式期间写入。
}

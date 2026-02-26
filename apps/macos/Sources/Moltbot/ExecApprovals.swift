import CryptoKit
import Foundation
import OSLog
import Security

/// 执行安全级别
enum ExecSecurity: String, CaseIterable, Codable, Identifiable {
    case deny
    case allowlist
    case full

    var id: String { self.rawValue }

    /// 标题
    var title: String {
        switch self {
        case .deny: "拒绝"
        case .allowlist: "允许列表"
        case .full: "始终允许"
        }
    }
}

/// 执行批准快速模式
enum ExecApprovalQuickMode: String, CaseIterable, Identifiable {
    case deny
    case ask
    case allow

    var id: String { self.rawValue }

    /// 标题
    var title: String {
        switch self {
        case .deny: "拒绝"
        case .ask: "始终询问"
        case .allow: "始终允许"
        }
    }

    /// 安全级别
    var security: ExecSecurity {
        switch self {
        case .deny: .deny
        case .ask: .allowlist
        case .allow: .full
        }
    }

    /// 询问模式
    var ask: ExecAsk {
        switch self {
        case .deny: .off
        case .ask: .onMiss
        case .allow: .off
        }
    }

    /// 从安全级别和询问模式创建快速模式
    static func from(security: ExecSecurity, ask: ExecAsk) -> ExecApprovalQuickMode {
        switch security {
        case .deny:
            .deny
        case .full:
            .allow
        case .allowlist:
            .ask
        }
    }
}

/// 执行询问模式
enum ExecAsk: String, CaseIterable, Codable, Identifiable {
    case off
    case onMiss = "on-miss"
    case always

    var id: String { self.rawValue }

    /// 标题
    var title: String {
        switch self {
        case .off: "从不询问"
        case .onMiss: "允许列表未命中时询问"
        case .always: "始终询问"
        }
    }
}

/// 执行批准决策
enum ExecApprovalDecision: String, Codable, Sendable {
    case allowOnce = "allow-once"
    case allowAlways = "allow-always"
    case deny
}

/// 执行允许列表条目
struct ExecAllowlistEntry: Codable, Hashable, Identifiable {
    var id: UUID
    var pattern: String
    var lastUsedAt: Double?
    var lastUsedCommand: String?
    var lastResolvedPath: String?

    init(
        id: UUID = UUID(),
        pattern: String,
        lastUsedAt: Double? = nil,
        lastUsedCommand: String? = nil,
        lastResolvedPath: String? = nil)
    {
        self.id = id
        self.pattern = pattern
        self.lastUsedAt = lastUsedAt
        self.lastUsedCommand = lastUsedCommand
        self.lastResolvedPath = lastResolvedPath
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case pattern
        case lastUsedAt
        case lastUsedCommand
        case lastResolvedPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.pattern = try container.decode(String.self, forKey: .pattern)
        self.lastUsedAt = try container.decodeIfPresent(Double.self, forKey: .lastUsedAt)
        self.lastUsedCommand = try container.decodeIfPresent(String.self, forKey: .lastUsedCommand)
        self.lastResolvedPath = try container.decodeIfPresent(String.self, forKey: .lastResolvedPath)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.id, forKey: .id)
        try container.encode(self.pattern, forKey: .pattern)
        try container.encodeIfPresent(self.lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(self.lastUsedCommand, forKey: .lastUsedCommand)
        try container.encodeIfPresent(self.lastResolvedPath, forKey: .lastResolvedPath)
    }
}

/// 执行批准默认设置
struct ExecApprovalsDefaults: Codable {
    var security: ExecSecurity?
    var ask: ExecAsk?
    var askFallback: ExecSecurity?
    var autoAllowSkills: Bool?
}

/// 执行批准代理设置
struct ExecApprovalsAgent: Codable {
    var security: ExecSecurity?
    var ask: ExecAsk?
    var askFallback: ExecSecurity?
    var autoAllowSkills: Bool?
    var allowlist: [ExecAllowlistEntry]?

    /// 是否为空
    var isEmpty: Bool {
        self.security == nil && self.ask == nil && self.askFallback == nil && self
            .autoAllowSkills == nil && (self.allowlist?.isEmpty ?? true)
    }
}

/// 执行批准套接字配置
struct ExecApprovalsSocketConfig: Codable {
    var path: String?
    var token: String?
}

/// 执行批准文件
struct ExecApprovalsFile: Codable {
    var version: Int
    var socket: ExecApprovalsSocketConfig?
    var defaults: ExecApprovalsDefaults?
    var agents: [String: ExecApprovalsAgent]?
}

/// 执行批准快照
struct ExecApprovalsSnapshot: Codable {
    var path: String
    var exists: Bool
    var hash: String
    var file: ExecApprovalsFile
}

/// 执行批准解析结果
struct ExecApprovalsResolved {
    let url: URL
    let socketPath: String
    let token: String
    let defaults: ExecApprovalsResolvedDefaults
    let agent: ExecApprovalsResolvedDefaults
    let allowlist: [ExecAllowlistEntry]
    var file: ExecApprovalsFile
}

/// 执行批准解析的默认设置
struct ExecApprovalsResolvedDefaults {
    var security: ExecSecurity
    var ask: ExecAsk
    var askFallback: ExecSecurity
    var autoAllowSkills: Bool
}

/// 执行批准存储
enum ExecApprovalsStore {
    private static let logger = Logger(subsystem: "bot.molt", category: "exec-approvals")
    private static let defaultAgentId = "main"
    private static let defaultSecurity: ExecSecurity = .deny
    private static let defaultAsk: ExecAsk = .onMiss
    private static let defaultAskFallback: ExecSecurity = .deny
    private static let defaultAutoAllowSkills = false

    /// 获取文件URL
    static func fileURL() -> URL {
        MoltbotPaths.stateDirURL.appendingPathComponent("exec-approvals.json")
    }

    /// 获取套接字路径
    static func socketPath() -> String {
        MoltbotPaths.stateDirURL.appendingPathComponent("exec-approvals.sock").path
    }

    /// 规范化传入的文件
    static func normalizeIncoming(_ file: ExecApprovalsFile) -> ExecApprovalsFile {
        let socketPath = file.socket?.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = file.socket?.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var agents = file.agents ?? [:]
        if let legacyDefault = agents["default"] {
            if let main = agents[self.defaultAgentId] {
                agents[self.defaultAgentId] = self.mergeAgents(current: main, legacy: legacyDefault)
            } else {
                agents[self.defaultAgentId] = legacyDefault
            }
            agents.removeValue(forKey: "default")
        }
        return ExecApprovalsFile(
            version: 1,
            socket: ExecApprovalsSocketConfig(
                path: socketPath.isEmpty ? nil : socketPath,
                token: token.isEmpty ? nil : token),
            defaults: file.defaults,
            agents: agents)
    }

    /// 读取快照
    static func readSnapshot() -> ExecApprovalsSnapshot {
        let url = self.fileURL()
        guard FileManager().fileExists(atPath: url.path) else {
            return ExecApprovalsSnapshot(
                path: url.path,
                exists: false,
                hash: self.hashRaw(nil),
                file: ExecApprovalsFile(version: 1, socket: nil, defaults: nil, agents: [:]))
        }
        let raw = try? String(contentsOf: url, encoding: .utf8)
        let data = raw.flatMap { $0.data(using: .utf8) }
        let decoded: ExecApprovalsFile = {
            if let data, let file = try? JSONDecoder().decode(ExecApprovalsFile.self, from: data), file.version == 1 {
                return file
            }
            return ExecApprovalsFile(version: 1, socket: nil, defaults: nil, agents: [:])
        }()
        return ExecApprovalsSnapshot(
            path: url.path,
            exists: true,
            hash: self.hashRaw(raw),
            file: decoded)
    }

    /// 为快照脱敏
    static func redactForSnapshot(_ file: ExecApprovalsFile) -> ExecApprovalsFile {
        let socketPath = file.socket?.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if socketPath.isEmpty {
            return ExecApprovalsFile(
                version: file.version,
                socket: nil,
                defaults: file.defaults,
                agents: file.agents)
        }
        return ExecApprovalsFile(
            version: file.version,
            socket: ExecApprovalsSocketConfig(path: socketPath, token: nil),
            defaults: file.defaults,
            agents: file.agents)
    }

    /// 加载文件
    static func loadFile() -> ExecApprovalsFile {
        let url = self.fileURL()
        guard FileManager().fileExists(atPath: url.path) else {
            return ExecApprovalsFile(version: 1, socket: nil, defaults: nil, agents: [:])
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(ExecApprovalsFile.self, from: data)
            if decoded.version != 1 {
                return ExecApprovalsFile(version: 1, socket: nil, defaults: nil, agents: [:])
            }
            return decoded
        } catch {
            self.logger.warning("exec approvals load failed: \(error.localizedDescription, privacy: .public)")
            return ExecApprovalsFile(version: 1, socket: nil, defaults: nil, agents: [:])
        }
    }

    /// 保存文件
    static func saveFile(_ file: ExecApprovalsFile) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(file)
            let url = self.fileURL()
            try FileManager().createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try? FileManager().setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            self.logger.error("exec approvals save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 确保文件存在
    static func ensureFile() -> ExecApprovalsFile {
        var file = self.loadFile()
        if file.socket == nil { file.socket = ExecApprovalsSocketConfig(path: nil, token: nil) }
        let path = file.socket?.path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if path.isEmpty {
            file.socket?.path = self.socketPath()
        }
        let token = file.socket?.token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if token.isEmpty {
            file.socket?.token = self.generateToken()
        }
        if file.agents == nil { file.agents = [:] }
        self.saveFile(file)
        return file
    }

    /// 解析代理设置
    static func resolve(agentId: String?) -> ExecApprovalsResolved {
        let file = self.ensureFile()
        let defaults = file.defaults ?? ExecApprovalsDefaults()
        let resolvedDefaults = ExecApprovalsResolvedDefaults(
            security: defaults.security ?? self.defaultSecurity,
            ask: defaults.ask ?? self.defaultAsk,
            askFallback: defaults.askFallback ?? self.defaultAskFallback,
            autoAllowSkills: defaults.autoAllowSkills ?? self.defaultAutoAllowSkills)
        let key = self.agentKey(agentId)
        let agentEntry = file.agents?[key] ?? ExecApprovalsAgent()
        let wildcardEntry = file.agents?["*"] ?? ExecApprovalsAgent()
        let resolvedAgent = ExecApprovalsResolvedDefaults(
            security: agentEntry.security ?? wildcardEntry.security ?? resolvedDefaults.security,
            ask: agentEntry.ask ?? wildcardEntry.ask ?? resolvedDefaults.ask,
            askFallback: agentEntry.askFallback ?? wildcardEntry.askFallback
                ?? resolvedDefaults.askFallback,
            autoAllowSkills: agentEntry.autoAllowSkills ?? wildcardEntry.autoAllowSkills
                ?? resolvedDefaults.autoAllowSkills)
        let allowlist = ((wildcardEntry.allowlist ?? []) + (agentEntry.allowlist ?? []))
            .map { entry in
                ExecAllowlistEntry(
                    id: entry.id,
                    pattern: entry.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastUsedAt: entry.lastUsedAt,
                    lastUsedCommand: entry.lastUsedCommand,
                    lastResolvedPath: entry.lastResolvedPath)
            }
            .filter { !$0.pattern.isEmpty }
        let socketPath = self.expandPath(file.socket?.path ?? self.socketPath())
        let token = file.socket?.token ?? ""
        return ExecApprovalsResolved(
            url: self.fileURL(),
            socketPath: socketPath,
            token: token,
            defaults: resolvedDefaults,
            agent: resolvedAgent,
            allowlist: allowlist,
            file: file)
    }

    /// 解析默认设置
    static func resolveDefaults() -> ExecApprovalsResolvedDefaults {
        let file = self.ensureFile()
        let defaults = file.defaults ?? ExecApprovalsDefaults()
        return ExecApprovalsResolvedDefaults(
            security: defaults.security ?? self.defaultSecurity,
            ask: defaults.ask ?? self.defaultAsk,
            askFallback: defaults.askFallback ?? self.defaultAskFallback,
            autoAllowSkills: defaults.autoAllowSkills ?? self.defaultAutoAllowSkills)
    }

    /// 保存默认设置
    static func saveDefaults(_ defaults: ExecApprovalsDefaults) {
        self.updateFile { file in
            file.defaults = defaults
        }
    }

    /// 更新默认设置
    static func updateDefaults(_ mutate: (inout ExecApprovalsDefaults) -> Void) {
        self.updateFile { file in
            var defaults = file.defaults ?? ExecApprovalsDefaults()
            mutate(&defaults)
            file.defaults = defaults
        }
    }

    /// 保存代理设置
    static func saveAgent(_ agent: ExecApprovalsAgent, agentId: String?) {
        self.updateFile { file in
            var agents = file.agents ?? [:]
            let key = self.agentKey(agentId)
            if agent.isEmpty {
                agents.removeValue(forKey: key)
            } else {
                agents[key] = agent
            }
            file.agents = agents.isEmpty ? nil : agents
        }
    }

    /// 添加允许列表条目
    static func addAllowlistEntry(agentId: String?, pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        self.updateFile { file in
            let key = self.agentKey(agentId)
            var agents = file.agents ?? [:]
            var entry = agents[key] ?? ExecApprovalsAgent()
            var allowlist = entry.allowlist ?? []
            if allowlist.contains(where: { $0.pattern == trimmed }) { return }
            allowlist.append(ExecAllowlistEntry(pattern: trimmed, lastUsedAt: Date().timeIntervalSince1970 * 1000))
            entry.allowlist = allowlist
            agents[key] = entry
            file.agents = agents
        }
    }

    /// 记录允许列表使用
    static func recordAllowlistUse(
        agentId: String?,
        pattern: String,
        command: String,
        resolvedPath: String?)
    {
        self.updateFile { file in
            let key = self.agentKey(agentId)
            var agents = file.agents ?? [:]
            var entry = agents[key] ?? ExecApprovalsAgent()
            let allowlist = (entry.allowlist ?? []).map { item -> ExecAllowlistEntry in
                guard item.pattern == pattern else { return item }
                return ExecAllowlistEntry(
                    id: item.id,
                    pattern: item.pattern,
                    lastUsedAt: Date().timeIntervalSince1970 * 1000,
                    lastUsedCommand: command,
                    lastResolvedPath: resolvedPath)
            }
            entry.allowlist = allowlist
            agents[key] = entry
            file.agents = agents
        }
    }

    /// 更新允许列表
    static func updateAllowlist(agentId: String?, allowlist: [ExecAllowlistEntry]) {
        self.updateFile { file in
            let key = self.agentKey(agentId)
            var agents = file.agents ?? [:]
            var entry = agents[key] ?? ExecApprovalsAgent()
            let cleaned = allowlist
                .map { item in
                    ExecAllowlistEntry(
                        id: item.id,
                        pattern: item.pattern.trimmingCharacters(in: .whitespacesAndNewlines),
                        lastUsedAt: item.lastUsedAt,
                        lastUsedCommand: item.lastUsedCommand,
                        lastResolvedPath: item.lastResolvedPath)
                }
                .filter { !$0.pattern.isEmpty }
            entry.allowlist = cleaned
            agents[key] = entry
            file.agents = agents
        }
    }

    /// 更新代理设置
    static func updateAgentSettings(agentId: String?, mutate: (inout ExecApprovalsAgent) -> Void) {
        self.updateFile { file in
            let key = self.agentKey(agentId)
            var agents = file.agents ?? [:]
            var entry = agents[key] ?? ExecApprovalsAgent()
            mutate(&entry)
            if entry.isEmpty {
                agents.removeValue(forKey: key)
            } else {
                agents[key] = entry
            }
            file.agents = agents.isEmpty ? nil : agents
        }
    }

    /// 更新文件
    private static func updateFile(_ mutate: (inout ExecApprovalsFile) -> Void) {
        var file = self.ensureFile()
        mutate(&file)
        self.saveFile(file)
    }

    /// 生成令牌
    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return UUID().uuidString
    }

    /// 计算原始字符串的哈希
    private static func hashRaw(_ raw: String?) -> String {
        let data = Data((raw ?? "").utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 展开路径
    private static func expandPath(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return FileManager().homeDirectoryForCurrentUser.path
        }
        if trimmed.hasPrefix("~/") {
            let suffix = trimmed.dropFirst(2)
            return FileManager().homeDirectoryForCurrentUser
                .appendingPathComponent(String(suffix)).path
        }
        return trimmed
    }

    /// 获取代理键
    private static func agentKey(_ agentId: String?) -> String {
        let trimmed = agentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? self.defaultAgentId : trimmed
    }

    /// 规范化模式
    private static func normalizedPattern(_ pattern: String?) -> String? {
        let trimmed = pattern?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    /// 合并代理设置
    private static func mergeAgents(
        current: ExecApprovalsAgent,
        legacy: ExecApprovalsAgent) -> ExecApprovalsAgent
    {
        var seen = Set<String>()
        var allowlist: [ExecAllowlistEntry] = []
        func append(_ entry: ExecAllowlistEntry) {
            guard let key = self.normalizedPattern(entry.pattern), !seen.contains(key) else {
                return
            }
            seen.insert(key)
            allowlist.append(entry)
        }
        for entry in current.allowlist ?? [] {
            append(entry)
        }
        for entry in legacy.allowlist ?? [] {
            append(entry)
        }

        return ExecApprovalsAgent(
            security: current.security ?? legacy.security,
            ask: current.ask ?? legacy.ask,
            askFallback: current.askFallback ?? legacy.askFallback,
            autoAllowSkills: current.autoAllowSkills ?? legacy.autoAllowSkills,
            allowlist: allowlist.isEmpty ? nil : allowlist)
    }
}

/// 执行命令解析结果
struct ExecCommandResolution: Sendable {
    let rawExecutable: String
    let resolvedPath: String?
    let executableName: String
    let cwd: String?

    /// 解析命令
    static func resolve(
        command: [String],
        rawCommand: String?,
        cwd: String?,
        env: [String: String]?) -> ExecCommandResolution?
    {
        let trimmedRaw = rawCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedRaw.isEmpty, let token = self.parseFirstToken(trimmedRaw) {
            return self.resolveExecutable(rawExecutable: token, cwd: cwd, env: env)
        }
        return self.resolve(command: command, cwd: cwd, env: env)
    }

    /// 解析命令数组
    static func resolve(command: [String], cwd: String?, env: [String: String]?) -> ExecCommandResolution? {
        guard let raw = command.first?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return self.resolveExecutable(rawExecutable: raw, cwd: cwd, env: env)
    }

    /// 解析可执行文件
    private static func resolveExecutable(
        rawExecutable: String,
        cwd: String?,
        env: [String: String]?) -> ExecCommandResolution?
    {
        let expanded = rawExecutable.hasPrefix("~") ? (rawExecutable as NSString).expandingTildeInPath : rawExecutable
        let hasPathSeparator = expanded.contains("/") || expanded.contains("\\")
        let resolvedPath: String? = {
            if hasPathSeparator {
                if expanded.hasPrefix("/") {
                    return expanded
                }
                let base = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
                let root = (base?.isEmpty == false) ? base! : FileManager().currentDirectoryPath
                return URL(fileURLWithPath: root).appendingPathComponent(expanded).path
            }
            let searchPaths = self.searchPaths(from: env)
            return CommandResolver.findExecutable(named: expanded, searchPaths: searchPaths)
        }()
        let name = resolvedPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? expanded
        return ExecCommandResolution(
            rawExecutable: expanded,
            resolvedPath: resolvedPath,
            executableName: name,
            cwd: cwd)
    }

    /// 解析第一个标记
    private static func parseFirstToken(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let first = trimmed.first else { return nil }
        if first == "\"" || first == "'" {
            let rest = trimmed.dropFirst()
            if let end = rest.firstIndex(of: first) {
                return String(rest[..<end])
            }
            return String(rest)
        }
        return trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
    }

    /// 从环境变量获取搜索路径
    private static func searchPaths(from env: [String: String]?) -> [String] {
        let raw = env?["PATH"]
        if let raw, !raw.isEmpty {
            return raw.split(separator: ":").map(String.init)
        }
        return CommandResolver.preferredPaths()
    }
}

/// 执行命令格式化器
enum ExecCommandFormatter {
    /// 获取显示字符串
    static func displayString(for argv: [String]) -> String {
        argv.map { arg in
            let trimmed = arg.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "\"\"" }
            let needsQuotes = trimmed.contains { $0.isWhitespace || $0 == "\"" }
            if !needsQuotes { return trimmed }
            let escaped = trimmed.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }.joined(separator: " ")
    }

    /// 获取显示字符串(带原始命令)
    static func displayString(for argv: [String], rawCommand: String?) -> String {
        let trimmed = rawCommand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return self.displayString(for: argv)
    }
}

/// 执行批准辅助工具
enum ExecApprovalHelpers {
    /// 解析决策
    static func parseDecision(_ raw: String?) -> ExecApprovalDecision? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return ExecApprovalDecision(rawValue: trimmed)
    }

    /// 是否需要询问
    static func requiresAsk(
        ask: ExecAsk,
        security: ExecSecurity,
        allowlistMatch: ExecAllowlistEntry?,
        skillAllow: Bool) -> Bool
    {
        if ask == .always { return true }
        if ask == .onMiss, security == .allowlist, allowlistMatch == nil, !skillAllow { return true }
        return false
    }

    /// 获取允许列表模式
    static func allowlistPattern(command: [String], resolution: ExecCommandResolution?) -> String? {
        let pattern = resolution?.resolvedPath ?? resolution?.rawExecutable ?? command.first ?? ""
        return pattern.isEmpty ? nil : pattern
    }
}

/// 执行允许列表匹配器
enum ExecAllowlistMatcher {
    /// 匹配条目
    static func match(entries: [ExecAllowlistEntry], resolution: ExecCommandResolution?) -> ExecAllowlistEntry? {
        guard let resolution, !entries.isEmpty else { return nil }
        let rawExecutable = resolution.rawExecutable
        let resolvedPath = resolution.resolvedPath
        let executableName = resolution.executableName

        for entry in entries {
            let pattern = entry.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            if pattern.isEmpty { continue }
            let hasPath = pattern.contains("/") || pattern.contains("~") || pattern.contains("\\")
            if hasPath {
                let target = resolvedPath ?? rawExecutable
                if self.matches(pattern: pattern, target: target) { return entry }
            } else if self.matches(pattern: pattern, target: executableName) {
                return entry
            }
        }
        return nil
    }

    /// 匹配模式和目标
    private static func matches(pattern: String, target: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let expanded = trimmed.hasPrefix("~") ? (trimmed as NSString).expandingTildeInPath : trimmed
        let normalizedPattern = self.normalizeMatchTarget(expanded)
        let normalizedTarget = self.normalizeMatchTarget(target)
        guard let regex = self.regex(for: normalizedPattern) else { return false }
        let range = NSRange(location: 0, length: normalizedTarget.utf16.count)
        return regex.firstMatch(in: normalizedTarget, options: [], range: range) != nil
    }

    /// 规范化匹配目标
    private static func normalizeMatchTarget(_ value: String) -> String {
        value.replacingOccurrences(of: "\\\\", with: "/").lowercased()
    }

    /// 创建正则表达式
    private static func regex(for pattern: String) -> NSRegularExpression? {
        var regex = "^"
        var idx = pattern.startIndex
        while idx < pattern.endIndex {
            let ch = pattern[idx]
            if ch == "*" {
                let next = pattern.index(after: idx)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    idx = pattern.index(after: next)
                } else {
                    regex += "[^/]*"
                    idx = next
                }
                continue
            }
            if ch == "?" {
                regex += "."
                idx = pattern.index(after: idx)
                continue
            }
            regex += NSRegularExpression.escapedPattern(for: String(ch))
            idx = pattern.index(after: idx)
        }
        regex += "$"
        return try? NSRegularExpression(pattern: regex, options: [.caseInsensitive])
    }
}

/// 执行事件负载
struct ExecEventPayload: Codable, Sendable {
    var sessionKey: String
    var runId: String
    var host: String
    var command: String?
    var exitCode: Int?
    var timedOut: Bool?
    var success: Bool?
    var output: String?
    var reason: String?

    /// 截断输出
    static func truncateOutput(_ raw: String, maxChars: Int = 20000) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxChars { return trimmed }
        let suffix = trimmed.suffix(maxChars)
        return "... (truncated) \(suffix)"
    }
}

/// 技能二进制文件缓存
actor SkillBinsCache {
    static let shared = SkillBinsCache()

    private var bins: Set<String> = []
    private var lastRefresh: Date?
    private let refreshInterval: TimeInterval = 90

    /// 获取当前二进制文件集合
    func currentBins(force: Bool = false) async -> Set<String> {
        if force || self.isStale() {
            await self.refresh()
        }
        return self.bins
    }

    /// 刷新缓存
    func refresh() async {
        do {
            let report = try await GatewayConnection.shared.skillsStatus()
            var next = Set<String>()
            for skill in report.skills {
                for bin in skill.requirements.bins {
                    let trimmed = bin.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { next.insert(trimmed) }
                }
            }
            self.bins = next
            self.lastRefresh = Date()
        } catch {
            if self.lastRefresh == nil {
                self.bins = []
            }
        }
    }

    /// 检查是否过期
    private func isStale() -> Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > self.refreshInterval
    }
}

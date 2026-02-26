import CryptoKit
import Foundation
import OSLog
import Security

/// Anthropic OAuth 凭证结构体
/// 用于编码和解码 OAuth 凭证数据
struct AnthropicOAuthCredentials: Codable {
    /// 凭证类型
    let type: String
    /// 刷新令牌
    let refresh: String
    /// 访问令牌
    let access: String
    /// 过期时间（毫秒）
    let expires: Int64
}

/// Anthropic 认证模式枚举
/// 定义了不同的认证方式和状态
enum AnthropicAuthMode: Equatable {
    /// 从文件读取 OAuth 凭证
    case oauthFile
    /// 从环境变量读取 OAuth 令牌
    case oauthEnv
    /// 从环境变量读取 API 密钥
    case apiKeyEnv
    /// 缺少凭证
    case missing

    /// 获取认证模式的简短标签
    var shortLabel: String {
        switch self {
        case .oauthFile: "OAuth (Moltbot 令牌文件)"
        case .oauthEnv: "OAuth (环境变量)"
        case .apiKeyEnv: "API 密钥 (环境变量)"
        case .missing: "缺少凭证"
        }
    }

    /// 检查认证是否已配置
    var isConfigured: Bool {
        switch self {
        case .missing: false
        case .oauthFile, .oauthEnv, .apiKeyEnv: true
        }
    }
}

/// Anthropic 认证解析器
/// 用于解析和确定当前的认证模式
enum AnthropicAuthResolver {
    /// 解析认证模式
    /// 
    /// - Parameters:
    ///   - environment: 环境变量字典，默认为当前进程的环境变量
    ///   - oauthStatus: OAuth 状态，默认为从存储中获取的状态
    /// - Returns: 解析后的认证模式
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        oauthStatus: MoltbotOAuthStore.AnthropicOAuthStatus = MoltbotOAuthStore
            .anthropicOAuthStatus()) -> AnthropicAuthMode
    {
        // 检查是否已从文件连接
        if oauthStatus.isConnected { return .oauthFile }

        // 检查环境变量中的 OAuth 令牌
        if let token = environment["ANTHROPIC_OAUTH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty
        {
            return .oauthEnv
        }

        // 检查环境变量中的 API 密钥
        if let key = environment["ANTHROPIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty
        {
            return .apiKeyEnv
        }

        // 缺少凭证
        return .missing
    }
}

/// Anthropic OAuth 处理
/// 提供 OAuth 认证流程的核心功能
enum AnthropicOAuth {
    private static let logger = Logger(subsystem: "bot.molt", category: "anthropic-oauth")

    /// OAuth 配置常量
    private static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"

    /// PKCE (Proof Key for Code Exchange) 结构体
    /// 用于 OAuth 认证过程中的安全验证
    struct PKCE {
        /// 验证器字符串
        let verifier: String
        /// 挑战码字符串（验证器的哈希值）
        let challenge: String
    }

    /// 生成 PKCE 验证器和挑战码
    /// 
    /// - Returns: 生成的 PKCE 对象
    /// - Throws: 生成随机数失败时抛出错误
    static func generatePKCE() throws -> PKCE {
        // 生成 32 字节随机数
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        
        // 生成验证器（base64 URL 编码）
        let verifier = Data(bytes).base64URLEncodedString()
        // 生成挑战码（验证器的 SHA256 哈希值，再进行 base64 URL 编码）
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64URLEncodedString()
        
        return PKCE(verifier: verifier, challenge: challenge)
    }

    /// 构建授权 URL
    /// 
    /// - Parameter pkce: PKCE 对象，包含验证器和挑战码
    /// - Returns: 构建好的授权 URL
    static func buildAuthorizeURL(pkce: PKCE) -> URL {
        var components = URLComponents(url: self.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: self.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: self.redirectURI),
            URLQueryItem(name: "scope", value: self.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // 与旧流程匹配：state 参数使用验证器
            URLQueryItem(name: "state", value: pkce.verifier),
        ]
        return components.url!
    }

    /// 交换授权码获取凭证
    /// 
    /// - Parameters:
    ///   - code: 授权码
    ///   - state: 状态参数
    ///   - verifier: PKCE 验证器
    /// - Returns: 获取的 OAuth 凭证
    /// - Throws: 网络请求失败或响应解析失败时抛出错误
    static func exchangeCode(
        code: String,
        state: String,
        verifier: String) async throws -> AnthropicOAuthCredentials
    {
        // 构建请求体
        let payload: [String: Any] = [
            "grant_type": "authorization_code",
            "client_id": self.clientId,
            "code": code,
            "state": state,
            "redirect_uri": self.redirectURI,
            "code_verifier": verifier,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        // 构建请求
        var request = URLRequest(url: self.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 发送请求并获取响应
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // 检查响应状态码
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(
                domain: "AnthropicOAuth",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "令牌交换失败: \(text)"])
        }

        // 解析响应数据
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let access = decoded?["access_token"] as? String
        let refresh = decoded?["refresh_token"] as? String
        let expiresIn = decoded?["expires_in"] as? Double
        guard let access, let refresh, let expiresIn else {
            throw NSError(domain: "AnthropicOAuth", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "意外的令牌响应。",
            ])
        }

        // 计算过期时间：当前时间 + 过期时间 - 5 分钟（预留时间）
        let expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            + Int64(expiresIn * 1000)
            - Int64(5 * 60 * 1000)

        // 记录日志
        self.logger.info("Anthropic OAuth 交换成功; expiresAtMs=\(expiresAtMs, privacy: .public)")
        return AnthropicOAuthCredentials(type: "oauth", refresh: refresh, access: access, expires: expiresAtMs)
    }

    /// 使用刷新令牌刷新凭证
    /// 
    /// - Parameter refreshToken: 刷新令牌
    /// - Returns: 刷新后的 OAuth 凭证
    /// - Throws: 网络请求失败或响应解析失败时抛出错误
    static func refresh(refreshToken: String) async throws -> AnthropicOAuthCredentials {
        // 构建请求体
        let payload: [String: Any] = [
            "grant_type": "refresh_token",
            "client_id": self.clientId,
            "refresh_token": refreshToken,
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])

        // 构建请求
        var request = URLRequest(url: self.tokenURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 发送请求并获取响应
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        // 检查响应状态码
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw NSError(
                domain: "AnthropicOAuth",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "令牌刷新失败: \(text)"])
        }

        // 解析响应数据
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let access = decoded?["access_token"] as? String
        let refresh = (decoded?["refresh_token"] as? String) ?? refreshToken
        let expiresIn = decoded?["expires_in"] as? Double
        guard let access, let expiresIn else {
            throw NSError(domain: "AnthropicOAuth", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "意外的令牌响应。",
            ])
        }

        // 计算过期时间：当前时间 + 过期时间 - 5 分钟（预留时间）
        let expiresAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            + Int64(expiresIn * 1000)
            - Int64(5 * 60 * 1000)

        // 记录日志
        self.logger.info("Anthropic OAuth 刷新成功; expiresAtMs=\(expiresAtMs, privacy: .public)")
        return AnthropicOAuthCredentials(type: "oauth", refresh: refresh, access: access, expires: expiresAtMs)
    }
}

/// Moltbot OAuth 存储管理
/// 用于管理 OAuth 凭证的存储和读取
enum MoltbotOAuthStore {
    /// OAuth 文件名
    static let oauthFilename = "oauth.json"
    /// 提供商键名
    private static let providerKey = "anthropic"
    /// Moltbot OAuth 目录环境变量
    private static let moltbotOAuthDirEnv = "CLAWDBOT_OAUTH_DIR"
    /// 旧版 PI 目录环境变量
    private static let legacyPiDirEnv = "PI_CODING_AGENT_DIR"

    /// Anthropic OAuth 状态枚举
    enum AnthropicOAuthStatus: Equatable {
        /// 文件缺失
        case missingFile
        /// 文件不可读
        case unreadableFile
        /// JSON 无效
        case invalidJSON
        /// 缺少提供商条目
        case missingProviderEntry
        /// 缺少令牌
        case missingTokens
        /// 已连接（带过期时间）
        case connected(expiresAtMs: Int64?)

        /// 检查是否已连接
        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }

        /// 获取简短描述
        var shortDescription: String {
            switch self {
            case .missingFile: "未找到 Moltbot OAuth 令牌文件"
        case .unreadableFile: "Moltbot OAuth 令牌文件不可读"
        case .invalidJSON: "Moltbot OAuth 令牌文件无效"
        case .missingProviderEntry: "Moltbot OAuth 令牌文件中缺少 Anthropic 条目"
        case .missingTokens: "Anthropic 条目缺少令牌"
        case .connected: "找到 Moltbot OAuth 凭证"
            }
        }
    }

    /// 获取 OAuth 目录
    /// 
    /// - Returns: OAuth 目录的 URL
    static func oauthDir() -> URL {
        // 检查环境变量覆盖
        if let override = ProcessInfo.processInfo.environment[self.moltbotOAuthDirEnv]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !override.isEmpty
        {
            let expanded = NSString(string: override).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }

        // 默认目录：~/.clawdbot/credentials
        return FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(".clawdbot", isDirectory: true)
            .appendingPathComponent("credentials", isDirectory: true)
    }

    /// 获取 OAuth 文件 URL
    /// 
    /// - Returns: OAuth 文件的 URL
    static func oauthURL() -> URL {
        self.oauthDir().appendingPathComponent(self.oauthFilename)
    }

    /// 获取旧版 OAuth 文件 URL 列表
    /// 
    /// - Returns: 旧版 OAuth 文件的 URL 列表
    static func legacyOAuthURLs() -> [URL] {
        var urls: [URL] = []
        let env = ProcessInfo.processInfo.environment
        
        // 检查旧版 PI 目录环境变量
        if let override = env[self.legacyPiDirEnv]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            let expanded = NSString(string: override).expandingTildeInPath
            urls.append(URL(fileURLWithPath: expanded, isDirectory: true).appendingPathComponent(self.oauthFilename))
        }

        // 检查常见的旧版路径
        let home = FileManager().homeDirectoryForCurrentUser
        urls.append(home.appendingPathComponent(".pi/agent/\(self.oauthFilename)"))
        urls.append(home.appendingPathComponent(".claude/\(self.oauthFilename)"))
        urls.append(home.appendingPathComponent(".config/claude/\(self.oauthFilename)"))
        urls.append(home.appendingPathComponent(".config/anthropic/\(self.oauthFilename)"))

        // 去重
        var seen = Set<String>()
        return urls.filter { url in
            let path = url.standardizedFileURL.path
            if seen.contains(path) { return false }
            seen.insert(path)
            return true
        }
    }

    /// 导入旧版 Anthropic OAuth 凭证（如果需要）
    /// 
    /// - Returns: 导入的旧版文件 URL，导入失败返回 nil
    static func importLegacyAnthropicOAuthIfNeeded() -> URL? {
        let dest = self.oauthURL()
        // 如果目标文件已存在，跳过导入
        guard !FileManager().fileExists(atPath: dest.path) else { return nil }

        // 尝试从旧版路径导入
        for url in self.legacyOAuthURLs() {
            // 检查文件是否存在
            guard FileManager().fileExists(atPath: url.path) else { continue }
            // 检查是否已连接
            guard self.anthropicOAuthStatus(at: url).isConnected else { continue }
            // 加载存储
            guard let storage = self.loadStorage(at: url) else { continue }
            
            // 保存到新位置
            do {
                try self.saveStorage(storage)
                return url
            } catch {
                continue
            }
        }

        return nil
    }

    /// 获取 Anthropic OAuth 状态
    /// 
    /// - Returns: Anthropic OAuth 状态
    static func anthropicOAuthStatus() -> AnthropicOAuthStatus {
        self.anthropicOAuthStatus(at: self.oauthURL())
    }

    /// 检查是否有 Anthropic OAuth 凭证
    /// 
    /// - Returns: 如果有凭证返回 true，否则返回 false
    static func hasAnthropicOAuth() -> Bool {
        self.anthropicOAuthStatus().isConnected
    }

    /// 获取指定 URL 的 Anthropic OAuth 状态
    /// 
    /// - Parameter url: 要检查的文件 URL
    /// - Returns: Anthropic OAuth 状态
    static func anthropicOAuthStatus(at url: URL) -> AnthropicOAuthStatus {
        // 检查文件是否存在
        guard FileManager().fileExists(atPath: url.path) else { return .missingFile }

        // 尝试读取文件
        guard let data = try? Data(contentsOf: url) else { return .unreadableFile }
        // 尝试解析 JSON
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return .invalidJSON }
        // 尝试转换为字典
        guard let storage = json as? [String: Any] else { return .invalidJSON }
        // 检查是否有 Anthropic 条目
        guard let rawEntry = storage[self.providerKey] else { return .missingProviderEntry }
        // 尝试转换为字典
        guard let entry = rawEntry as? [String: Any] else { return .invalidJSON }

        // 尝试获取刷新令牌和访问令牌
        let refresh = self.firstString(in: entry, keys: ["refresh", "refresh_token", "refreshToken"])
        let access = self.firstString(in: entry, keys: ["access", "access_token", "accessToken"])
        guard refresh?.isEmpty == false, access?.isEmpty == false else { return .missingTokens }

        // 尝试获取过期时间
        let expiresAny = entry["expires"] ?? entry["expires_at"] ?? entry["expiresAt"]
        let expiresAtMs: Int64? = if let ms = expiresAny as? Int64 {
            ms
        } else if let number = expiresAny as? NSNumber {
            number.int64Value
        } else if let ms = expiresAny as? Double {
            Int64(ms)
        } else {
            nil
        }

        return .connected(expiresAtMs: expiresAtMs)
    }

    /// 加载 Anthropic OAuth 刷新令牌
    /// 
    /// - Returns: 刷新令牌字符串，加载失败返回 nil
    static func loadAnthropicOAuthRefreshToken() -> String? {
        let url = self.oauthURL()
        guard let storage = self.loadStorage(at: url) else { return nil }
        guard let rawEntry = storage[self.providerKey] as? [String: Any] else { return nil }
        let refresh = self.firstString(in: rawEntry, keys: ["refresh", "refresh_token", "refreshToken"])
        return refresh?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从字典中获取第一个存在的字符串值
    /// 
    /// - Parameters:
    ///   - dict: 要搜索的字典
    ///   - keys: 要尝试的键数组
    /// - Returns: 找到的第一个字符串值，未找到返回 nil
    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String { return value }
        }
        return nil
    }

    /// 加载存储
    /// 
    /// - Parameter url: 存储文件的 URL
    /// - Returns: 加载的存储字典，加载失败返回 nil
    private static func loadStorage(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
        return json as? [String: Any]
    }

    /// 保存 Anthropic OAuth 凭证
    /// 
    /// - Parameter creds: 要保存的 OAuth 凭证
    /// - Throws: 保存失败时抛出错误
    static func saveAnthropicOAuth(_ creds: AnthropicOAuthCredentials) throws {
        let url = self.oauthURL()
        // 加载现有存储
        let existing: [String: Any] = self.loadStorage(at: url) ?? [:]

        // 更新存储
        var updated = existing
        updated[self.providerKey] = [
            "type": creds.type,
            "refresh": creds.refresh,
            "access": creds.access,
            "expires": creds.expires,
        ]

        // 保存存储
        try self.saveStorage(updated)
    }

    /// 保存存储
    /// 
    /// - Parameter storage: 要保存的存储字典
    /// - Throws: 保存失败时抛出错误
    private static func saveStorage(_ storage: [String: Any]) throws {
        let dir = self.oauthDir()
        // 创建目录（如果不存在），设置权限为 700
        try FileManager().createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])

        let url = self.oauthURL()
        // 序列化 JSON
        let data = try JSONSerialization.data(
            withJSONObject: storage,
            options: [.prettyPrinted, .sortedKeys])
        // 写入文件
        try data.write(to: url, options: [.atomic])
        // 设置文件权限（仅所有者可读写）
        try FileManager().setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// Data 扩展，用于生成 base64 URL 编码字符串
extension Data {
    /// 生成 base64 URL 编码字符串
    /// 
    /// - Returns: base64 URL 编码的字符串
    fileprivate func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

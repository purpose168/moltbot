import CryptoKit
import Foundation

/// 设备身份结构体，用于存储设备的唯一标识和加密密钥信息
public struct DeviceIdentity: Codable, Sendable {
    /// 设备唯一标识符
    public var deviceId: String
    /// 公钥（Base64编码）
    public var publicKey: String
    /// 私钥（Base64编码）
    public var privateKey: String
    /// 创建时间戳（毫秒）
    public var createdAtMs: Int

    /// 初始化设备身份
    /// - Parameters:
    ///   - deviceId: 设备唯一标识符
    ///   - publicKey: 公钥（Base64编码）
    ///   - privateKey: 私钥（Base64编码）
    ///   - createdAtMs: 创建时间戳（毫秒）
    public init(deviceId: String, publicKey: String, privateKey: String, createdAtMs: Int) {
        self.deviceId = deviceId
        self.publicKey = publicKey
        self.privateKey = privateKey
        self.createdAtMs = createdAtMs
    }
}

/// 设备身份存储路径管理
enum DeviceIdentityPaths {
    /// 状态目录环境变量名
    private static let stateDirEnv = "CLAWDBOT_STATE_DIR"

    /// 获取状态目录URL
    /// - Returns: 状态目录的URL路径
    static func stateDirURL() -> URL {
        // 首先检查环境变量是否设置
        if let raw = getenv(self.stateDirEnv) {
            let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
        }

        // 其次尝试使用应用支持目录
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return appSupport.appendingPathComponent("moltbot", isDirectory: true)
        }

        // 最后使用临时目录作为备选
        return FileManager.default.temporaryDirectory.appendingPathComponent("moltbot", isDirectory: true)
    }
}

/// 设备身份存储管理
public enum DeviceIdentityStore {
    /// 设备身份文件名
    private static let fileName = "device.json"

    /// 加载或创建设备身份
    /// - Returns: 设备身份对象
    public static func loadOrCreate() -> DeviceIdentity {
        let url = self.fileURL()
        // 尝试从文件加载已存在的设备身份
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(DeviceIdentity.self, from: data),
           !decoded.deviceId.isEmpty,
           !decoded.publicKey.isEmpty,
           !decoded.privateKey.isEmpty {
            return decoded
        }
        // 如果加载失败，生成新的设备身份并保存
        let identity = self.generate()
        self.save(identity)
        return identity
    }

    /// 使用设备私钥对数据进行签名
    /// - Parameters:
    ///   - payload: 需要签名的数据
    ///   - identity: 设备身份对象
    /// - Returns: 签名结果（Base64URL编码），如果签名失败则返回nil
    public static func signPayload(_ payload: String, identity: DeviceIdentity) -> String? {
        guard let privateKeyData = Data(base64Encoded: identity.privateKey) else { return nil }
        do {
            let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
            let signature = try privateKey.signature(for: Data(payload.utf8))
            return self.base64UrlEncode(signature)
        } catch {
            return nil
        }
    }

    /// 生成新的设备身份
    /// - Returns: 新生成的设备身份对象
    private static func generate() -> DeviceIdentity {
        // 生成Curve25519签名密钥对
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey
        let publicKeyData = publicKey.rawRepresentation
        let privateKeyData = privateKey.rawRepresentation
        // 使用公钥的SHA256哈希作为设备ID
        let deviceId = SHA256.hash(data: publicKeyData).compactMap { String(format: "%02x", $0) }.joined()
        return DeviceIdentity(
            deviceId: deviceId,
            publicKey: publicKeyData.base64EncodedString(),
            privateKey: privateKeyData.base64EncodedString(),
            createdAtMs: Int(Date().timeIntervalSince1970 * 1000))
    }

    /// 将数据编码为Base64URL格式
    /// - Parameter data: 需要编码的数据
    /// - Returns: Base64URL编码后的字符串
    private static func base64UrlEncode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 获取设备公钥的Base64URL编码
    /// - Parameter identity: 设备身份对象
    /// - Returns: Base64URL编码的公钥，失败则返回nil
    public static func publicKeyBase64Url(_ identity: DeviceIdentity) -> String? {
        guard let data = Data(base64Encoded: identity.publicKey) else { return nil }
        return self.base64UrlEncode(data)
    }

    /// 保存设备身份到文件
    /// - Parameter identity: 需要保存的设备身份对象
    private static func save(_ identity: DeviceIdentity) {
        let url = self.fileURL()
        do {
            // 确保目录存在
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            // 编码并写入文件
            let data = try JSONEncoder().encode(identity)
            try data.write(to: url, options: [.atomic])
        } catch {
            // 仅做最大努力尝试，失败不抛出异常
        }
    }

    /// 获取设备身份文件的URL路径
    /// - Returns: 设备身份文件的URL
    private static func fileURL() -> URL {
        let base = DeviceIdentityPaths.stateDirURL()
        return base
            .appendingPathComponent("identity", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

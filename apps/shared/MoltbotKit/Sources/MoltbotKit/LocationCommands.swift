import Foundation

/// 位置命令枚举，定义了可执行的位置相关操作
public enum MoltbotLocationCommand: String, Codable, Sendable {
    /// 获取当前位置命令
    case get = "location.get"
}

/// 位置精度枚举，定义了不同级别的位置精度
public enum MoltbotLocationAccuracy: String, Codable, Sendable {
    /// 粗略精度
    case coarse
    /// 平衡精度
    case balanced
    /// 精确精度
    case precise
}

/// 获取位置参数结构体，包含获取位置时的配置选项
public struct MoltbotLocationGetParams: Codable, Sendable, Equatable {
    /// 超时时间（毫秒）
    public var timeoutMs: Int?
    /// 最大缓存时间（毫秒）
    public var maxAgeMs: Int?
    /// 期望的位置精度
    public var desiredAccuracy: MoltbotLocationAccuracy?

    /// 初始化获取位置参数
    /// - Parameters:
    ///   - timeoutMs: 超时时间（毫秒）
    ///   - maxAgeMs: 最大缓存时间（毫秒）
    ///   - desiredAccuracy: 期望的位置精度
    public init(timeoutMs: Int? = nil, maxAgeMs: Int? = nil, desiredAccuracy: MoltbotLocationAccuracy? = nil) {
        self.timeoutMs = timeoutMs
        self.maxAgeMs = maxAgeMs
        self.desiredAccuracy = desiredAccuracy
    }
}

/// 位置信息载荷结构体，包含获取到的位置详细信息
public struct MoltbotLocationPayload: Codable, Sendable, Equatable {
    /// 纬度
    public var lat: Double
    /// 经度
    public var lon: Double
    /// 精度（米）
    public var accuracyMeters: Double
    /// 海拔高度（米）
    public var altitudeMeters: Double?
    /// 速度（米/秒）
    public var speedMps: Double?
    /// 航向（度）
    public var headingDeg: Double?
    /// 时间戳
    public var timestamp: String
    /// 是否为精确位置
    public var isPrecise: Bool
    /// 位置来源
    public var source: String?

    /// 初始化位置信息载荷
    /// - Parameters:
    ///   - lat: 纬度
    ///   - lon: 经度
    ///   - accuracyMeters: 精度（米）
    ///   - altitudeMeters: 海拔高度（米）
    ///   - speedMps: 速度（米/秒）
    ///   - headingDeg: 航向（度）
    ///   - timestamp: 时间戳
    ///   - isPrecise: 是否为精确位置
    ///   - source: 位置来源
    public init(
        lat: Double,
        lon: Double,
        accuracyMeters: Double,
        altitudeMeters: Double? = nil,
        speedMps: Double? = nil,
        headingDeg: Double? = nil,
        timestamp: String,
        isPrecise: Bool,
        source: String? = nil)
    {
        self.lat = lat
        self.lon = lon
        self.accuracyMeters = accuracyMeters
        self.altitudeMeters = altitudeMeters
        self.speedMps = speedMps
        self.headingDeg = headingDeg
        self.timestamp = timestamp
        self.isPrecise = isPrecise
        self.source = source
    }
}

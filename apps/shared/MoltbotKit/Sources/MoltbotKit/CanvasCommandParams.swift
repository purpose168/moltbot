import Foundation

/// 用于导航到指定 URL 的参数结构体
/// - 实现了 Codable、Sendable 和 Equatable 协议
public struct MoltbotCanvasNavigateParams: Codable, Sendable, Equatable {
    /// 要导航到的 URL 字符串
    public var url: String

    /// 初始化方法
    /// - Parameter url: 要导航到的 URL 字符串
    public init(url: String) {
        self.url = url
    }
}

/// 用于指定 Canvas 位置和大小的结构体
/// - 实现了 Codable、Sendable 和 Equatable 协议
public struct MoltbotCanvasPlacement: Codable, Sendable, Equatable {
    /// X 坐标位置（可选）
    public var x: Double?
    /// Y 坐标位置（可选）
    public var y: Double?
    /// 宽度（可选）
    public var width: Double?
    /// 高度（可选）
    public var height: Double?

    /// 初始化方法
    /// - Parameters:
    ///   - x: X 坐标位置（默认 nil）
    ///   - y: Y 坐标位置（默认 nil）
    ///   - width: 宽度（默认 nil）
    ///   - height: 高度（默认 nil）
    public init(x: Double? = nil, y: Double? = nil, width: Double? = nil, height: Double? = nil) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 用于呈现 Canvas 的参数结构体
/// - 实现了 Codable、Sendable 和 Equatable 协议
public struct MoltbotCanvasPresentParams: Codable, Sendable, Equatable {
    /// 要呈现的 URL 字符串（可选）
    public var url: String?
    /// Canvas 的位置和大小信息（可选）
    public var placement: MoltbotCanvasPlacement?

    /// 初始化方法
    /// - Parameters:
    ///   - url: 要呈现的 URL 字符串（默认 nil）
    ///   - placement: Canvas 的位置和大小信息（默认 nil）
    public init(url: String? = nil, placement: MoltbotCanvasPlacement? = nil) {
        self.url = url
        self.placement = placement
    }
}

/// 用于执行 JavaScript 的参数结构体
/// - 实现了 Codable、Sendable 和 Equatable 协议
public struct MoltbotCanvasEvalParams: Codable, Sendable, Equatable {
    /// 要执行的 JavaScript 代码字符串
    public var javaScript: String

    /// 初始化方法
    /// - Parameter javaScript: 要执行的 JavaScript 代码字符串
    public init(javaScript: String) {
        self.javaScript = javaScript
    }
}

/// Canvas 快照格式枚举
/// - 实现了 Codable、Sendable 协议
public enum MoltbotCanvasSnapshotFormat: String, Codable, Sendable {
    /// PNG 格式
    case png
    /// JPEG 格式
    case jpeg

    /// 从解码器初始化
    /// - Parameter decoder: 解码器
    /// - Throws: 解码错误
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch raw {
        case "png":
            self = .png
        case "jpeg", "jpg":
            self = .jpeg
        default:
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid snapshot format: \(raw)")
        }
    }

    /// 编码到编码器
    /// - Parameter encoder: 编码器
    /// - Throws: 编码错误
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.rawValue)
    }
}

/// 用于生成 Canvas 快照的参数结构体
/// - 实现了 Codable、Sendable 和 Equatable 协议
public struct MoltbotCanvasSnapshotParams: Codable, Sendable, Equatable {
    /// 快照的最大宽度（可选）
    public var maxWidth: Int?
    /// 快照的质量（可选），范围通常为 0.0 到 1.0
    public var quality: Double?
    /// 快照的格式（可选）
    public var format: MoltbotCanvasSnapshotFormat?

    /// 初始化方法
    /// - Parameters:
    ///   - maxWidth: 快照的最大宽度（默认 nil）
    ///   - quality: 快照的质量（默认 nil）
    ///   - format: 快照的格式（默认 nil）
    public init(maxWidth: Int? = nil, quality: Double? = nil, format: MoltbotCanvasSnapshotFormat? = nil) {
        self.maxWidth = maxWidth
        self.quality = quality
        self.format = format
    }
}

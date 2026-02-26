import Foundation

/// 相机命令枚举，定义了支持的相机操作类型
public enum MoltbotCameraCommand: String, Codable, Sendable {
    /// 列出可用相机
    case list = "camera.list"
    /// 拍摄照片
    case snap = "camera.snap"
    /// 录制视频片段
    case clip = "camera.clip"
}

/// 相机朝向枚举，定义了相机的前后方向
public enum MoltbotCameraFacing: String, Codable, Sendable {
    /// 后置相机
    case back
    /// 前置相机
    case front
}

/// 相机图像格式枚举，定义了支持的图像格式
public enum MoltbotCameraImageFormat: String, Codable, Sendable {
    /// JPG图像格式
    case jpg
    /// JPEG图像格式
    case jpeg
}

/// 相机视频格式枚举，定义了支持的视频格式
public enum MoltbotCameraVideoFormat: String, Codable, Sendable {
    /// MP4视频格式
    case mp4
}

/// 相机拍照参数结构体，用于配置拍照时的各项参数
public struct MoltbotCameraSnapParams: Codable, Sendable, Equatable {
    /// 相机朝向（前置/后置）
    public var facing: MoltbotCameraFacing?
    /// 图像最大宽度
    public var maxWidth: Int?
    /// 图像质量（0.0-1.0）
    public var quality: Double?
    /// 图像格式
    public var format: MoltbotCameraImageFormat?
    /// 设备ID，指定使用哪个相机设备
    public var deviceId: String?
    /// 延迟时间（毫秒），拍照前的延迟
    public var delayMs: Int?

    /// 初始化拍照参数
    /// - Parameters:
    ///   - facing: 相机朝向（前置/后置）
    ///   - maxWidth: 图像最大宽度
    ///   - quality: 图像质量（0.0-1.0）
    ///   - format: 图像格式
    ///   - deviceId: 设备ID，指定使用哪个相机设备
    ///   - delayMs: 延迟时间（毫秒），拍照前的延迟
    public init(
        facing: MoltbotCameraFacing? = nil,
        maxWidth: Int? = nil,
        quality: Double? = nil,
        format: MoltbotCameraImageFormat? = nil,
        deviceId: String? = nil,
        delayMs: Int? = nil)
    {
        self.facing = facing
        self.maxWidth = maxWidth
        self.quality = quality
        self.format = format
        self.deviceId = deviceId
        self.delayMs = delayMs
    }
}

/// 相机录制视频参数结构体，用于配置录制视频时的各项参数
public struct MoltbotCameraClipParams: Codable, Sendable, Equatable {
    /// 相机朝向（前置/后置）
    public var facing: MoltbotCameraFacing?
    /// 录制时长（毫秒）
    public var durationMs: Int?
    /// 是否包含音频
    public var includeAudio: Bool?
    /// 视频格式
    public var format: MoltbotCameraVideoFormat?
    /// 设备ID，指定使用哪个相机设备
    public var deviceId: String?

    /// 初始化录制视频参数
    /// - Parameters:
    ///   - facing: 相机朝向（前置/后置）
    ///   - durationMs: 录制时长（毫秒）
    ///   - includeAudio: 是否包含音频
    ///   - format: 视频格式
    ///   - deviceId: 设备ID，指定使用哪个相机设备
    public init(
        facing: MoltbotCameraFacing? = nil,
        durationMs: Int? = nil,
        includeAudio: Bool? = nil,
        format: MoltbotCameraVideoFormat? = nil,
        deviceId: String? = nil)
    {
        self.facing = facing
        self.durationMs = durationMs
        self.includeAudio = includeAudio
        self.format = format
        self.deviceId = deviceId
    }
}

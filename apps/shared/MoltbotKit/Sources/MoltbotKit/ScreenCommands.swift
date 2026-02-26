import Foundation

/// 屏幕命令枚举，定义了可用的屏幕操作命令
public enum MoltbotScreenCommand: String, Codable, Sendable {
    /// 屏幕录制命令
    case record = "screen.record"
}

/// 屏幕录制参数结构体，用于配置屏幕录制的各种选项
public struct MoltbotScreenRecordParams: Codable, Sendable, Equatable {
    /// 屏幕索引，指定要录制的屏幕（默认为主屏幕）
    public var screenIndex: Int?
    /// 录制持续时间（毫秒），如果为 nil 则持续录制直到手动停止
    public var durationMs: Int?
    /// 录制帧率，指定视频的每秒帧数
    public var fps: Double?
    /// 输出格式，指定录制视频的格式
    public var format: String?
    /// 是否包含音频，true 表示同时录制音频
    public var includeAudio: Bool?

    /// 初始化屏幕录制参数
    /// - Parameters:
    ///   - screenIndex: 屏幕索引，默认为 nil（主屏幕）
    ///   - durationMs: 录制持续时间（毫秒），默认为 nil
    ///   - fps: 录制帧率，默认为 nil
    ///   - format: 输出格式，默认为 nil
    ///   - includeAudio: 是否包含音频，默认为 nil
    public init(
        screenIndex: Int? = nil,
        durationMs: Int? = nil,
        fps: Double? = nil,
        format: String? = nil,
        includeAudio: Bool? = nil)
    {
        self.screenIndex = screenIndex
        self.durationMs = durationMs
        self.fps = fps
        self.format = format
        self.includeAudio = includeAudio
    }
}

import Foundation

/// Moltbot 能力枚举，定义了应用支持的各种功能模块
/// 遵循 String、Codable 和 Sendable 协议，可用于序列化和并发环境
public enum MoltbotCapability: String, Codable, Sendable {
    /// 画布能力，用于绘制和图像处理
    case canvas
    /// 相机能力，用于拍摄照片和录制视频
    case camera
    /// 屏幕能力，用于屏幕截图和屏幕录制
    case screen
    /// 语音唤醒能力，用于通过语音指令唤醒应用
    case voiceWake
    /// 位置能力，用于获取设备地理位置信息
    case location
}

import Foundation

/// 音频流播放协议
/// 定义了播放音频流和停止播放的基本方法
@MainActor
public protocol StreamingAudioPlaying {
    /// 播放音频流
    /// - Parameter stream: 异步抛出流，包含音频数据和可能的错误
    /// - Returns: 流播放结果
    func play(stream: AsyncThrowingStream<Data, Error>) async -> StreamingPlaybackResult
    
    /// 停止播放
    /// - Returns: 可选的播放时间（秒），如果没有播放则返回 nil
    func stop() -> Double?
}

/// PCM 音频流播放协议
/// 继承了基本音频流播放功能，增加了采样率参数
@MainActor
public protocol PCMStreamingAudioPlaying {
    /// 播放 PCM 音频流
    /// - Parameters:
    ///   - stream: 异步抛出流，包含 PCM 音频数据和可能的错误
    ///   - sampleRate: 采样率（Hz）
    /// - Returns: 流播放结果
    func play(stream: AsyncThrowingStream<Data, Error>, sampleRate: Double) async -> StreamingPlaybackResult
    
    /// 停止播放
    /// - Returns: 可选的播放时间（秒），如果没有播放则返回 nil
    func stop() -> Double?
}

/// StreamingAudioPlayer 类遵循 StreamingAudioPlaying 协议
extension StreamingAudioPlayer: StreamingAudioPlaying {}

/// PCMStreamingAudioPlayer 类遵循 PCMStreamingAudioPlaying 协议
extension PCMStreamingAudioPlayer: PCMStreamingAudioPlaying {}

import AVFoundation
import ReplayKit

/// 屏幕录制服务类，使用 AVFoundation 和 ReplayKit 框架实现屏幕录制功能
final class ScreenRecordService: @unchecked Sendable {
    /// 用于包装不支持 Sendable 的类型，使其可以在并发上下文中安全传递
    private struct UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
    }

    /// 捕获状态类，用于管理录制过程中的状态
    private final class CaptureState: @unchecked Sendable {
        private let lock = NSLock()         // 用于线程同步的锁
        var writer: AVAssetWriter?          // 资产写入器
        var videoInput: AVAssetWriterInput? // 视频输入
        var audioInput: AVAssetWriterInput? // 音频输入
        var started = false                 // 是否已开始录制
        var sawVideo = false                // 是否已看到视频帧
        var lastVideoTime: CMTime?          // 最后一个视频帧的时间戳
        var handlerError: Error?            // 处理过程中的错误

        /// 在锁的保护下执行闭包
        func withLock<T>(_ body: (CaptureState) -> T) -> T {
            self.lock.lock()
            defer { lock.unlock() }
            return body(self)
        }
    }

    /// 屏幕录制错误枚举
    enum ScreenRecordError: LocalizedError {
        case invalidScreenIndex(Int)  // 无效的屏幕索引
        case captureFailed(String)     // 捕获失败
        case writeFailed(String)       // 写入失败

        /// 错误描述
        var errorDescription: String? {
            switch self {
            case let .invalidScreenIndex(idx):
                "无效的屏幕索引 \(idx)"
            case let .captureFailed(msg):
                msg
            case let .writeFailed(msg):
                msg
            }
        }
    }

    /// 录制屏幕
    /// - Parameters:
    ///   - screenIndex: 屏幕索引（目前仅支持 0）
    ///   - durationMs: 录制持续时间（毫秒）
    ///   - fps: 帧率
    ///   - includeAudio: 是否包含音频
    ///   - outPath: 输出文件路径
    /// - Returns: 录制完成后的文件路径
    func record(
        screenIndex: Int?,
        durationMs: Int?,
        fps: Double?,
        includeAudio: Bool?,
        outPath: String?) async throws -> String
    {
        // 创建录制配置
        let config = try self.makeRecordConfig(
            screenIndex: screenIndex,
            durationMs: durationMs,
            fps: fps,
            includeAudio: includeAudio,
            outPath: outPath)

        // 初始化捕获状态和录制队列
        let state = CaptureState()
        let recordQueue = DispatchQueue(label: "bot.molt.screenrecord")

        // 开始捕获
        try await self.startCapture(state: state, config: config, recordQueue: recordQueue)
        // 等待指定的录制时长
        try await Task.sleep(nanoseconds: UInt64(config.durationMs) * 1_000_000)
        // 停止捕获
        try await self.stopCapture()
        // 完成捕获
        try self.finalizeCapture(state: state)
        // 完成写入
        try await self.finishWriting(state: state)

        // 返回录制文件路径
        return config.outURL.path
    }

    /// 录制配置结构
    private struct RecordConfig {
        let durationMs: Int     // 录制持续时间（毫秒）
        let fpsValue: Double    // 帧率值
        let includeAudio: Bool  // 是否包含音频
        let outURL: URL         // 输出文件 URL
    }

    /// 创建录制配置
    private func makeRecordConfig(
        screenIndex: Int?,
        durationMs: Int?,
        fps: Double?,
        includeAudio: Bool?,
        outPath: String?) throws -> RecordConfig
    {
        // 检查屏幕索引是否有效
        if let idx = screenIndex, idx != 0 {
            throw ScreenRecordError.invalidScreenIndex(idx)
        }

        // 处理录制参数
        let durationMs = Self.clampDurationMs(durationMs)
        let fps = Self.clampFps(fps)
        let fpsInt = Int32(fps.rounded())
        let fpsValue = Double(fpsInt)
        let includeAudio = includeAudio ?? true

        // 创建输出 URL
        let outURL = self.makeOutputURL(outPath: outPath)
        // 删除已存在的文件
        try? FileManager().removeItem(at: outURL)

        // 返回配置
        return RecordConfig(
            durationMs: durationMs,
            fpsValue: fpsValue,
            includeAudio: includeAudio,
            outURL: outURL)
    }

    /// 创建输出 URL
    private func makeOutputURL(outPath: String?) -> URL {
        // 如果提供了输出路径，则使用该路径
        if let outPath, !outPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: outPath)
        }
        // 否则使用临时目录
        return FileManager().temporaryDirectory
            .appendingPathComponent("moltbot-screen-record-\(UUID().uuidString).mp4")
    }

    /// 开始捕获
    private func startCapture(
        state: CaptureState,
        config: RecordConfig,
        recordQueue: DispatchQueue) async throws
    {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // 创建捕获处理器
            let handler = self.makeCaptureHandler(
                state: state,
                config: config,
                recordQueue: recordQueue)
            // 创建完成回调
            let completion: @Sendable (Error?) -> Void = { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }

            // 在主线程上启动 ReplayKit 捕获
            Task { @MainActor in
                startReplayKitCapture(
                    includeAudio: config.includeAudio,
                    handler: handler,
                    completion: completion)
            }
        }
    }

    /// 创建捕获处理器
    private func makeCaptureHandler(
        state: CaptureState,
        config: RecordConfig,
        recordQueue: DispatchQueue) -> @Sendable (CMSampleBuffer, RPSampleBufferType, Error?) -> Void
    {
        { sample, type, error in
            let sampleBox = UncheckedSendableBox(value: sample)
            // ReplayKit 可能在后台队列上调用捕获处理器
            // 序列化写入以避免队列断言
            recordQueue.async {
                let sample = sampleBox.value
                // 处理错误
                if let error {
                    state.withLock { state in
                        if state.handlerError == nil { state.handlerError = error }
                    }
                    return
                }
                // 检查样本数据是否准备就绪
                guard CMSampleBufferDataIsReady(sample) else { return }

                // 根据样本类型处理
                switch type {
                case .video:
                    self.handleVideoSample(sample, state: state, config: config)
                case .audioApp, .audioMic:
                    self.handleAudioSample(sample, state: state, includeAudio: config.includeAudio)
                @unknown default:
                    break
                }
            }
        }
    }

    /// 处理视频样本
    private func handleVideoSample(
        _ sample: CMSampleBuffer,
        state: CaptureState,
        config: RecordConfig)
    {
        // 获取样本的呈现时间戳
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        // 检查是否需要跳过此帧（根据帧率控制）
        let shouldSkip = state.withLock { state in
            if let lastVideoTime = state.lastVideoTime {
                let delta = CMTimeSubtract(pts, lastVideoTime)
                return delta.seconds < (1.0 / config.fpsValue)
            }
            return false
        }
        if shouldSkip { return }

        // 如果写入器尚未初始化，则准备写入器
        if state.withLock({ $0.writer == nil }) {
            self.prepareWriter(sample: sample, state: state, config: config, pts: pts)
        }

        // 获取视频输入和启动状态
        let vInput = state.withLock { $0.videoInput }
        let isStarted = state.withLock { $0.started }
        guard let vInput, isStarted else { return }
        // 如果视频输入准备好接收更多媒体数据
        if vInput.isReadyForMoreMediaData {
            // 尝试追加样本
            if vInput.append(sample) {
                state.withLock { state in
                    state.sawVideo = true
                    state.lastVideoTime = pts
                }
            } else {
                // 处理写入错误
                let err = state.withLock { $0.writer?.error }
                if let err {
                    state.withLock { state in
                        if state.handlerError == nil {
                            state.handlerError = ScreenRecordError.writeFailed(err.localizedDescription)
                        }
                    }
                }
            }
        }
    }

    /// 准备写入器
    private func prepareWriter(
        sample: CMSampleBuffer,
        state: CaptureState,
        config: RecordConfig,
        pts: CMTime)
    {
        // 获取图像缓冲区
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sample) else {
            state.withLock { state in
                if state.handlerError == nil {
                    state.handlerError = ScreenRecordError.captureFailed("缺少图像缓冲区")
                }
            }
            return
        }
        // 获取图像尺寸
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        do {
            // 创建资产写入器
            let writer = try AVAssetWriter(outputURL: config.outURL, fileType: .mp4)
            // 配置视频设置
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ]
            // 创建视频输入
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            vInput.expectsMediaDataInRealTime = true
            // 检查是否可以添加视频输入
            guard writer.canAdd(vInput) else {
                throw ScreenRecordError.writeFailed("无法添加视频输入")
            }
            writer.add(vInput)

            // 如果需要包含音频
            if config.includeAudio {
                // 创建音频输入
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                aInput.expectsMediaDataInRealTime = true
                if writer.canAdd(aInput) {
                    writer.add(aInput)
                    state.withLock { state in
                        state.audioInput = aInput
                    }
                }
            }

            // 开始写入
            guard writer.startWriting() else {
                throw ScreenRecordError.writeFailed(
                    writer.error?.localizedDescription ?? "无法启动写入器")
            }
            // 开始会话
            writer.startSession(atSourceTime: pts)
            // 更新状态
            state.withLock { state in
                state.writer = writer
                state.videoInput = vInput
                state.started = true
            }
        } catch {
            // 处理错误
            state.withLock { state in
                if state.handlerError == nil { state.handlerError = error }
            }
        }
    }

    /// 处理音频样本
    private func handleAudioSample(
        _ sample: CMSampleBuffer,
        state: CaptureState,
        includeAudio: Bool)
    {
        // 获取音频输入和启动状态
        let aInput = state.withLock { $0.audioInput }
        let isStarted = state.withLock { $0.started }
        // 检查是否需要处理音频
        guard includeAudio, let aInput, isStarted else { return }
        // 如果音频输入准备好接收更多媒体数据
        if aInput.isReadyForMoreMediaData {
            _ = aInput.append(sample)
        }
    }

    /// 停止捕获
    private func stopCapture() async throws {
        let stopError = await withCheckedContinuation { cont in
            Task { @MainActor in
                stopReplayKitCapture { error in cont.resume(returning: error) }
            }
        }
        if let stopError { throw stopError }
    }

    /// 完成捕获
    private func finalizeCapture(state: CaptureState) throws {
        // 检查是否有错误
        if let handlerErrorSnapshot = state.withLock({ $0.handlerError }) {
            throw handlerErrorSnapshot
        }
        // 获取状态快照
        let writerSnapshot = state.withLock { $0.writer }
        let videoInputSnapshot = state.withLock { $0.videoInput }
        let audioInputSnapshot = state.withLock { $0.audioInput }
        let sawVideoSnapshot = state.withLock { $0.sawVideo }
        // 检查是否捕获了视频帧
        guard let writerSnapshot, let videoInputSnapshot, sawVideoSnapshot else {
            throw ScreenRecordError.captureFailed("未捕获到帧")
        }

        // 标记输入完成
        videoInputSnapshot.markAsFinished()
        audioInputSnapshot?.markAsFinished()
        _ = writerSnapshot
    }

    /// 完成写入
    private func finishWriting(state: CaptureState) async throws {
        // 获取写入器
        guard let writerSnapshot = state.withLock({ $0.writer }) else {
            throw ScreenRecordError.captureFailed("缺少写入器")
        }
        let writerBox = UncheckedSendableBox(value: writerSnapshot)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // 完成写入
            writerBox.value.finishWriting {
                let writer = writerBox.value
                // 处理错误
                if let err = writer.error {
                    cont.resume(throwing: ScreenRecordError.writeFailed(err.localizedDescription))
                } else if writer.status != .completed {
                    cont.resume(throwing: ScreenRecordError.writeFailed("无法完成视频"))
                } else {
                    cont.resume()
                }
            }
        }
    }

    /// 限制录制持续时间在合理范围内
    private nonisolated static func clampDurationMs(_ ms: Int?) -> Int {
        let v = ms ?? 10000  // 默认 10 秒
        return min(60000, max(250, v))  // 限制在 250ms 到 60s 之间
    }

    /// 限制帧率在合理范围内
    private nonisolated static func clampFps(_ fps: Double?) -> Double {
        let v = fps ?? 10  // 默认 10fps
        if !v.isFinite { return 10 }  // 处理非有限值
        return min(30, max(1, v))  // 限制在 1fps 到 30fps 之间
    }
}

/// 在主线程上启动 ReplayKit 捕获
@MainActor
private func startReplayKitCapture(
    includeAudio: Bool,
    handler: @escaping @Sendable (CMSampleBuffer, RPSampleBufferType, Error?) -> Void,
    completion: @escaping @Sendable (Error?) -> Void)
{
    let recorder = RPScreenRecorder.shared()
    recorder.isMicrophoneEnabled = includeAudio
    recorder.startCapture(handler: handler, completionHandler: completion)
}

/// 在主线程上停止 ReplayKit 捕获
@MainActor
private func stopReplayKitCapture(_ completion: @escaping @Sendable (Error?) -> Void) {
    RPScreenRecorder.shared().stopCapture { error in completion(error) }
}

#if DEBUG
extension ScreenRecordService {
    /// 测试用：限制录制持续时间
    nonisolated static func _test_clampDurationMs(_ ms: Int?) -> Int {
        self.clampDurationMs(ms)
    }

    /// 测试用：限制帧率
    nonisolated static func _test_clampFps(_ fps: Double?) -> Double {
        self.clampFps(fps)
    }
}
#endif

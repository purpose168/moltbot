import AVFoundation
import Foundation

/// 系统语音合成器，用于将文本转换为语音
/// 使用AVFoundation框架实现系统级别的语音合成功能
@MainActor
public final class TalkSystemSpeechSynthesizer: NSObject {
    /// 语音合成错误类型
    public enum SpeakError: Error {
        /// 取消语音合成
        case canceled
    }

    /// 单例实例
    public static let shared = TalkSystemSpeechSynthesizer()

    /// 语音合成器实例
    private let synth = AVSpeechSynthesizer()
    /// 语音合成完成的延续
    private var speakContinuation: CheckedContinuation<Void, Error>?
    /// 当前正在处理的语音 utterance
    private var currentUtterance: AVSpeechUtterance?
    /// 当前语音合成的唯一标识符
    private var currentToken = UUID()
    ///  watchdog 任务，用于处理语音合成超时情况
    private var watchdog: Task<Void, Never>?

    /// 是否正在语音合成
    public var isSpeaking: Bool { self.synth.isSpeaking }

    /// 私有初始化方法
    override private init() {
        super.init()
        // 设置语音合成器的代理
        self.synth.delegate = self
    }

    /// 停止当前语音合成
    public func stop() {
        // 生成新的 token，使之前的语音合成任务失效
        self.currentToken = UUID()
        // 取消 watchdog 任务
        self.watchdog?.cancel()
        self.watchdog = nil
        // 立即停止语音合成
        self.synth.stopSpeaking(at: .immediate)
        // 以取消错误结束当前任务
        self.finishCurrent(with: SpeakError.canceled)
    }

    /// 开始语音合成
    /// - Parameters:
    ///   - text: 要合成的文本
    ///   - language: 语言代码（可选）
    /// - Throws: 语音合成错误
    public func speak(text: String, language: String? = nil) async throws {
        // 去除文本首尾的空白字符和换行符
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // 如果文本为空，直接返回
        guard !trimmed.isEmpty else { return }

        // 停止当前可能正在进行的语音合成
        self.stop()
        // 生成新的 token 用于标识本次语音合成
        let token = UUID()
        self.currentToken = token

        // 创建语音 utterance
        let utterance = AVSpeechUtterance(string: trimmed)
        // 如果指定了语言且能找到对应的语音，则设置语音
        if let language, let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        }
        // 保存当前 utterance
        self.currentUtterance = utterance

        // 估算语音合成所需的时间（最少3秒，最多180秒，基于文本长度）
        let estimatedSeconds = max(3.0, min(180.0, Double(trimmed.count) * 0.08))
        // 取消之前的 watchdog 任务
        self.watchdog?.cancel()
        // 创建新的 watchdog 任务，用于处理超时情况
        self.watchdog = Task { @MainActor [weak self] in
            guard let self else { return }
            // 等待估算的时间
            try? await Task.sleep(nanoseconds: UInt64(estimatedSeconds * 1_000_000_000))
            // 如果任务已取消，直接返回
            if Task.isCancelled { return }
            // 如果当前 token 已变更，说明任务已被其他操作取代，直接返回
            guard self.currentToken == token else { return }
            // 如果仍在语音合成，停止它
            if self.synth.isSpeaking {
                self.synth.stopSpeaking(at: .immediate)
            }
            // 以超时错误结束当前任务
            self.finishCurrent(
                with: NSError(domain: "TalkSystemSpeechSynthesizer", code: 408, userInfo: [
                    NSLocalizedDescriptionKey: "系统语音合成在\(estimatedSeconds)秒后超时",
                ]))
        }

        // 使用任务取消处理器包装语音合成操作
        try await withTaskCancellationHandler(operation: { 
            // 使用检查性延续等待语音合成完成
            try await withCheckedThrowingContinuation { cont in
                self.speakContinuation = cont
                // 开始语音合成
                self.synth.speak(utterance)
            }
        }, onCancel: { 
            // 如果任务被取消，停止语音合成
            Task { @MainActor in
                self.stop()
            }
        })

        // 如果当前 token 已变更，说明任务已被其他操作取代，抛出取消错误
        if self.currentToken != token {
            throw SpeakError.canceled
        }
    }

    /// 处理语音合成完成
    /// - Parameter error: 错误信息（可选）
    private func handleFinish(error: Error?) {
        // 如果当前没有 utterance，直接返回
        guard self.currentUtterance != nil else { return }
        // 取消 watchdog 任务
        self.watchdog?.cancel()
        self.watchdog = nil
        // 结束当前任务
        self.finishCurrent(with: error)
    }

    /// 结束当前语音合成任务
    /// - Parameter error: 错误信息（可选）
    private func finishCurrent(with error: Error?) {
        // 清除当前 utterance
        self.currentUtterance = nil
        // 保存延续引用
        let cont = self.speakContinuation
        // 清除延续引用
        self.speakContinuation = nil
        // 根据是否有错误来恢复延续
        if let error {
            cont?.resume(throwing: error)
        } else {
            cont?.resume(returning: ())
        }
    }
}

/// 扩展实现AVSpeechSynthesizerDelegate协议
/// 处理语音合成的各种回调事件
extension TalkSystemSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    /// 语音合成完成回调
    /// - Parameters:
    ///   - synthesizer: 语音合成器
    ///   - utterance: 已完成的语音 utterance
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance)
    {
        // 在主Actor上处理完成事件
        Task { @MainActor in
            self.handleFinish(error: nil)
        }
    }

    /// 语音合成取消回调
    /// - Parameters:
    ///   - synthesizer: 语音合成器
    ///   - utterance: 已取消的语音 utterance
    public nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance)
    {
        // 在主Actor上处理取消事件
        Task { @MainActor in
            self.handleFinish(error: SpeakError.canceled)
        }
    }
}

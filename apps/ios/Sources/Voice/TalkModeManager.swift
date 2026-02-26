import AVFAudio
import MoltbotKit
import MoltbotProtocol
import Foundation
import Observation
import OSLog
import Speech

/// 语音模式管理器，负责处理语音识别、语音合成和对话流程
@MainActor
@Observable
final class TalkModeManager: NSObject {
    private typealias SpeechRequest = SFSpeechAudioBufferRecognitionRequest
    /// 默认的模型ID回退值
    private static let defaultModelIdFallback = "eleven_v3"
    /// 是否启用语音模式
    var isEnabled: Bool = false
    /// 是否正在聆听
    var isListening: Bool = false
    /// 是否正在说话
    var isSpeaking: Bool = false
    /// 状态文本
    var statusText: String = "关闭"

    /// 音频引擎
    private let audioEngine = AVAudioEngine()
    /// 语音识别器
    private var speechRecognizer: SFSpeechRecognizer?
    /// 语音识别请求
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    /// 语音识别任务
    private var recognitionTask: SFSpeechRecognitionTask?
    /// 静音监测任务
    private var silenceTask: Task<Void, Never>?

    /// 最后听到声音的时间
    private var lastHeard: Date?
    /// 最后识别的文本
    private var lastTranscript: String = ""
    /// 最后说过的文本
    private var lastSpokenText: String?
    /// 最后被打断的时间（秒）
    private var lastInterruptedAtSeconds: Double?

    /// 默认语音ID
    private var defaultVoiceId: String?
    /// 当前语音ID
    private var currentVoiceId: String?
    /// 默认模型ID
    private var defaultModelId: String?
    /// 当前模型ID
    private var currentModelId: String?
    /// 语音覆盖是否激活
    private var voiceOverrideActive = false
    /// 模型覆盖是否激活
    private var modelOverrideActive = false
    /// 默认输出格式
    private var defaultOutputFormat: String?
    /// API密钥
    private var apiKey: String?
    /// 语音别名映射
    private var voiceAliases: [String: String] = [:]
    /// 是否在说话时被打断
    private var interruptOnSpeech: Bool = true
    /// 主会话键
    private var mainSessionKey: String = "main"
    /// 回退语音ID
    private var fallbackVoiceId: String?
    /// 上次播放是否为PCM格式
    private var lastPlaybackWasPCM: Bool = false
    /// PCM音频播放器
    var pcmPlayer: PCMStreamingAudioPlaying = PCMStreamingAudioPlayer.shared
    /// MP3音频播放器
    var mp3Player: StreamingAudioPlaying = StreamingAudioPlayer.shared

    /// 网关节点会话
    private var gateway: GatewayNodeSession?
    /// 静音监测窗口（秒）
    private let silenceWindow: TimeInterval = 0.7

    /// 已订阅的聊天会话键集合
    private var chatSubscribedSessionKeys = Set<String>()

    /// 日志记录器
    private let logger = Logger(subsystem: "bot.molt", category: "TalkMode")

    /// 附加网关节点会话
    func attachGateway(_ gateway: GatewayNodeSession) {
        self.gateway = gateway
    }

    /// 更新主会话键
    func updateMainSessionKey(_ sessionKey: String?) {
        let trimmed = (sessionKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if SessionKey.isCanonicalMainSessionKey(self.mainSessionKey) { return }
        self.mainSessionKey = trimmed
    }

    /// 设置语音模式是否启用
    func setEnabled(_ enabled: Bool) {
        self.isEnabled = enabled
        if enabled {
            self.logger.info("已启用")
            Task { await self.start() }
        } else {
            self.logger.info("已禁用")
            self.stop()
        }
    }

    /// 启动语音模式
    func start() async {
        guard self.isEnabled else { return }
        if self.isListening { return }

        self.logger.info("启动")
        self.statusText = "请求权限中…"
        let micOk = await Self.requestMicrophonePermission()
        guard micOk else {
            self.logger.warning("启动被阻止：麦克风权限被拒绝")
            self.statusText = "麦克风权限被拒绝"
            return
        }
        let speechOk = await Self.requestSpeechPermission()
        guard speechOk else {
            self.logger.warning("启动被阻止：语音识别权限被拒绝")
            self.statusText = "语音识别权限被拒绝"
            return
        }

        await self.reloadConfig()
        do {
            try Self.configureAudioSession()
            try self.startRecognition()
            self.isListening = true
            self.statusText = "正在聆听"
            self.startSilenceMonitor()
            await self.subscribeChatIfNeeded(sessionKey: self.mainSessionKey)
            self.logger.info("正在聆听")
        } catch {
            self.isListening = false
            self.statusText = "启动失败：\(error.localizedDescription)"
            self.logger.error("启动失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 停止语音模式
    func stop() {
        self.isEnabled = false
        self.isListening = false
        self.statusText = "关闭"
        self.lastTranscript = ""
        self.lastHeard = nil
        self.silenceTask?.cancel()
        self.silenceTask = nil
        self.stopRecognition()
        self.stopSpeaking()
        self.lastInterruptedAtSeconds = nil
        TalkSystemSpeechSynthesizer.shared.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            self.logger.warning("音频会话停用失败：\(error.localizedDescription, privacy: .public)")
        }
        Task { await self.unsubscribeAllChats() }
    }

    /// 用户点击了球体
    func userTappedOrb() {
        self.stopSpeaking()
    }

    /// 开始语音识别
    private func startRecognition() throws {
        #if targetEnvironment(simulator)
            throw NSError(domain: "TalkMode", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "语音模式在iOS模拟器上不支持",
            ])
        #endif

        self.stopRecognition()
        self.speechRecognizer = SFSpeechRecognizer()
        guard let recognizer = self.speechRecognizer else {
            throw NSError(domain: "TalkMode", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "语音识别器不可用",
            ])
        }

        self.recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        self.recognitionRequest?.shouldReportPartialResults = true
        guard let request = self.recognitionRequest else { return }

        let input = self.audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "TalkMode", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "无效的音频输入格式",
            ])
        }
        input.removeTap(onBus: 0)
        let tapBlock = Self.makeAudioTapAppendCallback(request: request)
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: tapBlock)

        self.audioEngine.prepare()
        try self.audioEngine.start()

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let error {
                if !self.isSpeaking {
                    self.statusText = "语音错误：\(error.localizedDescription)"
                }
                self.logger.debug("语音识别错误：\(error.localizedDescription, privacy: .public)")
            }
            guard let result else { return }
            let transcript = result.bestTranscription.formattedString
            Task { @MainActor in
                await self.handleTranscript(transcript: transcript, isFinal: result.isFinal)
            }
        }
    }

    /// 停止语音识别
    private func stopRecognition() {
        self.recognitionTask?.cancel()
        self.recognitionTask = nil
        self.recognitionRequest?.endAudio()
        self.recognitionRequest = nil
        self.audioEngine.inputNode.removeTap(onBus: 0)
        self.audioEngine.stop()
        self.speechRecognizer = nil
    }

    /// 创建音频节点点击回调
    private nonisolated static func makeAudioTapAppendCallback(request: SpeechRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
        }
    }

    /// 处理识别到的文本
    private func handleTranscript(transcript: String, isFinal: Bool) async {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.isSpeaking, self.interruptOnSpeech {
            if self.shouldInterrupt(with: trimmed) {
                self.stopSpeaking()
            }
            return
        }

        guard self.isListening else { return }
        if !trimmed.isEmpty {
            self.lastTranscript = trimmed
            self.lastHeard = Date()
        }
        if isFinal {
            self.lastTranscript = trimmed
        }
    }

    /// 启动静音监测
    private func startSilenceMonitor() {
        self.silenceTask?.cancel()
        self.silenceTask = Task { [weak self] in
            guard let self else { return }
            while self.isEnabled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await self.checkSilence()
            }
        }
    }

    /// 检查静音状态
    private func checkSilence() async {
        guard self.isListening, !self.isSpeaking else { return }
        let transcript = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        guard let lastHeard else { return }
        if Date().timeIntervalSince(lastHeard) < self.silenceWindow { return }
        await self.finalizeTranscript(transcript)
    }

    /// 完成识别文本处理
    private func finalizeTranscript(_ transcript: String) async {
        self.isListening = false
        self.statusText = "思考中…"
        self.lastTranscript = ""
        self.lastHeard = nil
        self.stopRecognition()

        await self.reloadConfig()
        let prompt = self.buildPrompt(transcript: transcript)
        guard let gateway else {
            self.statusText = "网关未连接"
            self.logger.warning("完成处理：网关未连接")
            await self.start()
            return
        }

        do {
            let startedAt = Date().timeIntervalSince1970
            let sessionKey = self.mainSessionKey
            await self.subscribeChatIfNeeded(sessionKey: sessionKey)
            self.logger.info(
                "chat.send 开始 sessionKey=\(sessionKey, privacy: .public) 字符数=\(prompt.count, privacy: .public)")
            let runId = try await self.sendChat(prompt, gateway: gateway)
            self.logger.info("chat.send 成功 runId=\(runId, privacy: .public)")
            let completion = await self.waitForChatCompletion(runId: runId, gateway: gateway, timeoutSeconds: 120)
            if completion == .timeout {
                self.logger.warning(
                    "聊天完成超时 runId=\(runId, privacy: .public); 尝试历史回退")
            } else if completion == .aborted {
                self.statusText = "已中止"
                self.logger.warning("聊天完成已中止 runId=\(runId, privacy: .public)")
                await self.start()
                return
            } else if completion == .error {
                self.statusText = "聊天错误"
                self.logger.warning("聊天完成错误 runId=\(runId, privacy: .public)")
                await self.start()
                return
            }

            guard let assistantText = try await self.waitForAssistantText(
                gateway: gateway,
                since: startedAt,
                timeoutSeconds: completion == .final ? 12 : 25)
            else {
                self.statusText = "无回复"
                self.logger.warning("助手文本超时 runId=\(runId, privacy: .public)")
                await self.start()
                return
            }
            self.logger.info("助手文本成功 字符数=\(assistantText.count, privacy: .public)")
            await self.playAssistant(text: assistantText)
        } catch {
            self.statusText = "语音失败：\(error.localizedDescription)"
            self.logger.error("完成处理失败：\(error.localizedDescription, privacy: .public)")
        }

        await self.start()
    }

    /// 订阅聊天（如果需要）
    private func subscribeChatIfNeeded(sessionKey: String) async {
        let key = sessionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard let gateway else { return }
        guard !self.chatSubscribedSessionKeys.contains(key) else { return }

        let payload = "{\"sessionKey\":\"\(key)\"}"
        await gateway.sendEvent(event: "chat.subscribe", payloadJSON: payload)
        self.chatSubscribedSessionKeys.insert(key)
        self.logger.info("chat.subscribe 成功 sessionKey=\(key, privacy: .public)")
    }

    /// 取消订阅所有聊天
    private func unsubscribeAllChats() async {
        guard let gateway else { return }
        let keys = self.chatSubscribedSessionKeys
        self.chatSubscribedSessionKeys.removeAll()
        for key in keys {
            let payload = "{\"sessionKey\":\"\(key)\"}"
            await gateway.sendEvent(event: "chat.unsubscribe", payloadJSON: payload)
        }
    }

    /// 构建聊天提示
    private func buildPrompt(transcript: String) -> String {
        let interrupted = self.lastInterruptedAtSeconds
        self.lastInterruptedAtSeconds = nil
        return TalkPromptBuilder.build(transcript: transcript, interruptedAtSeconds: interrupted)
    }

    /// 聊天完成状态
    private enum ChatCompletionState: CustomStringConvertible {
        case final     // 完成
        case aborted   // 中止
        case error     // 错误
        case timeout   // 超时

        var description: String {
            switch self {
            case .final: "完成"
            case .aborted: "中止"
            case .error: "错误"
            case .timeout: "超时"
            }
        }
    }

    /// 发送聊天消息
    private func sendChat(_ message: String, gateway: GatewayNodeSession) async throws -> String {
        struct SendResponse: Decodable { let runId: String }
        let payload: [String: Any] = [
            "sessionKey": self.mainSessionKey,
            "message": message,
            "thinking": "low",
            "timeoutMs": 30000,
            "idempotencyKey": UUID().uuidString,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw NSError(
                domain: "TalkModeManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "编码聊天载荷失败"])
        }
        let res = try await gateway.request(method: "chat.send", paramsJSON: json, timeoutSeconds: 30)
        let decoded = try JSONDecoder().decode(SendResponse.self, from: res)
        return decoded.runId
    }

    /// 等待聊天完成
    private func waitForChatCompletion(
        runId: String,
        gateway: GatewayNodeSession,
        timeoutSeconds: Int = 120) async -> ChatCompletionState
    {
        let stream = await gateway.subscribeServerEvents(bufferingNewest: 200)
        return await withTaskGroup(of: ChatCompletionState.self) { group in
            group.addTask { [runId] in
                for await evt in stream {
                    if Task.isCancelled { return .timeout }
                    guard evt.event == "chat", let payload = evt.payload else { continue }
                    guard let chatEvent = try? GatewayPayloadDecoding.decode(payload, as: ChatEvent.self) else {
                        continue
                    }
                    guard chatEvent.runid == runId else { continue }
                    if let state = chatEvent.state.value as? String {
                        switch state {
                        case "final": return .final
                        case "aborted": return .aborted
                        case "error": return .error
                        default: break
                        }
                    }
                }
                return .timeout
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
                return .timeout
            }
            let result = await group.next() ?? .timeout
            group.cancelAll()
            return result
        }
    }

    /// 等待助手文本
    private func waitForAssistantText(
        gateway: GatewayNodeSession,
        since: Double,
        timeoutSeconds: Int) async throws -> String?
    {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            if let text = try await self.fetchLatestAssistantText(gateway: gateway, since: since) {
                return text
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return nil
    }

    /// 获取最新的助手文本
    private func fetchLatestAssistantText(gateway: GatewayNodeSession, since: Double? = nil) async throws -> String? {
        let res = try await gateway.request(
            method: "chat.history",
            paramsJSON: "{\"sessionKey\":\"\(self.mainSessionKey)\"}",
            timeoutSeconds: 15)
        guard let json = try JSONSerialization.jsonObject(with: res) as? [String: Any] else { return nil }
        guard let messages = json["messages"] as? [[String: Any]] else { return nil }
        for msg in messages.reversed() {
            guard (msg["role"] as? String) == "assistant" else { continue }
            if let since, let timestamp = msg["timestamp"] as? Double,
               TalkHistoryTimestamp.isAfter(timestamp, sinceSeconds: since) == false
            {
                continue
            }
            guard let content = msg["content"] as? [[String: Any]] else { continue }
            let text = content.compactMap { $0["text"] as? String }.joined(separator: "\n")
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    /// 播放助手文本
    private func playAssistant(text: String) async {
        let parsed = TalkDirectiveParser.parse(text)
        let directive = parsed.directive
        let cleaned = parsed.stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let requestedVoice = directive?.voiceId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedVoice = self.resolveVoiceAlias(requestedVoice)
        if requestedVoice?.isEmpty == false, resolvedVoice == nil {
            self.logger.warning("未知语音别名 \(requestedVoice ?? "?", privacy: .public)")
        }
        if let voice = resolvedVoice {
            if directive?.once != true {
                self.currentVoiceId = voice
                self.voiceOverrideActive = true
            }
        }
        if let model = directive?.modelId {
            if directive?.once != true {
                self.currentModelId = model
                self.modelOverrideActive = true
            }
        }

        self.statusText = "生成语音中…"
        self.isSpeaking = true
        self.lastSpokenText = cleaned

        do {
            let started = Date()
            let language = ElevenLabsTTSClient.validatedLanguage(directive?.language)

            let resolvedKey =
                (self.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? self.apiKey : nil) ??
                ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]
            let apiKey = resolvedKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preferredVoice = resolvedVoice ?? self.currentVoiceId ?? self.defaultVoiceId
            let voiceId: String? = if let apiKey, !apiKey.isEmpty {
                await self.resolveVoiceId(preferred: preferredVoice, apiKey: apiKey)
            } else {
                nil
            }
            let canUseElevenLabs = (voiceId?.isEmpty == false) && (apiKey?.isEmpty == false)

            if canUseElevenLabs, let voiceId, let apiKey {
                let desiredOutputFormat = (directive?.outputFormat ?? self.defaultOutputFormat)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let requestedOutputFormat = (desiredOutputFormat?.isEmpty == false) ? desiredOutputFormat : nil
                let outputFormat = ElevenLabsTTSClient.validatedOutputFormat(requestedOutputFormat ?? "pcm_44100")
                if outputFormat == nil, let requestedOutputFormat {
                    self.logger.warning(
                        "语音输出格式不支持本地播放：\(requestedOutputFormat, privacy: .public)")
                }

                let modelId = directive?.modelId ?? self.currentModelId ?? self.defaultModelId
                func makeRequest(outputFormat: String?) -> ElevenLabsTTSRequest {
                    ElevenLabsTTSRequest(
                        text: cleaned,
                        modelId: modelId,
                        outputFormat: outputFormat,
                        speed: TalkTTSValidation.resolveSpeed(speed: directive?.speed, rateWPM: directive?.rateWPM),
                        stability: TalkTTSValidation.validatedStability(directive?.stability, modelId: modelId),
                        similarity: TalkTTSValidation.validatedUnit(directive?.similarity),
                        style: TalkTTSValidation.validatedUnit(directive?.style),
                        speakerBoost: directive?.speakerBoost,
                        seed: TalkTTSValidation.validatedSeed(directive?.seed),
                        normalize: ElevenLabsTTSClient.validatedNormalize(directive?.normalize),
                        language: language,
                        latencyTier: TalkTTSValidation.validatedLatencyTier(directive?.latencyTier))
                }

                let request = makeRequest(outputFormat: outputFormat)

                let client = ElevenLabsTTSClient(apiKey: apiKey)
                let stream = client.streamSynthesize(voiceId: voiceId, request: request)

                if self.interruptOnSpeech {
                    do {
                        try self.startRecognition()
                    } catch {
                        self.logger.warning(
                            "说话时启动识别失败：\(error.localizedDescription, privacy: .public)")
                    }
                }

                self.statusText = "说话中…"
                let sampleRate = TalkTTSValidation.pcmSampleRate(from: outputFormat)
                let result: StreamingPlaybackResult
                if let sampleRate {
                    self.lastPlaybackWasPCM = true
                    var playback = await self.pcmPlayer.play(stream: stream, sampleRate: sampleRate)
                    if !playback.finished, playback.interruptedAt == nil {
                        let mp3Format = ElevenLabsTTSClient.validatedOutputFormat("mp3_44100")
                        self.logger.warning("PCM播放失败；重试MP3")
                        self.lastPlaybackWasPCM = false
                        let mp3Stream = client.streamSynthesize(
                            voiceId: voiceId,
                            request: makeRequest(outputFormat: mp3Format))
                        playback = await self.mp3Player.play(stream: mp3Stream)
                    }
                    result = playback
                } else {
                    self.lastPlaybackWasPCM = false
                    result = await self.mp3Player.play(stream: stream)
                }
                let duration = Date().timeIntervalSince(started)
                self.logger.info("elevenlabs 流完成=\(result.finished, privacy: .public) 持续时间=\(duration, privacy: .public)s")
                if !result.finished, let interruptedAt = result.interruptedAt {
                    self.lastInterruptedAtSeconds = interruptedAt
                }
            } else {
                self.logger.warning("TTS不可用；回退到系统语音（缺少密钥或语音ID）")
                if self.interruptOnSpeech {
                    do {
                        try self.startRecognition()
                    } catch {
                        self.logger.warning(
                            "说话时启动识别失败：\(error.localizedDescription, privacy: .public)")
                    }
                }
                self.statusText = "说话中（系统）…"
                try await TalkSystemSpeechSynthesizer.shared.speak(text: cleaned, language: language)
            }
        } catch {
            self.logger.error(
                "TTS失败：\(error.localizedDescription, privacy: .public)；回退到系统语音")
            do {
                if self.interruptOnSpeech {
                    do {
                        try self.startRecognition()
                    } catch {
                        self.logger.warning(
                            "说话时启动识别失败：\(error.localizedDescription, privacy: .public)")
                    }
                }
                self.statusText = "说话中（系统）…"
                let language = ElevenLabsTTSClient.validatedLanguage(directive?.language)
                try await TalkSystemSpeechSynthesizer.shared.speak(text: cleaned, language: language)
            } catch {
                self.statusText = "说话失败：\(error.localizedDescription)"
                self.logger.error("系统语音失败：\(error.localizedDescription, privacy: .public)")
            }
        }

        self.stopRecognition()
        self.isSpeaking = false
    }

    /// 停止说话
    private func stopSpeaking(storeInterruption: Bool = true) {
        guard self.isSpeaking else { return }
        let interruptedAt = self.lastPlaybackWasPCM
            ? self.pcmPlayer.stop()
            : self.mp3Player.stop()
        if storeInterruption {
            self.lastInterruptedAtSeconds = interruptedAt
        }
        _ = self.lastPlaybackWasPCM
            ? self.mp3Player.stop()
            : self.pcmPlayer.stop()
        TalkSystemSpeechSynthesizer.shared.stop()
        self.isSpeaking = false
    }

    /// 判断是否应该中断说话
    private func shouldInterrupt(with transcript: String) -> Bool {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }
        if let spoken = self.lastSpokenText?.lowercased(), spoken.contains(trimmed.lowercased()) {
            return false
        }
        return true
    }

    /// 解析语音别名
    private func resolveVoiceAlias(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.lowercased()
        if let mapped = self.voiceAliases[normalized] { return mapped }
        if self.voiceAliases.values.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return trimmed
        }
        return Self.isLikelyVoiceId(trimmed) ? trimmed : nil
    }

    /// 解析语音ID
    private func resolveVoiceId(preferred: String?, apiKey: String) async -> String? {
        let trimmed = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            if let resolved = self.resolveVoiceAlias(trimmed) { return resolved }
            self.logger.warning("未知语音别名 \(trimmed, privacy: .public)")
        }
        if let fallbackVoiceId { return fallbackVoiceId }

        do {
            let voices = try await ElevenLabsTTSClient(apiKey: apiKey).listVoices()
            guard let first = voices.first else {
                self.logger.warning("elevenlabs 语音列表为空")
                return nil
            }
            self.fallbackVoiceId = first.voiceId
            if self.defaultVoiceId == nil {
                self.defaultVoiceId = first.voiceId
            }
            if !self.voiceOverrideActive {
                self.currentVoiceId = first.voiceId
            }
            let name = first.name ?? "未知"
            self.logger
                .info("默认语音已选择 \(name, privacy: .public) (\(first.voiceId, privacy: .public))")
            return first.voiceId
        } catch {
            self.logger.error("elevenlabs 列出语音失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// 判断是否可能是语音ID
    private static func isLikelyVoiceId(_ value: String) -> Bool {
        guard value.count >= 10 else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// 重新加载配置
    private func reloadConfig() async {
        guard let gateway else { return }
        do {
            let res = try await gateway.request(method: "config.get", paramsJSON: "{}", timeoutSeconds: 8)
            guard let json = try JSONSerialization.jsonObject(with: res) as? [String: Any] else { return }
            guard let config = json["config"] as? [String: Any] else { return }
            let talk = config["talk"] as? [String: Any]
            let session = config["session"] as? [String: Any]
            let mainKey = SessionKey.normalizeMainKey(session?["mainKey"] as? String)
            if !SessionKey.isCanonicalMainSessionKey(self.mainSessionKey) {
                self.mainSessionKey = mainKey
            }
            self.defaultVoiceId = (talk?["voiceId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let aliases = talk?["voiceAliases"] as? [String: Any] {
                var resolved: [String: String] = [:]
                for (key, value) in aliases {
                    guard let id = value as? String else { continue }
                    let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalizedKey.isEmpty, !trimmedId.isEmpty else { continue }
                    resolved[normalizedKey] = trimmedId
                }
                self.voiceAliases = resolved
            } else {
                self.voiceAliases = [:]
            }
            if !self.voiceOverrideActive {
                self.currentVoiceId = self.defaultVoiceId
            }
            let model = (talk?["modelId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.defaultModelId = (model?.isEmpty == false) ? model : Self.defaultModelIdFallback
            if !self.modelOverrideActive {
                self.currentModelId = self.defaultModelId
            }
            self.defaultOutputFormat = (talk?["outputFormat"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            self.apiKey = (talk?["apiKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let interrupt = talk?["interruptOnSpeech"] as? Bool {
                self.interruptOnSpeech = interrupt
            }
        } catch {
            self.defaultModelId = Self.defaultModelIdFallback
            if !self.modelOverrideActive {
                self.currentModelId = self.defaultModelId
            }
        }
    }

    /// 配置音频会话
    private static func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [
            .duckOthers,
            .mixWithOthers,
            .allowBluetoothHFP,
            .defaultToSpeaker,
        ])
        try session.setActive(true, options: [])
    }

    /// 请求麦克风权限
    private nonisolated static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation(isolation: nil) { cont in
            AVAudioApplication.requestRecordPermission { ok in
                cont.resume(returning: ok)
            }
        }
    }

    /// 请求语音识别权限
    private nonisolated static func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation(isolation: nil) { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}

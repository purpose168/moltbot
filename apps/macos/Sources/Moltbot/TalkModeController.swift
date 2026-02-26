import Observation

/// 通话模式控制器
/// 管理通话模式的状态和行为
@MainActor
@Observable
final class TalkModeController {
    static let shared = TalkModeController()

    private let logger = Logger(subsystem: "bot.molt", category: "talk.controller")

    private(set) var phase: TalkModePhase = .idle
    private(set) var isPaused: Bool = false

    /// 设置启用状态
    /// - Parameter enabled: 是否启用
    func setEnabled(_ enabled: Bool) async {
        self.logger.info("talk enabled=\(enabled)")
        if enabled {
            TalkOverlayController.shared.present()
        } else {
            TalkOverlayController.shared.dismiss()
        }
        await TalkModeRuntime.shared.setEnabled(enabled)
    }

    /// 更新阶段
    /// - Parameter phase: 新的阶段
    func updatePhase(_ phase: TalkModePhase) {
        self.phase = phase
        TalkOverlayController.shared.updatePhase(phase)
        let effectivePhase = self.isPaused ? "paused" : phase.rawValue
        Task {
            await GatewayConnection.shared.talkMode(
                enabled: AppStateStore.shared.talkEnabled,
                phase: effectivePhase)
        }
    }

    /// 更新电平
    /// - Parameter level: 音频电平
    func updateLevel(_ level: Double) {
        TalkOverlayController.shared.updateLevel(level)
    }

    /// 设置暂停状态
    /// - Parameter paused: 是否暂停
    func setPaused(_ paused: Bool) {
        guard self.isPaused != paused else { return }
        self.logger.info("talk paused=\(paused)")
        self.isPaused = paused
        TalkOverlayController.shared.updatePaused(paused)
        let effectivePhase = paused ? "paused" : self.phase.rawValue
        Task {
            await GatewayConnection.shared.talkMode(
                enabled: AppStateStore.shared.talkEnabled,
                phase: effectivePhase)
        }
        Task { await TalkModeRuntime.shared.setPaused(paused) }
    }

    /// 切换暂停状态
    func togglePaused() {
        self.setPaused(!self.isPaused)
    }

    /// 停止说话
    /// - Parameter reason: 停止原因
    func stopSpeaking(reason: TalkStopReason = .userTap) {
        Task { await TalkModeRuntime.shared.stopSpeaking(reason: reason) }
    }

    /// 退出通话模式
    func exitTalkMode() {
        Task { await AppStateStore.shared.setTalkEnabled(false) }
    }
}

/// 通话停止原因
enum TalkStopReason {
    case userTap
    case speech
    case manual
}

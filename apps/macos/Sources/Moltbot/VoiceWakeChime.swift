import AppKit
import Foundation
import OSLog

/// 语音唤醒提示音类型
enum VoiceWakeChime: Codable, Equatable, Sendable {
    case none
    case system(name: String)
    case custom(displayName: String, bookmark: Data)

    /// 系统提示音名称
    var systemName: String? {
        if case let .system(name) = self {
            return name
        }
        return nil
    }

    /// 显示标签
    var displayLabel: String {
        switch self {
        case .none:
            "无声音"
        case let .system(name):
            VoiceWakeChimeCatalog.displayName(for: name)
        case let .custom(displayName, _):
            displayName
        }
    }
}

/// 语音唤醒提示音目录
enum VoiceWakeChimeCatalog {
    /// 选择器中显示的选项
    static var systemOptions: [String] { SoundEffectCatalog.systemOptions }

    /// 获取显示名称
    static func displayName(for raw: String) -> String {
        SoundEffectCatalog.displayName(for: raw)
    }

    /// 获取URL
    static func url(for name: String) -> URL? {
        SoundEffectCatalog.url(for: name)
    }
}

/// 语音唤醒提示音播放器
@MainActor
enum VoiceWakeChimePlayer {
    private static let logger = Logger(subsystem: "bot.molt", category: "voicewake.chime")
    private static var lastSound: NSSound?

    /// 播放提示音
    /// - Parameters:
    ///   - chime: 提示音类型
    ///   - reason: 播放原因
    static func play(_ chime: VoiceWakeChime, reason: String? = nil) {
        guard let sound = self.sound(for: chime) else { return }
        if let reason {
            self.logger.log(level: .info, "chime play reason=\(reason, privacy: .public)")
        } else {
            self.logger.log(level: .info, "chime play")
        }
        DiagnosticsFileLog.shared.log(category: "voicewake.chime", event: "play", fields: [
            "reason": reason ?? "",
            "chime": chime.displayLabel,
            "systemName": chime.systemName ?? "",
        ])
        SoundEffectPlayer.play(sound)
    }

    /// 获取提示音
    private static func sound(for chime: VoiceWakeChime) -> NSSound? {
        switch chime {
        case .none:
            nil

        case let .system(name):
            SoundEffectPlayer.sound(named: name)

        case let .custom(_, bookmark):
            SoundEffectPlayer.sound(from: bookmark)
        }
    }
}

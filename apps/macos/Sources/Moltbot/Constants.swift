import Foundation

/// Launchd标签
let launchdLabel = "bot.molt.mac"
/// 网关Launchd标签
let gatewayLaunchdLabel = "bot.molt.gateway"
/// 引导流程版本键
let onboardingVersionKey = "moltbot.onboardingVersion"
/// 当前引导流程版本
let currentOnboardingVersion = 7
/// 暂停默认值键
let pauseDefaultsKey = "moltbot.pauseEnabled"
/// 图标动画启用键
let iconAnimationsEnabledKey = "moltbot.iconAnimationsEnabled"
/// Swabble启用键
let swabbleEnabledKey = "moltbot.swabbleEnabled"
/// Swabble触发器键
let swabbleTriggersKey = "moltbot.swabbleTriggers"
/// 语音唤醒触发提示音键
let voiceWakeTriggerChimeKey = "moltbot.voiceWakeTriggerChime"
/// 语音唤醒发送提示音键
let voiceWakeSendChimeKey = "moltbot.voiceWakeSendChime"
/// 显示Dock图标键
let showDockIconKey = "moltbot.showDockIcon"
/// 默认语音唤醒触发器
let defaultVoiceWakeTriggers = ["clawd", "claude"]
/// 语音唤醒最大单词数
let voiceWakeMaxWords = 32
/// 语音唤醒最大单词长度
let voiceWakeMaxWordLength = 64
/// 语音唤醒麦克风ID键
let voiceWakeMicKey = "moltbot.voiceWakeMicID"
/// 语音唤醒麦克风名称键
let voiceWakeMicNameKey = "moltbot.voiceWakeMicName"
/// 语音唤醒区域设置ID键
let voiceWakeLocaleKey = "moltbot.voiceWakeLocaleID"
/// 语音唤醒附加区域设置ID键
let voiceWakeAdditionalLocalesKey = "moltbot.voiceWakeAdditionalLocaleIDs"
/// 语音按键通话启用键
let voicePushToTalkEnabledKey = "moltbot.voicePushToTalkEnabled"
/// 通话启用键
let talkEnabledKey = "moltbot.talkEnabled"
/// 图标覆盖键
let iconOverrideKey = "moltbot.iconOverride"
/// 连接模式键
let connectionModeKey = "moltbot.connectionMode"
/// 远程目标键
let remoteTargetKey = "moltbot.remoteTarget"
/// 远程身份键
let remoteIdentityKey = "moltbot.remoteIdentity"
/// 远程项目根目录键
let remoteProjectRootKey = "moltbot.remoteProjectRoot"
/// 远程CLI路径键
let remoteCliPathKey = "moltbot.remoteCliPath"
/// Canvas启用键
let canvasEnabledKey = "moltbot.canvasEnabled"
/// 相机启用键
let cameraEnabledKey = "moltbot.cameraEnabled"
/// 系统运行策略键
let systemRunPolicyKey = "moltbot.systemRunPolicy"
/// 系统运行允许列表键
let systemRunAllowlistKey = "moltbot.systemRunAllowlist"
/// 系统运行启用键
let systemRunEnabledKey = "moltbot.systemRunEnabled"
/// 位置模式键
let locationModeKey = "moltbot.locationMode"
/// 位置精确启用键
let locationPreciseKey = "moltbot.locationPreciseEnabled"
/// Peekaboo桥启用键
let peekabooBridgeEnabledKey = "moltbot.peekabooBridgeEnabled"
/// 深度链接键键
let deepLinkKeyKey = "moltbot.deepLinkKey"
/// 模型目录路径键
let modelCatalogPathKey = "moltbot.modelCatalogPath"
/// 模型目录重载键
let modelCatalogReloadKey = "moltbot.modelCatalogReload"
/// CLI安装提示版本键
let cliInstallPromptedVersionKey = "moltbot.cliInstallPromptedVersion"
/// 心跳启用键
let heartbeatsEnabledKey = "moltbot.heartbeatsEnabled"
/// 调试文件日志启用键
let debugFileLogEnabledKey = "moltbot.debug.fileLogEnabled"
/// 应用日志级别键
let appLogLevelKey = "moltbot.debug.appLogLevel"
/// 语音唤醒支持状态
let voiceWakeSupported: Bool = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26

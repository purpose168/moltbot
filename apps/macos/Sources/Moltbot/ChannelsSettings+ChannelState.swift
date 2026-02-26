import MoltbotProtocol
import SwiftUI

// MARK: - 渠道状态管理扩展
extension ChannelsSettings {
    /// 获取指定渠道的状态信息
    /// - Parameters:
    ///   - id: 渠道ID
    ///   - type: 状态类型
    /// - Returns: 解码后的状态对象，如不存在返回nil
    private func channelStatus<T: Decodable>(
        _ id: String,
        as type: T.Type) -> T?
    {
        self.store.snapshot?.decodeChannel(id, as: type)
    }

    /// WhatsApp 渠道的状态颜色
    var whatsAppTint: Color {
        guard let status = self.channelStatus("whatsapp", as: ChannelsStatusSnapshot.WhatsAppStatus.self)
        else { return .secondary } // 未获取到状态
        if !status.configured { return .secondary } // 未配置
        if !status.linked { return .red } // 未链接
        if status.lastError != nil { return .orange } // 有错误
        if status.connected { return .green } // 已连接
        if status.running { return .orange } // 运行中
        return .orange // 默认橙色
    }

    /// Telegram 渠道的状态颜色
    var telegramTint: Color {
        guard let status = self.channelStatus("telegram", as: ChannelsStatusSnapshot.TelegramStatus.self)
        else { return .secondary } // 未获取到状态
        if !status.configured { return .secondary } // 未配置
        if status.lastError != nil { return .orange } // 有错误
        if status.probe?.ok == false { return .orange } // 探测失败
        if status.running { return .green } // 运行中
        return .orange // 默认橙色
    }

    /// Discord 渠道的状态颜色
    var discordTint: Color {
        guard let status = self.channelStatus("discord", as: ChannelsStatusSnapshot.DiscordStatus.self)
        else { return .secondary } // 未获取到状态
        if !status.configured { return .secondary } // 未配置
        if status.lastError != nil { return .orange } // 有错误
        if status.probe?.ok == false { return .orange } // 探测失败
        if status.running { return .green } // 运行中
        return .orange // 默认橙色
    }

    /// Google Chat 渠道的状态颜色
    var googlechatTint: Color {
        guard let status = self.channelStatus("googlechat", as: ChannelsStatusSnapshot.GoogleChatStatus.self)
        else { return .secondary } // 未获取到状态
        if !status.configured { return .secondary } // 未配置
        if status.lastError != nil { return .orange } // 有错误
        if status.probe?.ok == false { return .orange } // 探测失败
        if status.running { return .green } // 运行中
        return .orange // 默认橙色
    }

    /// Signal 渠道的状态颜色
    var signalTint: Color {
        guard let status = self.channelStatus("signal", as: ChannelsStatusSnapshot.SignalStatus.self)
        else { return .secondary } // 未获取到状态
        if !status.configured { return .secondary } // 未配置
        if status.lastError != nil { return .orange } // 有错误
        if status.probe?.ok == false { return .orange } // 探测失败
        if status.running { return .green } // 运行中
        return .orange // 默认橙色
    }

    /// iMessage 渠道的状态颜色
    var imessageTint: Color {
        guard let status = self.channelStatus("imessage", as: ChannelsStatusSnapshot.IMessageStatus.self)
        else { return .secondary } // 未获取到状态
        if !status.configured { return .secondary } // 未配置
        if status.lastError != nil { return .orange } // 有错误
        if status.probe?.ok == false { return .orange } // 探测失败
        if status.running { return .green } // 运行中
        return .orange // 默认橙色
    }

    /// WhatsApp 渠道的状态摘要
    var whatsAppSummary: String {
        guard let status = self.channelStatus("whatsapp", as: ChannelsStatusSnapshot.WhatsAppStatus.self)
        else { return "检查中…" }
        if !status.linked { return "未链接" }
        if status.connected { return "已连接" }
        if status.running { return "运行中" }
        return "已链接"
    }

    /// Telegram 渠道的状态摘要
    var telegramSummary: String {
        guard let status = self.channelStatus("telegram", as: ChannelsStatusSnapshot.TelegramStatus.self)
        else { return "检查中…" }
        if !status.configured { return "未配置" }
        if status.running { return "运行中" }
        return "已配置"
    }

    /// Discord 渠道的状态摘要
    var discordSummary: String {
        guard let status = self.channelStatus("discord", as: ChannelsStatusSnapshot.DiscordStatus.self)
        else { return "检查中…" }
        if !status.configured { return "未配置" }
        if status.running { return "运行中" }
        return "已配置"
    }

    /// Google Chat 渠道的状态摘要
    var googlechatSummary: String {
        guard let status = self.channelStatus("googlechat", as: ChannelsStatusSnapshot.GoogleChatStatus.self)
        else { return "检查中…" }
        if !status.configured { return "未配置" }
        if status.running { return "运行中" }
        return "已配置"
    }

    /// Signal 渠道的状态摘要
    var signalSummary: String {
        guard let status = self.channelStatus("signal", as: ChannelsStatusSnapshot.SignalStatus.self)
        else { return "检查中…" }
        if !status.configured { return "未配置" }
        if status.running { return "运行中" }
        return "已配置"
    }

    /// iMessage 渠道的状态摘要
    var imessageSummary: String {
        guard let status = self.channelStatus("imessage", as: ChannelsStatusSnapshot.IMessageStatus.self)
        else { return "检查中…" }
        if !status.configured { return "未配置" }
        if status.running { return "运行中" }
        return "已配置"
    }

    /// WhatsApp 渠道的详细状态信息
    var whatsAppDetails: String? {
        guard let status = self.channelStatus("whatsapp", as: ChannelsStatusSnapshot.WhatsAppStatus.self)
        else { return nil }
        var lines: [String] = []
        // 添加链接信息
        if let e164 = status.`self`?.e164 ?? status.`self`?.jid {
            lines.append("已链接为 \(e164)")
        }
        // 添加认证年龄
        if let age = status.authAgeMs {
            lines.append("认证年龄 \(msToAge(age))")
        }
        // 添加最后连接时间
        if let last = self.date(fromMs: status.lastConnectedAt) {
            lines.append("最后连接 \(relativeAge(from: last))")
        }
        // 添加最后断开信息
        if let disconnect = status.lastDisconnect {
            let when = self.date(fromMs: disconnect.at).map { relativeAge(from: $0) } ?? "未知"
            let code = disconnect.status.map { "状态 \($0)" } ?? "状态未知"
            let err = disconnect.error ?? "断开连接"
            lines.append("最后断开 \(code) · \(err) · \(when)")
        }
        // 添加重连尝试次数
        if status.reconnectAttempts > 0 {
            lines.append("重连尝试 \(status.reconnectAttempts)")
        }
        // 添加最后消息时间
        if let msgAt = self.date(fromMs: status.lastMessageAt) {
            lines.append("最后消息 \(relativeAge(from: msgAt))")
        }
        // 添加错误信息
        if let err = status.lastError, !err.isEmpty {
            lines.append("错误: \(err)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// Telegram 渠道的详细状态信息
    var telegramDetails: String? {
        guard let status = self.channelStatus("telegram", as: ChannelsStatusSnapshot.TelegramStatus.self)
        else { return nil }
        var lines: [String] = []
        // 添加令牌来源
        if let source = status.tokenSource {
            lines.append("令牌来源: \(source)")
        }
        // 添加模式
        if let mode = status.mode {
            lines.append("模式: \(mode)")
        }
        // 添加探测信息
        if let probe = status.probe {
            if probe.ok {
                // 探测成功
                if let name = probe.bot?.username {
                    lines.append("机器人: @\(name)")
                }
                if let url = probe.webhook?.url, !url.isEmpty {
                    lines.append("Webhook: \(url)")
                }
            } else {
                // 探测失败
                let code = probe.status.map { String($0) } ?? "未知"
                lines.append("探测失败 (\(code))")
            }
        }
        // 添加最后探测时间
        if let last = self.date(fromMs: status.lastProbeAt) {
            lines.append("最后探测 \(relativeAge(from: last))")
        }
        // 添加错误信息
        if let err = status.lastError, !err.isEmpty {
            lines.append("错误: \(err)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// Discord 渠道的详细状态信息
    var discordDetails: String? {
        guard let status = self.channelStatus("discord", as: ChannelsStatusSnapshot.DiscordStatus.self)
        else { return nil }
        var lines: [String] = []
        // 添加令牌来源
        if let source = status.tokenSource {
            lines.append("令牌来源: \(source)")
        }
        // 添加探测信息
        if let probe = status.probe {
            if probe.ok {
                // 探测成功
                if let name = probe.bot?.username {
                    lines.append("机器人: @\(name)")
                }
                if let elapsed = probe.elapsedMs {
                    lines.append("探测 \(Int(elapsed))ms")
                }
            } else {
                // 探测失败
                let code = probe.status.map { String($0) } ?? "未知"
                lines.append("探测失败 (\(code))")
            }
        }
        // 添加最后探测时间
        if let last = self.date(fromMs: status.lastProbeAt) {
            lines.append("最后探测 \(relativeAge(from: last))")
        }
        // 添加错误信息
        if let err = status.lastError, !err.isEmpty {
            lines.append("错误: \(err)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// Google Chat 渠道的详细状态信息
    var googlechatDetails: String? {
        guard let status = self.channelStatus("googlechat", as: ChannelsStatusSnapshot.GoogleChatStatus.self)
        else { return nil }
        var lines: [String] = []
        // 添加凭证来源
        if let source = status.credentialSource {
            lines.append("凭证: \(source)")
        }
        // 添加受众信息
        if let audienceType = status.audienceType {
            let audience = status.audience ?? ""
            let label = audience.isEmpty ? audienceType : "\(audienceType) \(audience)"
            lines.append("受众: \(label)")
        }
        // 添加探测信息
        if let probe = status.probe {
            if probe.ok {
                // 探测成功
                if let elapsed = probe.elapsedMs {
                    lines.append("探测 \(Int(elapsed))ms")
                }
            } else {
                // 探测失败
                let code = probe.status.map { String($0) } ?? "未知"
                lines.append("探测失败 (\(code))")
            }
        }
        // 添加最后探测时间
        if let last = self.date(fromMs: status.lastProbeAt) {
            lines.append("最后探测 \(relativeAge(from: last))")
        }
        // 添加错误信息
        if let err = status.lastError, !err.isEmpty {
            lines.append("错误: \(err)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// Signal 渠道的详细状态信息
    var signalDetails: String? {
        guard let status = self.channelStatus("signal", as: ChannelsStatusSnapshot.SignalStatus.self)
        else { return nil }
        var lines: [String] = []
        // 添加基础 URL
        lines.append("基础 URL: \(status.baseUrl)")
        // 添加探测信息
        if let probe = status.probe {
            if probe.ok {
                // 探测成功
                if let version = probe.version, !version.isEmpty {
                    lines.append("版本 \(version)")
                }
                if let elapsed = probe.elapsedMs {
                    lines.append("探测 \(Int(elapsed))ms")
                }
            } else {
                // 探测失败
                let code = probe.status.map { String($0) } ?? "未知"
                lines.append("探测失败 (\(code))")
            }
        }
        // 添加最后探测时间
        if let last = self.date(fromMs: status.lastProbeAt) {
            lines.append("最后探测 \(relativeAge(from: last))")
        }
        // 添加错误信息
        if let err = status.lastError, !err.isEmpty {
            lines.append("错误: \(err)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// iMessage 渠道的详细状态信息
    var imessageDetails: String? {
        guard let status = self.channelStatus("imessage", as: ChannelsStatusSnapshot.IMessageStatus.self)
        else { return nil }
        var lines: [String] = []
        // 添加 CLI 路径
        if let cliPath = status.cliPath, !cliPath.isEmpty {
            lines.append("CLI: \(cliPath)")
        }
        // 添加数据库路径
        if let dbPath = status.dbPath, !dbPath.isEmpty {
            lines.append("DB: \(dbPath)")
        }
        // 添加探测错误
        if let probe = status.probe, !probe.ok {
            let err = probe.error ?? "探测失败"
            lines.append("探测错误: \(err)")
        }
        // 添加最后探测时间
        if let last = self.date(fromMs: status.lastProbeAt) {
            lines.append("最后探测 \(relativeAge(from: last))")
        }
        // 添加错误信息
        if let err = status.lastError, !err.isEmpty {
            lines.append("错误: \(err)")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " · ")
    }

    /// 有序的渠道列表
    var orderedChannels: [ChannelItem] {
        let fallback = ["whatsapp", "telegram", "discord", "googlechat", "slack", "signal", "imessage"]
        let order = self.store.snapshot?.channelOrder ?? fallback
        let channels = order.enumerated().map { index, id in
            ChannelItem(
                id: id,
                title: self.resolveChannelTitle(id),
                detailTitle: self.resolveChannelDetailTitle(id),
                systemImage: self.resolveChannelSystemImage(id),
                sortOrder: index)
        }
        return channels.sorted { lhs, rhs in
            let lhsEnabled = self.channelEnabled(lhs)
            let rhsEnabled = self.channelEnabled(rhs)
            if lhsEnabled != rhsEnabled { return lhsEnabled && !rhsEnabled }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    /// 已启用的渠道列表
    var enabledChannels: [ChannelItem] {
        self.orderedChannels.filter { self.channelEnabled($0) }
    }

    /// 可用的渠道列表（未启用）
    var availableChannels: [ChannelItem] {
        self.orderedChannels.filter { !self.channelEnabled($0) }
    }

    /// 确保选择了一个渠道
    func ensureSelection() {
        guard let selected = self.selectedChannel else {
            self.selectedChannel = self.orderedChannels.first
            return
        }
        if !self.orderedChannels.contains(selected) {
            self.selectedChannel = self.orderedChannels.first
        }
    }

    /// 检查渠道是否已启用
    /// - Parameter channel: 渠道项
    /// - Returns: 是否已启用
    func channelEnabled(_ channel: ChannelItem) -> Bool {
        let status = self.channelStatusDictionary(channel.id)
        let configured = status?["configured"]?.boolValue ?? false
        let running = status?["running"]?.boolValue ?? false
        let connected = status?["connected"]?.boolValue ?? false
        let accountActive = self.store.snapshot?.channelAccounts[channel.id]?.contains(
            where: { $0.configured == true || $0.running == true || $0.connected == true }) ?? false
        return configured || running || connected || accountActive
    }

    /// 为渠道创建对应的设置视图
    /// - Parameter channel: 渠道项
    /// - Returns: 渠道对应的设置视图
    @ViewBuilder
    func channelSection(_ channel: ChannelItem) -> some View {
        if channel.id == "whatsapp" {
            self.whatsAppSection
        } else {
            self.genericChannelSection(channel)
        }
    }

    /// 获取渠道的状态颜色
    /// - Parameter channel: 渠道项
    /// - Returns: 状态对应的颜色
    func channelTint(_ channel: ChannelItem) -> Color {
        switch channel.id {
        case "whatsapp":
            return self.whatsAppTint
        case "telegram":
            return self.telegramTint
        case "discord":
            return self.discordTint
        case "googlechat":
            return self.googlechatTint
        case "signal":
            return self.signalTint
        case "imessage":
            return self.imessageTint
        default:
            if self.channelHasError(channel) { return .orange }
            if self.channelEnabled(channel) { return .green }
            return .secondary
        }
    }

    /// 获取渠道的状态摘要
    /// - Parameter channel: 渠道项
    /// - Returns: 状态摘要文本
    func channelSummary(_ channel: ChannelItem) -> String {
        switch channel.id {
        case "whatsapp":
            return self.whatsAppSummary
        case "telegram":
            return self.telegramSummary
        case "discord":
            return self.discordSummary
        case "googlechat":
            return self.googlechatSummary
        case "signal":
            return self.signalSummary
        case "imessage":
            return self.imessageSummary
        default:
            if self.channelHasError(channel) { return "错误" }
            if self.channelEnabled(channel) { return "活跃" }
            return "未配置"
        }
    }

    /// 获取渠道的详细状态信息
    /// - Parameter channel: 渠道项
    /// - Returns: 详细状态信息，如无返回nil
    func channelDetails(_ channel: ChannelItem) -> String? {
        switch channel.id {
        case "whatsapp":
            return self.whatsAppDetails
        case "telegram":
            return self.telegramDetails
        case "discord":
            return self.discordDetails
        case "googlechat":
            return self.googlechatDetails
        case "signal":
            return self.signalDetails
        case "imessage":
            return self.imessageDetails
        default:
            let status = self.channelStatusDictionary(channel.id)
            if let err = status?["lastError"]?.stringValue, !err.isEmpty {
                return "错误: \(err)"
            }
            return nil
        }
    }

    /// 获取渠道最后检查时间的文本表示
    /// - Parameter channel: 渠道项
    /// - Returns: 时间文本
    func channelLastCheckText(_ channel: ChannelItem) -> String {
        guard let date = self.channelLastCheck(channel) else { return "从未" }
        return relativeAge(from: date)
    }

    /// 获取渠道最后检查时间
    /// - Parameter channel: 渠道项
    /// - Returns: 最后检查时间，如无返回nil
    func channelLastCheck(_ channel: ChannelItem) -> Date? {
        switch channel.id {
        case "whatsapp":
            guard let status = self.channelStatus("whatsapp", as: ChannelsStatusSnapshot.WhatsAppStatus.self)
            else { return nil }
            return self.date(fromMs: status.lastEventAt ?? status.lastMessageAt ?? status.lastConnectedAt)
        case "telegram":
            return self
                .date(fromMs: self.channelStatus("telegram", as: ChannelsStatusSnapshot.TelegramStatus.self)?
                    .lastProbeAt)
        case "discord":
            return self
                .date(fromMs: self.channelStatus("discord", as: ChannelsStatusSnapshot.DiscordStatus.self)?
                    .lastProbeAt)
        case "googlechat":
            return self
                .date(fromMs: self.channelStatus("googlechat", as: ChannelsStatusSnapshot.GoogleChatStatus.self)?
                    .lastProbeAt)
        case "signal":
            return self
                .date(fromMs: self.channelStatus("signal", as: ChannelsStatusSnapshot.SignalStatus.self)?.lastProbeAt)
        case "imessage":
            return self
                .date(fromMs: self.channelStatus("imessage", as: ChannelsStatusSnapshot.IMessageStatus.self)?
                    .lastProbeAt)
        default:
            let status = self.channelStatusDictionary(channel.id)
            if let probeAt = status?["lastProbeAt"]?.doubleValue {
                return self.date(fromMs: probeAt)
            }
            if let accounts = self.store.snapshot?.channelAccounts[channel.id] {
                let last = accounts.compactMap { $0.lastInboundAt ?? $0.lastOutboundAt }.max()
                return self.date(fromMs: last)
            }
            return nil
        }
    }

    /// 检查渠道是否有错误
    /// - Parameter channel: 渠道项
    /// - Returns: 是否有错误
    func channelHasError(_ channel: ChannelItem) -> Bool {
        switch channel.id {
        case "whatsapp":
            guard let status = self.channelStatus("whatsapp", as: ChannelsStatusSnapshot.WhatsAppStatus.self)
            else { return false }
            return status.lastError?.isEmpty == false || status.lastDisconnect?.loggedOut == true
        case "telegram":
            guard let status = self.channelStatus("telegram", as: ChannelsStatusSnapshot.TelegramStatus.self)
            else { return false }
            return status.lastError?.isEmpty == false || status.probe?.ok == false
        case "discord":
            guard let status = self.channelStatus("discord", as: ChannelsStatusSnapshot.DiscordStatus.self)
            else { return false }
            return status.lastError?.isEmpty == false || status.probe?.ok == false
        case "googlechat":
            guard let status = self.channelStatus("googlechat", as: ChannelsStatusSnapshot.GoogleChatStatus.self)
            else { return false }
            return status.lastError?.isEmpty == false || status.probe?.ok == false
        case "signal":
            guard let status = self.channelStatus("signal", as: ChannelsStatusSnapshot.SignalStatus.self)
            else { return false }
            return status.lastError?.isEmpty == false || status.probe?.ok == false
        case "imessage":
            guard let status = self.channelStatus("imessage", as: ChannelsStatusSnapshot.IMessageStatus.self)
            else { return false }
            return status.lastError?.isEmpty == false || status.probe?.ok == false
        default:
            let status = self.channelStatusDictionary(channel.id)
            return status?["lastError"]?.stringValue?.isEmpty == false
        }
    }

    /// 解析渠道标题
    /// - Parameter id: 渠道ID
    /// - Returns: 渠道标题
    private func resolveChannelTitle(_ id: String) -> String {
        let label = self.store.resolveChannelLabel(id)
        if label != id { return label }
        return id.prefix(1).uppercased() + id.dropFirst()
    }

    /// 解析渠道详细标题
    /// - Parameter id: 渠道ID
    /// - Returns: 渠道详细标题
    private func resolveChannelDetailTitle(_ id: String) -> String {
        self.store.resolveChannelDetailLabel(id)
    }

    /// 解析渠道系统图标
    /// - Parameter id: 渠道ID
    /// - Returns: 系统图标名称
    private func resolveChannelSystemImage(_ id: String) -> String {
        self.store.resolveChannelSystemImage(id)
    }

    /// 获取渠道状态字典
    /// - Parameter id: 渠道ID
    /// - Returns: 状态字典，如无返回nil
    private func channelStatusDictionary(_ id: String) -> [String: AnyCodable]? {
        self.store.snapshot?.channels[id]?.dictionaryValue
    }
}

import MoltbotProtocol
import Foundation
import SwiftUI

/// CronJobEditor 扩展
/// 
/// 包含 CronJobEditor 的辅助方法
extension CronJobEditor {
    /// 创建网格标签
    /// - Parameter text: 标签文本
    /// - Returns: 标签视图
    func gridLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: self.labelColumnWidth, alignment: .leading)
    }

    /// 从作业中加载数据
    func hydrateFromJob() {
        guard let job else { return }
        self.name = job.name
        self.description = job.description ?? ""
        self.agentId = job.agentId ?? ""
        self.enabled = job.enabled
        self.deleteAfterRun = job.deleteAfterRun ?? false
        self.sessionTarget = job.sessionTarget
        self.wakeMode = job.wakeMode

        switch job.schedule {
        case let .at(atMs):
            self.scheduleKind = .at
            self.atDate = Date(timeIntervalSince1970: TimeInterval(atMs) / 1000)
        case let .every(everyMs, _):
            self.scheduleKind = .every
            self.everyText = self.formatDuration(ms: everyMs)
        case let .cron(expr, tz):
            self.scheduleKind = .cron
            self.cronExpr = expr
            self.cronTz = tz ?? ""
        }

        switch job.payload {
        case let .systemEvent(text):
            self.payloadKind = .systemEvent
            self.systemEventText = text
        case let .agentTurn(message, thinking, timeoutSeconds, deliver, channel, to, bestEffortDeliver):
            self.payloadKind = .agentTurn
            self.agentMessage = message
            self.thinking = thinking ?? ""
            self.timeoutSeconds = timeoutSeconds.map(String.init) ?? ""
            self.deliver = deliver ?? false
            let trimmed = (channel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            self.channel = trimmed.isEmpty ? "last" : trimmed
            self.to = to ?? ""
            self.bestEffortDeliver = bestEffortDeliver ?? false
        }

        self.postPrefix = job.isolation?.postToMainPrefix ?? "Cron"
    }

    /// 保存作业
    func save() {
        do {
            self.error = nil
            let payload = try self.buildPayload()
            self.onSave(payload)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 构建有效载荷
    /// - Returns: 有效载荷字典
    /// - Throws: 构建过程中的错误
    func buildPayload() throws -> [String: AnyCodable] {
        let name = try self.requireName()
        let description = self.trimmed(self.description)
        let agentId = self.trimmed(self.agentId)
        let schedule = try self.buildSchedule()
        let payload = try self.buildSelectedPayload()

        try self.validateSessionTarget(payload)
        try self.validatePayloadRequiredFields(payload)

        var root: [String: Any] = [
            "name": name,
            "enabled": self.enabled,
            "schedule": schedule,
            "sessionTarget": self.sessionTarget.rawValue,
            "wakeMode": self.wakeMode.rawValue,
            "payload": payload,
        ]
        self.applyDeleteAfterRun(to: &root)
        if !description.isEmpty { root["description"] = description }
        if !agentId.isEmpty {
            root["agentId"] = agentId
        } else if self.job?.agentId != nil {
            root["agentId"] = NSNull()
        }

        if self.sessionTarget == .isolated {
            let trimmed = self.postPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
            root["isolation"] = [
                "postToMainPrefix": trimmed.isEmpty ? "Cron" : trimmed,
            ]
        }

        return root.mapValues { AnyCodable($0) }
    }

    /// 修剪字符串
    /// - Parameter value: 输入字符串
    /// - Returns: 修剪后的字符串
    func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 要求名称
    /// - Returns: 修剪后的名称
    /// - Throws: 如果名称为空则抛出错误
    func requireName() throws -> String {
        let name = self.trimmed(self.name)
        if name.isEmpty {
            throw NSError(
                domain: "Cron",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "名称是必需的。"])
        }
        return name
    }

    /// 构建调度
    /// - Returns: 调度字典
    /// - Throws: 构建过程中的错误
    func buildSchedule() throws -> [String: Any] {
        switch self.scheduleKind {
        case .at:
            return ["kind": "at", "atMs": Int(self.atDate.timeIntervalSince1970 * 1000)]
        case .every:
            guard let ms = Self.parseDurationMs(self.everyText) else {
                throw NSError(
                    domain: "Cron",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "无效的每隔持续时间（使用 10m, 1h, 1d）。"])
            }
            return ["kind": "every", "everyMs": ms]
        case .cron:
            let expr = self.trimmed(self.cronExpr)
            if expr.isEmpty {
                throw NSError(
                    domain: "Cron",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Cron 表达式是必需的。"])
            }
            let tz = self.trimmed(self.cronTz)
            if tz.isEmpty {
                return ["kind": "cron", "expr": expr]
            }
            return ["kind": "cron", "expr": expr, "tz": tz]
        }
    }

    /// 构建选定的有效载荷
    /// - Returns: 有效载荷字典
    /// - Throws: 构建过程中的错误
    func buildSelectedPayload() throws -> [String: Any] {
        if self.sessionTarget == .isolated { return self.buildAgentTurnPayload() }
        switch self.payloadKind {
        case .systemEvent:
            let text = self.trimmed(self.systemEventText)
            return ["kind": "systemEvent", "text": text]
        case .agentTurn:
            return self.buildAgentTurnPayload()
        }
    }

    /// 验证会话目标
    /// - Parameter payload: 有效载荷字典
    /// - Throws: 验证过程中的错误
    func validateSessionTarget(_ payload: [String: Any]) throws {
        if self.sessionTarget == .main, payload["kind"] as? String == "agentTurn" {
            throw NSError(
                domain: "Cron",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "主会话作业需要 systemEvent 有效载荷（将会话目标切换到隔离）。",
                ])
        }

        if self.sessionTarget == .isolated, payload["kind"] as? String == "systemEvent" {
            throw NSError(
                domain: "Cron",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "隔离作业需要 agentTurn 有效载荷。"])
        }
    }

    /// 验证有效载荷必填字段
    /// - Parameter payload: 有效载荷字典
    /// - Throws: 验证过程中的错误
    func validatePayloadRequiredFields(_ payload: [String: Any]) throws {
        if payload["kind"] as? String == "systemEvent" {
            if (payload["text"] as? String ?? "").isEmpty {
                throw NSError(
                    domain: "Cron",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "系统事件文本是必需的。"])
            }
        }
        if payload["kind"] as? String == "agentTurn" {
            if (payload["message"] as? String ?? "").isEmpty {
                throw NSError(
                    domain: "Cron",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "代理消息是必需的。"])
            }
        }
    }

    /// 应用删除后运行设置
    /// - Parameters:
    ///   - root: 根字典
    ///   - scheduleKind: 调度类型，可选
    ///   - deleteAfterRun: 删除后运行标志，可选
    func applyDeleteAfterRun(
        to root: inout [String: Any],
        scheduleKind: ScheduleKind? = nil,
        deleteAfterRun: Bool? = nil)
    {
        let resolvedSchedule = scheduleKind ?? self.scheduleKind
        let resolvedDelete = deleteAfterRun ?? self.deleteAfterRun
        if resolvedSchedule == .at {
            root["deleteAfterRun"] = resolvedDelete
        } else if self.job?.deleteAfterRun != nil {
            root["deleteAfterRun"] = false
        }
    }

    /// 构建代理回合有效载荷
    /// - Returns: 代理回合有效载荷字典
    func buildAgentTurnPayload() -> [String: Any] {
        let msg = self.agentMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: Any] = ["kind": "agentTurn", "message": msg]
        let thinking = self.thinking.trimmingCharacters(in: .whitespacesAndNewlines)
        if !thinking.isEmpty { payload["thinking"] = thinking }
        if let n = Int(self.timeoutSeconds), n > 0 { payload["timeoutSeconds"] = n }
        payload["deliver"] = self.deliver
        if self.deliver {
            let trimmed = self.channel.trimmingCharacters(in: .whitespacesAndNewlines)
            payload["channel"] = trimmed.isEmpty ? "last" : trimmed
            let to = self.to.trimmingCharacters(in: .whitespacesAndNewlines)
            if !to.isEmpty { payload["to"] = to }
            payload["bestEffortDeliver"] = self.bestEffortDeliver
        }
        return payload
    }

    /// 解析持续时间（毫秒）
    /// - Parameter input: 输入字符串
    /// - Returns: 毫秒数，或 nil 如果解析失败
    static func parseDurationMs(_ input: String) -> Int? {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return nil }

        let rx = try? NSRegularExpression(pattern: "^(\\d+(?:\\.\\d+)?)(ms|s|m|h|d)$", options: [.caseInsensitive])
        guard let match = rx?.firstMatch(in: raw, range: NSRange(location: 0, length: raw.utf16.count)) else {
            return nil
        }
        func group(_ idx: Int) -> String {
            let range = match.range(at: idx)
            guard let r = Range(range, in: raw) else { return "" }
            return String(raw[r])
        }
        let n = Double(group(1)) ?? 0
        if !n.isFinite || n <= 0 { return nil }
        let unit = group(2).lowercased()
        let factor: Double = switch unit {
        case "ms": 1
        case "s": 1000
        case "m": 60000
        case "h": 3_600_000
        default: 86_400_000
        }
        return Int(floor(n * factor))
    }

    /// 格式化持续时间
    /// - Parameter ms: 毫秒数
    /// - Returns: 格式化的持续时间字符串
    func formatDuration(ms: Int) -> String {
        if ms < 1000 { return "\(ms)ms" }
        let s = Double(ms) / 1000.0
        if s < 60 { return "\(Int(round(s)))s" }
        let m = s / 60.0
        if m < 60 { return "\(Int(round(m)))m" }
        let h = m / 60.0
        if h < 48 { return "\(Int(round(h)))h" }
        let d = h / 24.0
        return "\(Int(round(d)))d"
    }
}

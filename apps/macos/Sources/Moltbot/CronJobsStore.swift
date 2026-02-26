import MoltbotKit
import MoltbotProtocol
import Foundation
import Observation
import OSLog

/// Cron 作业存储
/// 
/// 用于管理 Cron 作业的存储类，包括获取、更新、删除和运行作业等功能
@MainActor
@Observable
final class CronJobsStore {
    /// 共享实例
    static let shared = CronJobsStore()

    /// 作业列表
    var jobs: [CronJob] = []
    /// 选中的作业 ID
    var selectedJobId: String?
    /// 运行条目
    var runEntries: [CronRunLogEntry] = []

    /// 调度器是否启用
    var schedulerEnabled: Bool?
    /// 调度器存储路径
    var schedulerStorePath: String?
    /// 调度器下次唤醒时间（毫秒）
    var schedulerNextWakeAtMs: Int?

    /// 是否正在加载作业
    var isLoadingJobs = false
    /// 是否正在加载运行记录
    var isLoadingRuns = false
    /// 最后一个错误
    var lastError: String?
    /// 状态消息
    var statusMessage: String?

    /// 日志记录器
    private let logger = Logger(subsystem: "bot.molt", category: "cron.ui")
    /// 刷新任务
    private var refreshTask: Task<Void, Never>?
    /// 运行记录任务
    private var runsTask: Task<Void, Never>?
    /// 事件任务
    private var eventTask: Task<Void, Never>?
    /// 轮询任务
    private var pollTask: Task<Void, Never>?

    /// 轮询间隔（秒）
    private let interval: TimeInterval = 30
    /// 是否为预览模式
    private let isPreview: Bool

    /// 初始化
    /// - Parameter isPreview: 是否为预览模式，默认为 ProcessInfo.processInfo.isPreview
    init(isPreview: Bool = ProcessInfo.processInfo.isPreview) {
        self.isPreview = isPreview
    }

    /// 启动
    /// 
    /// 启动网关订阅和轮询任务
    func start() {
        guard !self.isPreview else { return }
        guard self.eventTask == nil else { return }
        self.startGatewaySubscription()
        self.pollTask = Task.detached { [weak self] in
            guard let self else { return }
            await self.refreshJobs()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                await self.refreshJobs()
            }
        }
    }

    /// 停止
    /// 
    /// 取消所有任务
    func stop() {
        self.refreshTask?.cancel()
        self.refreshTask = nil
        self.runsTask?.cancel()
        self.runsTask = nil
        self.eventTask?.cancel()
        self.eventTask = nil
        self.pollTask?.cancel()
        self.pollTask = nil
    }

    /// 刷新作业
    /// 
    /// 从网关获取作业列表和调度器状态
    func refreshJobs() async {
        guard !self.isLoadingJobs else { return }
        self.isLoadingJobs = true
        self.lastError = nil
        self.statusMessage = nil
        defer { self.isLoadingJobs = false }

        do {
            if let status = try? await GatewayConnection.shared.cronStatus() {
                self.schedulerEnabled = status.enabled
                self.schedulerStorePath = status.storePath
                self.schedulerNextWakeAtMs = status.nextWakeAtMs
            }
            self.jobs = try await GatewayConnection.shared.cronList(includeDisabled: true)
            if self.jobs.isEmpty {
                self.statusMessage = "尚未有 cron 作业。"
            }
        } catch {
            self.logger.error("cron.list 失败 \(error.localizedDescription, privacy: .public)")
            self.lastError = error.localizedDescription
        }
    }

    /// 刷新运行记录
    /// - Parameters:
    ///   - jobId: 作业 ID
    ///   - limit: 限制数量，默认为 200
    func refreshRuns(jobId: String, limit: Int = 200) async {
        guard !self.isLoadingRuns else { return }
        self.isLoadingRuns = true
        defer { self.isLoadingRuns = false }

        do {
            self.runEntries = try await GatewayConnection.shared.cronRuns(jobId: jobId, limit: limit)
        } catch {
            self.logger.error("cron.runs 失败 \(error.localizedDescription, privacy: .public)")
            self.lastError = error.localizedDescription
        }
    }

    /// 运行作业
    /// - Parameters:
    ///   - id: 作业 ID
    ///   - force: 是否强制运行，默认为 true
    func runJob(id: String, force: Bool = true) async {
        do {
            try await GatewayConnection.shared.cronRun(jobId: id, force: force)
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// 删除作业
    /// - Parameter id: 作业 ID
    func removeJob(id: String) async {
        do {
            try await GatewayConnection.shared.cronRemove(jobId: id)
            await self.refreshJobs()
            if self.selectedJobId == id {
                self.selectedJobId = nil
                self.runEntries = []
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// 设置作业启用状态
    /// - Parameters:
    ///   - id: 作业 ID
    ///   - enabled: 是否启用
    func setJobEnabled(id: String, enabled: Bool) async {
        do {
            try await GatewayConnection.shared.cronUpdate(
                jobId: id,
                patch: ["enabled": AnyCodable(enabled)])
            await self.refreshJobs()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    /// 插入或更新作业
    /// - Parameters:
    ///   - id: 作业 ID，nil 表示新建
    ///   - payload: 作业有效载荷
    /// - Throws: 操作过程中的错误
    func upsertJob(
        id: String?,
        payload: [String: AnyCodable]) async throws
    {
        if let id {
            try await GatewayConnection.shared.cronUpdate(jobId: id, patch: payload)
        } else {
            try await GatewayConnection.shared.cronAdd(payload: payload)
        }
        await self.refreshJobs()
    }

    // MARK: - 网关事件

    /// 启动网关订阅
    private func startGatewaySubscription() {
        self.eventTask?.cancel()
        self.eventTask = Task { [weak self] in
            guard let self else { return }
            let stream = await GatewayConnection.shared.subscribe()
            for await push in stream {
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    self?.handle(push: push)
                }
            }
        }
    }

    /// 处理网关推送
    /// - Parameter push: 网关推送事件
    private func handle(push: GatewayPush) {
        switch push {
        case let .event(evt) where evt.event == "cron":
            guard let payload = evt.payload else { return }
            if let cronEvt = try? GatewayPayloadDecoding.decode(payload, as: CronEvent.self) {
                self.handle(cronEvent: cronEvt)
            }
        case .seqGap:
            self.scheduleRefresh()
        default:
            break
        }
    }

    /// 处理 Cron 事件
    /// - Parameter evt: Cron 事件
    private func handle(cronEvent evt: CronEvent) {
        // 保持 UI 与网关调度器同步
        self.scheduleRefresh(delayMs: 250)
        if evt.action == "finished", let selected = self.selectedJobId, selected == evt.jobId {
            self.scheduleRunsRefresh(jobId: selected, delayMs: 200)
        }
    }

    /// 安排刷新
    /// - Parameter delayMs: 延迟时间（毫秒），默认为 250
    private func scheduleRefresh(delayMs: Int = 250) {
        self.refreshTask?.cancel()
        self.refreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await self.refreshJobs()
        }
    }

    /// 安排运行记录刷新
    /// - Parameters:
    ///   - jobId: 作业 ID
    ///   - delayMs: 延迟时间（毫秒），默认为 200
    private func scheduleRunsRefresh(jobId: String, delayMs: Int = 200) {
        self.runsTask?.cancel()
        self.runsTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
            await self.refreshRuns(jobId: jobId)
        }
    }

    // MARK: - (无其他 RPC 辅助方法)
}

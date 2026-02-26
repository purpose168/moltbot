#if DEBUG
/// CronJobEditor 测试扩展
/// 
/// 包含用于测试的 CronJobEditor 扩展方法
extension CronJobEditor {
    /// 用于测试的练习方法
    /// 
    /// 填充测试数据并调用各种方法以确保它们正常工作
    mutating func exerciseForTesting() {
        self.name = "测试作业"
        self.description = "测试描述"
        self.agentId = "ops"
        self.enabled = true
        self.sessionTarget = .isolated
        self.wakeMode = .now

        self.scheduleKind = .every
        self.everyText = "15m"

        self.payloadKind = .agentTurn
        self.agentMessage = "运行诊断"
        self.deliver = true
        self.channel = "last"
        self.to = "+15551230000"
        self.thinking = "low"
        self.timeoutSeconds = "90"
        self.bestEffortDeliver = true
        self.postPrefix = "Cron"

        _ = self.buildAgentTurnPayload()
        _ = try? self.buildPayload()
        _ = self.formatDuration(ms: 45000)
    }
}
#endif

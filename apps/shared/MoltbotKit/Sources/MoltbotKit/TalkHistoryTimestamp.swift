public enum TalkHistoryTimestamp: Sendable {
    /// 网关历史时间戳在历史上以秒（Double，纪元秒）或毫秒（Double，纪元毫秒）的形式发出。此助手方法可接受任意一种格式。
    public static func isAfter(_ timestamp: Double, sinceSeconds: Double) -> Bool {
        let sinceMs = sinceSeconds * 1000
        // 约为纪元秒的 2286-11-20。任何大于此值的几乎可以肯定是纪元毫秒。
        if timestamp > 10_000_000_000 {
            return timestamp >= sinceMs - 500
        }
        return timestamp >= sinceSeconds - 0.5
    }
}

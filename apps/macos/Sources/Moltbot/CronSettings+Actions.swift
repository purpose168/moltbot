import MoltbotProtocol
import Foundation

/// CronSettings 操作扩展
/// 
/// 包含 CronSettings 的操作相关扩展方法
extension CronSettings {
    /// 保存作业
    /// - Parameter payload: 作业有效载荷
    func save(payload: [String: AnyCodable]) async {
        guard !self.isSaving else { return }
        self.isSaving = true
        self.editorError = nil
        do {
            try await self.store.upsertJob(id: self.editingJob?.id, payload: payload)
            await MainActor.run {
                self.isSaving = false
                self.showEditor = false
                self.editingJob = nil
            }
        } catch {
            await MainActor.run {
                self.isSaving = false
                self.editorError = error.localizedDescription
            }
        }
    }
}

import Foundation

extension FileHandle {
    /// 使用抛出异常的 FileHandle API 读取直到 EOF,失败时返回空的 `Data`。
    ///
    /// 重要提示:避免使用遗留的、不抛出异常的 FileHandle 读取 API(例如 `readDataToEndOfFile()` 和
    /// `availableData`)。当文件句柄关闭或无效时,它们可能会抛出 Objective-C 异常,这将导致进程终止。
    func readToEndSafely() -> Data {
        do {
            return try self.readToEnd() ?? Data()
        } catch {
            return Data()
        }
    }

    /// 使用抛出异常的 FileHandle API 读取最多 `count` 个字节,失败或到达 EOF 时返回空的 `Data`。
    ///
    /// 重要提示:在如 `readabilityHandler` 等回调中使用此方法代替 `availableData`,以避免
    /// Objective-C 异常终止进程。
    func readSafely(upToCount count: Int) -> Data {
        do {
            return try self.read(upToCount: count) ?? Data()
        } catch {
            return Data()
        }
    }
}

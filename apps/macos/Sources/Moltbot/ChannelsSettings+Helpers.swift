import AppKit

/// ChannelsSettings 扩展，提供辅助方法
extension ChannelsSettings {
    /// 将毫秒时间戳转换为 Date 对象
    /// - Parameter ms: 毫秒时间戳
    /// - Returns: 转换后的 Date 对象，如果输入为 nil 则返回 nil
    func date(fromMs ms: Double?) -> Date? {
        guard let ms else { return nil }  // 确保毫秒值不为 nil
        return Date(timeIntervalSince1970: ms / 1000)  // 将毫秒转换为秒并创建 Date 对象
    }

    /// 从 data URL 创建 QR 码图像
    /// - Parameter dataUrl: 包含 base64 编码图像数据的 data URL
    /// - Returns: 创建的 NSImage 对象，如果解析失败则返回 nil
    func qrImage(from dataUrl: String) -> NSImage? {
        guard let comma = dataUrl.firstIndex(of: ",") else { return nil }  // 找到 URL 中逗号的位置
        let header = dataUrl[..<comma]  // 提取 URL 头部
        guard header.contains("base64") else { return nil }  // 确保包含 base64 编码标记
        let base64 = dataUrl[dataUrl.index(after: comma)...]  // 提取 base64 编码数据
        guard let data = Data(base64Encoded: String(base64)) else { return nil }  // 将 base64 字符串解码为数据
        return NSImage(data: data)  // 使用解码后的数据创建 NSImage
    }
}

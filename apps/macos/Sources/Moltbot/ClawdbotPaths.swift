import Foundation

enum MoltbotEnv {
    /// 获取环境变量的值并进行标准化处理
    /// - 参数 key: 环境变量的键名
    /// - 返回值: 标准化后的环境变量值，如果不存在或为空则返回 nil
    static func path(_ key: String) -> String? {
        // 标准化环境变量覆盖值，确保 UI 和文件 IO 保持一致
        guard let raw = getenv(key) else { return nil }
        let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty
        else {
            return nil
        }
        return value
    }
}

enum MoltbotPaths {
    /// 配置文件路径的环境变量键名
    private static let configPathEnv = "CLAWDBOT_CONFIG_PATH"
    /// 状态目录路径的环境变量键名
    private static let stateDirEnv = "CLAWDBOT_STATE_DIR"

    /// 状态目录的 URL
    /// - 如果设置了环境变量 CLAWDBOT_STATE_DIR，则使用该值
    /// - 否则使用用户主目录下的 .clawdbot 文件夹
    static var stateDirURL: URL {
        if let override = MoltbotEnv.path(self.stateDirEnv) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager().homeDirectoryForCurrentUser
            .appendingPathComponent(".clawdbot", isDirectory: true)
    }

    /// 配置文件的 URL
    /// - 如果设置了环境变量 CLAWDBOT_CONFIG_PATH，则使用该值
    /// - 否则使用状态目录下的 moltbot.json 文件
    static var configURL: URL {
        if let override = MoltbotEnv.path(self.configPathEnv) {
            return URL(fileURLWithPath: override)
        }
        return self.stateDirURL.appendingPathComponent("moltbot.json")
    }

    /// 工作区的 URL
    /// - 使用状态目录下的 workspace 文件夹
    static var workspaceURL: URL {
        self.stateDirURL.appendingPathComponent("workspace", isDirectory: true)
    }
}

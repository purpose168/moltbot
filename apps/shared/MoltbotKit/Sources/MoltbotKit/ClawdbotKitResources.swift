import Foundation

/// MoltbotKit 资源定位枚举
///
/// 提供资源包定位功能，确保在不同环境下都能正确找到资源
public enum MoltbotKitResources {
    /// MoltbotKit 的资源包
    ///
    /// 定位 SwiftPM 生成的资源包，检查多个位置：
    /// 1. 在 Bundle.main 内部（打包的应用程序）
    /// 2. Bundle.module（SwiftPM 开发/测试）
    /// 3. 如果未找到，则回退到 Bundle.main（资源查找将返回 nil）
    ///
    /// 这样可以避免在 Bundle.module 无法定位其资源时发生致命崩溃
    /// 在打包的 .app 捆绑包中，资源包路径与 SwiftPM 的期望不同。
    public static let bundle: Bundle = locateBundle()

    /// 资源包名称
    private static let bundleName = "MoltbotKit_MoltbotKit"

    /// 定位资源包的方法
    ///
    /// 按顺序检查多个位置，确保在不同环境下都能找到资源包
    /// - Returns: 找到的资源包，如果未找到则返回 Bundle.main
    private static func locateBundle() -> Bundle {
        // 1. 检查 Bundle.main 内部（打包的应用程序将资源复制到此处）
        if let mainResourceURL = Bundle.main.resourceURL {
            let bundleURL = mainResourceURL.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: bundleURL) {
                return bundle
            }
        }

        // 2. 直接检查 Bundle.main 中的嵌入资源
        if Bundle.main.url(forResource: "tool-display", withExtension: "json") != nil {
            return Bundle.main
        }

        // 3. 尝试 Bundle.module（在 SwiftPM 开发/测试中有效）
        // 包装在函数中以延迟 fatalError 直到实际调用
        if let moduleBundle = loadModuleBundleSafely() {
            return moduleBundle
        }

        // 4. 回退：返回 Bundle.main（资源查找将优雅地返回 nil）
        return Bundle.main
    }

    /// 安全加载模块资源包
    ///
    /// 手动检查可能的位置以避免 Bundle.module 找不到时的崩溃
    /// - Returns: 找到的模块资源包，如果未找到则返回 nil
    private static func loadModuleBundleSafely() -> Bundle? {
        // Bundle.module 由 SwiftPM 生成，如果未找到将触发 fatalError。
        // 我们手动检查可能的位置以避免崩溃。
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle(for: BundleLocator.self).resourceURL,
            Bundle(for: BundleLocator.self).bundleURL,
        ]

        // 遍历所有可能的位置
        for candidate in candidates {
            guard let baseURL = candidate else { continue }

            // 直接路径
            let directURL = baseURL.appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: directURL) {
                return bundle
            }

            // 在 Resources/ 目录内
            let resourcesURL = baseURL
                .appendingPathComponent("Resources")
                .appendingPathComponent("\(bundleName).bundle")
            if let bundle = Bundle(url: resourcesURL) {
                return bundle
            }
        }

        // 所有位置都未找到，返回 nil
        return nil
    }
}

/// 用于通过 Bundle(for:) 查找捆绑包的辅助类
private final class BundleLocator {}

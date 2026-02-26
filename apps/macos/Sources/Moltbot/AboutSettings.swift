import SwiftUI

/// 关于设置页面
/// 显示应用程序的基本信息、版本号、构建信息以及相关链接
struct AboutSettings: View {
    /// 更新控制器，用于检查和管理应用更新
    weak var updater: UpdaterProviding?
    /// 图标悬停状态
    @State private var iconHover = false
    /// 是否启用自动更新检查
    @AppStorage("autoUpdateEnabled") private var autoCheckEnabled = true
    /// 是否已加载更新器状态
    @State private var didLoadUpdaterState = false

    var body: some View {
        VStack(spacing: 8) {
            // 获取应用图标，若不存在则使用默认图标
            let appIcon = NSApplication.shared.applicationIconImage ?? CritterIconRenderer.makeIcon(blink: 0)
            // 应用图标按钮，点击跳转到GitHub仓库
            Button {
                if let url = URL(string: "https://github.com/moltbot/moltbot") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 160, height: 160)
                    .cornerRadius(24)
                    .shadow(color: self.iconHover ? .accentColor.opacity(0.25) : .clear, radius: 10)
                    .scaleEffect(self.iconHover ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .pointingHandCursor()
            .onHover { hover in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { self.iconHover = hover }
            }

            // 应用信息区域
            VStack(spacing: 3) {
                Text("Moltbot")
                    .font(.title3.bold())
                Text("版本 \(self.versionString)")
                    .foregroundStyle(.secondary)
                if let buildTimestamp {
                    Text("构建于 \(buildTimestamp)\(self.buildSuffix)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("菜单栏助手，用于通知、截图和特权代理操作。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
            }

            // 链接区域
            VStack(alignment: .center, spacing: 6) {
                AboutLinkRow(
                    icon: "chevron.left.slash.chevron.right",
                    title: "GitHub",
                    url: "https://github.com/moltbot/moltbot")
                AboutLinkRow(icon: "globe", title: "网站", url: "https://steipete.me")
                AboutLinkRow(icon: "bird", title: "Twitter", url: "https://twitter.com/steipete")
                AboutLinkRow(icon: "envelope", title: "邮箱", url: "mailto:peter@steipete.me")
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)

            // 更新设置区域
            if let updater {
                Divider()
                    .padding(.vertical, 8)

                if updater.isAvailable {
                    VStack(spacing: 10) {
                        Toggle("自动检查更新", isOn: self.$autoCheckEnabled)
                            .toggleStyle(.checkbox)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Button("检查更新…") { updater.checkForUpdates(nil) }
                    }
                } else {
                    Text("此构建版本不支持更新。")
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            // 版权信息
            Text("© 2025 Peter Steinberger — MIT 许可证。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear {
            guard let updater, !self.didLoadUpdaterState else { return }
            // 保持 Sparkle 的自动检查设置与持久化的开关同步
            updater.automaticallyChecksForUpdates = self.autoCheckEnabled
            updater.automaticallyDownloadsUpdates = self.autoCheckEnabled
            self.didLoadUpdaterState = true
        }
        .onChange(of: self.autoCheckEnabled) { _, newValue in
            // 当自动更新设置改变时，同步到更新器
            self.updater?.automaticallyChecksForUpdates = newValue
            self.updater?.automaticallyDownloadsUpdates = newValue
        }
    }

    /// 版本字符串
    /// 格式为：版本号 (构建号)
    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    /// 构建时间戳
    /// 将 ISO8601 格式的时间戳转换为本地日期时间格式
    private var buildTimestamp: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "MoltbotBuildTimestamp") as? String
        else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        guard let date = parser.date(from: raw) else { return raw }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current
        return formatter.string(from: date)
    }

    /// Git 提交哈希
    private var gitCommit: String {
        Bundle.main.object(forInfoDictionaryKey: "MoltbotGitCommit") as? String ?? "unknown"
    }

    /// 应用程序包标识符
    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    /// 构建后缀信息
    /// 包含 Git 提交哈希和调试版本标记
    private var buildSuffix: String {
        let git = self.gitCommit
        guard !git.isEmpty, git != "unknown" else { return "" }

        var suffix = " (\(git)"
        #if DEBUG
        suffix += " 调试版本"
        #endif
        suffix += ")"
        return suffix
    }
}

@MainActor
/// 关于页面中的链接行项目
private struct AboutLinkRow: View {
    /// 系统图标名称
    let icon: String
    /// 链接标题
    let title: String
    /// 链接 URL
    let url: String

    /// 悬停状态
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: self.icon)
                Text(self.title)
                    .underline(self.hovering, color: .accentColor)
            }
            .foregroundColor(.accentColor)
        }
        .buttonStyle(.plain)
        .onHover { self.hovering = $0 }
        .pointingHandCursor()
    }
}

/// 关于页面中的元数据行项目
private struct AboutMetaRow: View {
    /// 标签文本
    let label: String
    /// 值文本
    let value: String

    var body: some View {
        HStack {
            Text(self.label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(self.value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
        }
    }
}

#if DEBUG
/// 关于设置页面的预览
struct AboutSettings_Previews: PreviewProvider {
    /// 禁用的更新控制器，用于预览
    private static let updater = DisabledUpdaterController()
    static var previews: some View {
        AboutSettings(updater: updater)
            .frame(width: SettingsTab.windowWidth, height: SettingsTab.windowHeight)
    }
}
#endif

import SwiftUI

/// 配置设置视图
/// 
/// 用于显示和编辑应用程序配置的SwiftUI视图
@MainActor
struct ConfigSettings: View {
    /// 是否为预览模式
    private let isPreview = ProcessInfo.processInfo.isPreview
    /// 是否为Nix模式
    private let isNixMode = ProcessInfo.processInfo.isNixMode
    /// 通道存储
    @Bindable var store: ChannelsStore
    /// 是否已加载配置
    @State private var hasLoaded = false
    /// 当前激活的节段键
    @State private var activeSectionKey: String?
    /// 当前激活的子节段
    @State private var activeSubsection: SubsectionSelection?

    /// 初始化配置设置视图
    /// - Parameter store: 通道存储，默认为共享实例
    init(store: ChannelsStore = .shared) {
        self.store = store
    }

    var body: some View {
        HStack(spacing: 16) {
            self.sidebar
            self.detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            guard !self.hasLoaded else { return }
            guard !self.isPreview else { return }
            self.hasLoaded = true
            await self.store.loadConfigSchema()
            await self.store.loadConfig()
        }
        .onAppear { self.ensureSelection() }
        .onChange(of: self.store.configSchemaLoading) { _, loading in
            if !loading { self.ensureSelection() }
        }
    }
}

extension ConfigSettings {
    /// 子节段选择枚举
    private enum SubsectionSelection: Hashable {
        /// 全部
        case all
        /// 特定键
        case key(String)
    }

    /// 配置节段
    private struct ConfigSection: Identifiable {
        /// 键
        let key: String
        /// 标签
        let label: String
        /// 帮助文本
        let help: String?
        /// 模式节点
        let node: ConfigSchemaNode

        /// 标识符
        var id: String { self.key }
    }

    /// 配置子节段
    private struct ConfigSubsection: Identifiable {
        /// 键
        let key: String
        /// 标签
        let label: String
        /// 帮助文本
        let help: String?
        /// 模式节点
        let node: ConfigSchemaNode
        /// 配置路径
        let path: ConfigPath

        /// 标识符
        var id: String { self.key }
    }

    /// 节段列表
    private var sections: [ConfigSection] {
        guard let schema = self.store.configSchema else { return [] }
        return self.resolveSections(schema)
    }

    /// 当前激活的节段
    private var activeSection: ConfigSection? {
        self.sections.first { $0.key == self.activeSectionKey }
    }

    /// 侧边栏视图
    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if self.sections.isEmpty {
                    Text("No config sections available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                } else {
                    ForEach(self.sections) { section in
                        self.sidebarRow(section)
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
        }
        .frame(minWidth: 220, idealWidth: 240, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 详情视图
    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            if self.store.configSchemaLoading {
                ProgressView().controlSize(.small)
            } else if let section = self.activeSection {
                self.sectionDetail(section)
            } else if self.store.configSchema != nil {
                self.emptyDetail
            } else {
                Text("Schema unavailable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 空详情视图
    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            self.header
            Text("Select a config section to view settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// 节段详情视图
    /// - Parameter section: 配置节段
    /// - Returns: 节段详情视图
    private func sectionDetail(_ section: ConfigSection) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                self.header
                if let status = self.store.configStatus {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                self.actionRow
                self.sectionHeader(section)
                self.subsectionNav(section)
                self.sectionForm(section)
                if self.store.configDirty, !self.isNixMode {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .groupBoxStyle(PlainSettingsGroupBoxStyle())
        }
    }

    /// 头部视图
    @ViewBuilder
    private var header: some View {
        Text("Config")
            .font(.title3.weight(.semibold))
        Text(self.isNixMode
            ? "This tab is read-only in Nix mode. Edit config via Nix and rebuild."
            : "Edit ~/.clawdbot/moltbot.json using the schema-driven form.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    /// 节段头部视图
    /// - Parameter section: 配置节段
    /// - Returns: 节段头部视图
    private func sectionHeader(_ section: ConfigSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.label)
                .font(.title3.weight(.semibold))
            if let help = section.help {
                Text(help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 操作行视图
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Reload") {
                Task { await self.store.reloadConfigDraft() }
            }
            .disabled(!self.store.configLoaded)

            Button(self.store.isSavingConfig ? "Saving…" : "Save") {
                Task { await self.store.saveConfigDraft() }
            }
            .disabled(self.isNixMode || self.store.isSavingConfig || !self.store.configDirty)
        }
        .buttonStyle(.bordered)
    }

    /// 侧边栏行视图
    /// - Parameter section: 配置节段
    /// - Returns: 侧边栏行视图
    private func sidebarRow(_ section: ConfigSection) -> some View {
        let isSelected = self.activeSectionKey == section.key
        return Button {
            self.selectSection(section)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.label)
                if let help = section.help {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// 子节段导航视图
    /// - Parameter section: 配置节段
    /// - Returns: 子节段导航视图
    @ViewBuilder
    private func subsectionNav(_ section: ConfigSection) -> some View {
        let subsections = self.resolveSubsections(for: section)
        if subsections.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    self.subsectionButton(
                        title: "All",
                        isSelected: self.activeSubsection == .all)
                    {
                        self.activeSubsection = .all
                    }
                    ForEach(subsections) {
                        self.subsectionButton(
                            title: $0.label,
                            isSelected: self.activeSubsection == .key($0.key))
                        {
                            self.activeSubsection = .key($0.key)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    /// 子节段按钮
    /// - Parameters:
    ///   - title: 按钮标题
    ///   - isSelected: 是否被选中
    ///   - action: 点击回调
    /// - Returns: 子节段按钮视图
    private func subsectionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 节段表单视图
    /// - Parameter section: 配置节段
    /// - Returns: 节段表单视图
    private func sectionForm(_ section: ConfigSection) -> some View {
        let subsection = self.activeSubsection
        let defaultPath: ConfigPath = [.key(section.key)]
        let subsections = self.resolveSubsections(for: section)
        let resolved: (ConfigSchemaNode, ConfigPath) = {
            if case let .key(key) = subsection,
               let match = subsections.first(where: { $0.key == key })
            {
                return (match.node, match.path)
            }
            return (self.resolvedSchemaNode(section.node), defaultPath)
        }()

        return ConfigSchemaForm(store: self.store, schema: resolved.0, path: resolved.1)
            .disabled(self.isNixMode)
    }

    /// 确保选择
    private func ensureSelection() {
        guard let schema = self.store.configSchema else { return }
        let sections = self.resolveSections(schema)
        guard !sections.isEmpty else { return }

        let active = sections.first { $0.key == self.activeSectionKey } ?? sections[0]
        if self.activeSectionKey != active.key {
            self.activeSectionKey = active.key
        }
        self.ensureSubsection(for: active)
    }

    /// 确保子节段选择
    /// - Parameter section: 配置节段
    private func ensureSubsection(for section: ConfigSection) {
        let subsections = self.resolveSubsections(for: section)
        guard !subsections.isEmpty else {
            self.activeSubsection = nil
            return
        }

        switch self.activeSubsection {
        case .all:
            return
        case let .key(key):
            if subsections.contains(where: { $0.key == key }) { return }
        case .none:
            break
        }

        if let first = subsections.first {
            self.activeSubsection = .key(first.key)
        }
    }

    /// 选择节段
    /// - Parameter section: 配置节段
    private func selectSection(_ section: ConfigSection) {
        guard self.activeSectionKey != section.key else { return }
        self.activeSectionKey = section.key
        let subsections = self.resolveSubsections(for: section)
        if let first = subsections.first {
            self.activeSubsection = .key(first.key)
        } else {
            self.activeSubsection = nil
        }
    }

    /// 解析节段
    /// - Parameter root: 根配置模式节点
    /// - Returns: 配置节段列表
    private func resolveSections(_ root: ConfigSchemaNode) -> [ConfigSection] {
        let node = self.resolvedSchemaNode(root)
        let hints = self.store.configUiHints
        let keys = node.properties.keys.sorted { lhs, rhs in
            let orderA = hintForPath([.key(lhs)], hints: hints)?.order ?? 0
            let orderB = hintForPath([.key(rhs)], hints: hints)?.order ?? 0
            if orderA != orderB { return orderA < orderB }
            return lhs < rhs
        }

        return keys.compactMap { key in
            guard let child = node.properties[key] else { return nil }
            let path: ConfigPath = [.key(key)]
            let hint = hintForPath(path, hints: hints)
            let label = hint?.label
                ?? child.title
                ?? self.humanize(key)
            let help = hint?.help ?? child.description
            return ConfigSection(key: key, label: label, help: help, node: child)
        }
    }

    /// 解析子节段
    /// - Parameter section: 配置节段
    /// - Returns: 配置子节段列表
    private func resolveSubsections(for section: ConfigSection) -> [ConfigSubsection] {
        let node = self.resolvedSchemaNode(section.node)
        guard node.schemaType == "object" else { return [] }
        let hints = self.store.configUiHints
        let keys = node.properties.keys.sorted { lhs, rhs in
            let orderA = hintForPath([.key(section.key), .key(lhs)], hints: hints)?.order ?? 0
            let orderB = hintForPath([.key(section.key), .key(rhs)], hints: hints)?.order ?? 0
            if orderA != orderB { return orderA < orderB }
            return lhs < rhs
        }

        return keys.compactMap { key in
            guard let child = node.properties[key] else { return nil }
            let path: ConfigPath = [.key(section.key), .key(key)]
            let hint = hintForPath(path, hints: hints)
            let label = hint?.label
                ?? child.title
                ?? self.humanize(key)
            let help = hint?.help ?? child.description
            return ConfigSubsection(
                key: key,
                label: label,
                help: help,
                node: child,
                path: path)
        }
    }

    /// 解析模式节点
    /// - Parameter node: 配置模式节点
    /// - Returns: 解析后的配置模式节点
    private func resolvedSchemaNode(_ node: ConfigSchemaNode) -> ConfigSchemaNode {
        let variants = node.anyOf.isEmpty ? node.oneOf : node.anyOf
        if !variants.isEmpty {
            let nonNull = variants.filter { !$0.isNullSchema }
            if nonNull.count == 1, let only = nonNull.first { return only }
        }
        return node
    }

    /// 人性化键名
    /// - Parameter key: 原始键名
    /// - Returns: 人性化后的键名
    private func humanize(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}

/// 配置设置预览
struct ConfigSettings_Previews: PreviewProvider {
    static var previews: some View {
        ConfigSettings()
    }
}
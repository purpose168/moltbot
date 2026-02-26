import SwiftUI

/// ChannelsSettings 的视图扩展
/// 提供频道设置界面的完整 UI 实现
extension ChannelsSettings {
    /// 主视图布局
    var body: some View {
        HStack(spacing: 0) {
            self.sidebar        // 左侧边栏
            self.detail         // 右侧详情
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            self.store.start()      // 启动存储服务
            self.ensureSelection()  // 确保有选中项
        }
        .onChange(of: self.orderedChannels) { _, _ in
            self.ensureSelection()  // 当频道列表变化时重新确保选中项
        }
        .onDisappear { self.store.stop() }  // 视图消失时停止存储服务
    }

    /// 侧边栏视图
    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                // 已配置的频道部分
                if !self.enabledChannels.isEmpty {
                    self.sidebarSectionHeader("Configured")
                    ForEach(self.enabledChannels) { channel in
                        self.sidebarRow(channel)
                    }
                }

                // 可用的频道部分
                if !self.availableChannels.isEmpty {
                    self.sidebarSectionHeader("Available")
                    ForEach(self.availableChannels) { channel in
                        self.sidebarRow(channel)
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
        Group {
            if let channel = self.selectedChannel {
                self.channelDetail(channel)  // 显示选中频道的详情
            } else {
                self.emptyDetail             // 显示空状态
            }
        }
        .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 空详情视图
    private var emptyDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Channels")
                .font(.title3.weight(.semibold))
            Text("Select a channel to view status and settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    /// 频道详情视图
    private func channelDetail(_ channel: ChannelItem) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                self.detailHeader(for: channel)  // 详情头部
                Divider()
                self.channelSection(channel)     // 频道设置部分
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
    }

    /// 侧边栏行视图
    private func sidebarRow(_ channel: ChannelItem) -> some View {
        let isSelected = self.selectedChannel == channel
        return Button {
            self.selectedChannel = channel  // 点击时选择频道
        } label: {
            HStack(spacing: 8) {
                // 频道状态指示器
                Circle()
                    .fill(self.channelTint(channel))
                    .frame(width: 8, height: 8)
                // 频道信息
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title)
                    Text(self.channelSummary(channel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(Color.clear) // 确保全宽点击区域
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// 侧边栏部分头部
    private func sidebarSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    /// 详情头部视图
    private func detailHeader(for channel: ChannelItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // 频道标题和图标
                Label(channel.detailTitle, systemImage: channel.systemImage)
                    .font(.title3.weight(.semibold))
                // 状态徽章
                self.statusBadge(
                    self.channelSummary(channel),
                    color: self.channelTint(channel))
                Spacer()
                // 频道头部操作
                self.channelHeaderActions(channel)
            }

            HStack(spacing: 10) {
                // 最后检查时间
                Text("Last check \(self.channelLastCheckText(channel))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // 错误状态指示器
                if self.channelHasError(channel) {
                    Text("Error")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
                        .clipShape(Capsule())
                }
            }

            // 频道详情信息
            if let details = self.channelDetails(channel) {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 状态徽章视图
    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

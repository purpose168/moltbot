import SwiftUI

/// ChannelsSettings 扩展，提供频道设置相关的视图组件
/// 包含表单部分、频道头部操作、WhatsApp 特定设置和通用频道设置
/// 以及配置编辑器部分和配置状态消息

extension ChannelsSettings {
    /// 创建一个带标题的表单部分
    /// - Parameters:
    ///   - title: 表单部分的标题
    ///   - content: 表单内容的视图构建器
    /// - Returns: 包含表单内容的 GroupBox 视图
    func formSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 为频道头部创建操作按钮
    /// - Parameter channel: 频道项
    /// - Returns: 包含操作按钮的水平堆栈视图
    @ViewBuilder
    func channelHeaderActions(_ channel: ChannelItem) -> some View {
        HStack(spacing: 8) {
            // WhatsApp 频道的登出按钮
            if channel.id == "whatsapp" {
                Button("登出") {
                    Task { await self.store.logoutWhatsApp() }
                }
                .buttonStyle(.bordered)
                .disabled(self.store.whatsappBusy)
            }

            // Telegram 频道的登出按钮
            if channel.id == "telegram" {
                Button("登出") {
                    Task { await self.store.logoutTelegram() }
                }
                .buttonStyle(.bordered)
                .disabled(self.store.telegramBusy)
            }

            // 刷新按钮
            Button {
                Task { await self.store.refresh(probe: true) }
            } label: {
                if self.store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Text("刷新")
                }
            }
            .buttonStyle(.bordered)
            .disabled(self.store.isRefreshing)
        }
        .controlSize(.small)
    }

    /// WhatsApp 频道的设置部分
    var whatsAppSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 链接部分
            self.formSection("链接") {
                // 显示 WhatsApp 登录消息
                if let message = self.store.whatsappLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // 显示 WhatsApp 登录二维码
                if let qr = self.store.whatsappLoginQrDataUrl, let image = self.qrImage(from: qr) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 180, height: 180)
                        .cornerRadius(8)
                }

                // 操作按钮
                HStack(spacing: 12) {
                    // 显示 QR 码按钮
                    Button {
                        Task { await self.store.startWhatsAppLogin(force: false) }
                    } label: {
                        if self.store.whatsappBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("显示二维码")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(self.store.whatsappBusy)

                    // 重新链接按钮
                    Button("重新链接") {
                        Task { await self.store.startWhatsAppLogin(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.store.whatsappBusy)
                }
                .font(.caption)
            }

            // 配置编辑器部分
            self.configEditorSection(channelId: "whatsapp")
        }
    }

    /// 为通用频道创建设置部分
    /// - Parameter channel: 频道项
    /// - Returns: 包含配置编辑器的垂直堆栈视图
    @ViewBuilder
    func genericChannelSection(_ channel: ChannelItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            self.configEditorSection(channelId: channel.id)
        }
    }

    /// 创建配置编辑器部分
    /// - Parameter channelId: 频道 ID
    /// - Returns: 包含配置表单和操作按钮的视图
    @ViewBuilder
    private func configEditorSection(channelId: String) -> some View {
        // 配置表单部分
        self.formSection("配置") {
            ChannelConfigForm(store: self.store, channelId: channelId)
        }

        // 配置状态消息
        self.configStatusMessage

        // 操作按钮
        HStack(spacing: 12) {
            // 保存按钮
            Button {
                Task { await self.store.saveConfigDraft() }
            } label: {
                if self.store.isSavingConfig {
                    ProgressView().controlSize(.small)
                } else {
                    Text("保存")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(self.store.isSavingConfig || !self.store.configDirty)

            // 重新加载按钮
            Button("重新加载") {
                Task { await self.store.reloadConfigDraft() }
            }
            .buttonStyle(.bordered)
            .disabled(self.store.isSavingConfig)

            Spacer()
        }
        .font(.caption)
    }

    /// 配置状态消息视图
    @ViewBuilder
    var configStatusMessage: some View {
        if let status = self.store.configStatus {
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

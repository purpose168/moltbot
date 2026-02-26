import AppKit
import Combine
import SwiftUI

/// Anthropic OAuth 认证控制界面
/// 用于管理与 Anthropic API 的 OAuth 认证过程，包括状态显示、认证启动和完成
@MainActor
struct AnthropicAuthControls: View {
    /// 连接模式，用于确定是否可以在本地进行 OAuth 认证
    let connectionMode: AppState.ConnectionMode

    /// OAuth 认证状态
    @State private var oauthStatus: MoltbotOAuthStore.AnthropicOAuthStatus = MoltbotOAuthStore.anthropicOAuthStatus()
    /// PKCE 挑战参数，用于 OAuth 认证过程
    @State private var pkce: AnthropicOAuth.PKCE?
    /// 用户输入的认证代码
    @State private var code: String = ""
    /// 是否正在处理认证操作
    @State private var busy = false
    /// 状态提示文本
    @State private var statusText: String?
    /// 是否自动从剪贴板检测认证代码
    @State private var autoDetectClipboard = true
    /// 检测到认证代码后是否自动连接
    @State private var autoConnectClipboard = true
    /// 上次剪贴板更改计数，用于检测剪贴板变化
    @State private var lastPasteboardChangeCount = NSPasteboard.general.changeCount

    /// 剪贴板轮询定时器
    /// 用于定期检查剪贴板是否包含认证代码
    private static let clipboardPoll: AnyPublisher<Date, Never> = {
        if ProcessInfo.processInfo.isRunningTests {
            return Empty(completeImmediately: false).eraseToAnyPublisher()
        }
        return Timer.publish(every: 0.4, on: .main, in: .common)
            .autoconnect()
            .eraseToAnyPublisher()
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 非本地连接模式提示
            if self.connectionMode != .local {
                Text("网关未在本地运行；OAuth 必须在网关主机上创建。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 认证状态显示
            HStack(spacing: 10) {
                Circle()
                    .fill(self.oauthStatus.isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(self.oauthStatus.shortDescription)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("显示文件") {
                    NSWorkspace.shared.activateFileViewerSelecting([MoltbotOAuthStore.oauthURL()])
                }
                .buttonStyle(.bordered)
                .disabled(!FileManager().fileExists(atPath: MoltbotOAuthStore.oauthURL().path))

                Button("刷新") {
                    self.refresh()
                }
                .buttonStyle(.bordered)
            }

            // OAuth 文件路径显示
            Text(MoltbotOAuthStore.oauthURL().path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            // 认证操作按钮
            HStack(spacing: 12) {
                Button {
                    self.startOAuth()
                } label: {
                    if self.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(self.oauthStatus.isConnected ? "重新认证 (OAuth)" : "打开登录 (OAuth)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(self.connectionMode != .local || self.busy)

                // 取消按钮（仅在认证过程中显示）
                if self.pkce != nil {
                    Button("取消") {
                        self.pkce = nil
                        self.code = ""
                        self.statusText = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.busy)
                }
            }

            // 认证代码输入区域
            if self.pkce != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("粘贴 `code#state`")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TextField("code#state", text: self.$code)
                        .textFieldStyle(.roundedBorder)
                        .disabled(self.busy)

                    Toggle("从剪贴板自动检测", isOn: self.$autoDetectClipboard)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .disabled(self.busy)

                    Toggle("检测到后自动连接", isOn: self.$autoConnectClipboard)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .disabled(self.busy)

                    Button("连接") {
                        Task { await self.finishOAuth() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(self.busy || self.connectionMode != .local || self.code
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty)
                }
            }

            // 状态提示文本
            if let statusText, !statusText.isEmpty {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            self.refresh()
        }
        .onReceive(Self.clipboardPoll) { _ in
            self.pollClipboardIfNeeded()
        }
    }

    /// 刷新 OAuth 认证状态
    private func refresh() {
        // 尝试导入旧的 Anthropic OAuth 凭据
        let imported = MoltbotOAuthStore.importLegacyAnthropicOAuthIfNeeded()
        // 更新 OAuth 状态
        self.oauthStatus = MoltbotOAuthStore.anthropicOAuthStatus()
        if imported != nil {
            self.statusText = "已导入现有的 OAuth 凭据。"
        }
    }

    /// 启动 OAuth 认证流程
    private func startOAuth() {
        // 仅在本地连接模式下允许
        guard self.connectionMode == .local else { return }
        guard !self.busy else { return }
        self.busy = true
        defer { self.busy = false }

        do {
            // 生成 PKCE 挑战参数
            let pkce = try AnthropicOAuth.generatePKCE()
            self.pkce = pkce
            // 构建授权 URL 并打开浏览器
            let url = AnthropicOAuth.buildAuthorizeURL(pkce: pkce)
            NSWorkspace.shared.open(url)
            self.statusText = "已打开浏览器。批准后，请将 `code#state` 值粘贴到此处。"
        } catch {
            self.statusText = "启动 OAuth 失败：\(error.localizedDescription)"
        }
    }

    /// 完成 OAuth 认证流程
    @MainActor
    private func finishOAuth() async {
        // 仅在本地连接模式下允许
        guard self.connectionMode == .local else { return }
        guard !self.busy else { return }
        guard let pkce = self.pkce else { return }
        self.busy = true
        defer { self.busy = false }

        // 解析认证代码
        guard let parsed = AnthropicOAuthCodeState.parse(from: self.code) else {
            self.statusText = "OAuth 失败：缺少或无效的代码/状态。"
            return
        }

        do {
            // 交换认证代码获取访问令牌
            let creds = try await AnthropicOAuth.exchangeCode(
                code: parsed.code,
                state: parsed.state,
                verifier: pkce.verifier)
            // 保存 OAuth 凭据
            try MoltbotOAuthStore.saveAnthropicOAuth(creds)
            // 刷新状态
            self.refresh()
            // 清除认证过程中的临时数据
            self.pkce = nil
            self.code = ""
            self.statusText = "已连接。Moltbot 现在可以通过 OAuth 使用 Claude。"
        } catch {
            self.statusText = "OAuth 失败：\(error.localizedDescription)"
        }
    }

    /// 检查剪贴板是否包含认证代码
    private func pollClipboardIfNeeded() {
        // 仅在本地连接模式下允许
        guard self.connectionMode == .local else { return }
        guard self.pkce != nil else { return }
        guard !self.busy else { return }
        guard self.autoDetectClipboard else { return }

        let pb = NSPasteboard.general
        let changeCount = pb.changeCount
        // 检查剪贴板是否有变化
        guard changeCount != self.lastPasteboardChangeCount else { return }
        self.lastPasteboardChangeCount = changeCount

        // 尝试获取剪贴板内容并解析认证代码
        guard let raw = pb.string(forType: .string), !raw.isEmpty else { return }
        guard let parsed = AnthropicOAuthCodeState.parse(from: raw) else { return }
        guard let pkce = self.pkce, parsed.state == pkce.verifier else { return }

        // 更新认证代码
        let next = "\(parsed.code)#\(parsed.state)"
        if self.code != next {
            self.code = next
            self.statusText = "已从剪贴板检测到 `code#state`。"
        }

        // 如果启用了自动连接，则自动完成认证
        guard self.autoConnectClipboard else { return }
        Task { await self.finishOAuth() }
    }
}

#if DEBUG
extension AnthropicAuthControls {
    /// 用于预览的初始化方法
    init(
        connectionMode: AppState.ConnectionMode,
        oauthStatus: MoltbotOAuthStore.AnthropicOAuthStatus,
        pkce: AnthropicOAuth.PKCE? = nil,
        code: String = "",
        busy: Bool = false,
        statusText: String? = nil,
        autoDetectClipboard: Bool = true,
        autoConnectClipboard: Bool = true)
    {
        self.connectionMode = connectionMode
        self._oauthStatus = State(initialValue: oauthStatus)
        self._pkce = State(initialValue: pkce)
        self._code = State(initialValue: code)
        self._busy = State(initialValue: busy)
        self._statusText = State(initialValue: statusText)
        self._autoDetectClipboard = State(initialValue: autoDetectClipboard)
        self._autoConnectClipboard = State(initialValue: autoConnectClipboard)
        self._lastPasteboardChangeCount = State(initialValue: NSPasteboard.general.changeCount)
    }
}
#endif

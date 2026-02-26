import MoltbotProtocol
import Foundation

/// ChannelsStore 的生命周期管理扩展
extension ChannelsStore {
    /// 启动轮询任务
    /// - 检查是否为预览模式，若是则直接返回
    /// - 检查轮询任务是否已存在，若已存在则直接返回
    /// - 创建分离的任务，执行以下操作：
    ///   1. 刷新通道状态（探测模式）
    ///   2. 加载配置模式
    ///   3. 加载配置
    ///   4. 循环执行刷新操作，直到任务被取消
    func start() {
        guard !self.isPreview else { return }          // 预览模式下不启动
        guard self.pollTask == nil else { return }     // 任务已存在则不重复创建
        self.pollTask = Task.detached { [weak self] in  // 创建分离的任务，避免强引用
            guard let self else { return }             // 弱引用捕获，防止循环引用
            await self.refresh(probe: true)             // 首次刷新，使用探测模式
            await self.loadConfigSchema()               // 加载配置模式
            await self.loadConfig()                     // 加载配置
            while !Task.isCancelled {                   // 循环执行，直到任务被取消
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))  // 等待指定间隔
                await self.refresh(probe: false)        // 非探测模式刷新
            }
        }
    }

    /// 停止轮询任务
    /// - 取消当前轮询任务
    /// - 将任务引用设置为 nil
    func stop() {
        self.pollTask?.cancel()    // 取消任务
        self.pollTask = nil        // 清空任务引用
    }

    /// 刷新通道状态
    /// - Parameter probe: 是否为探测模式
    func refresh(probe: Bool) async {
        guard !self.isRefreshing else { return }     // 正在刷新则直接返回
        self.isRefreshing = true                     // 设置刷新状态
        defer { self.isRefreshing = false }          // 延迟执行，确保刷新状态被重置

        do {
            let params: [String: AnyCodable] = [     // 构建请求参数
                "probe": AnyCodable(probe),         // 探测模式标志
                "timeoutMs": AnyCodable(8000),      // 超时时间
            ]
            // 发送请求并解码响应
            let snap: ChannelsStatusSnapshot = try await GatewayConnection.shared.requestDecoded(
                method: .channelsStatus,             // 请求方法
                params: params,                      // 请求参数
                timeoutMs: 12000)                    // 超时时间
            self.snapshot = snap                     // 更新快照
            self.lastSuccess = Date()                // 更新最后成功时间
            self.lastError = nil                     // 清空错误信息
        } catch {
            self.lastError = error.localizedDescription  // 记录错误信息
        }
    }

    /// 启动 WhatsApp 登录流程
    /// - Parameters:
    ///   - force: 是否强制登录
    ///   - autoWait: 是否自动等待登录完成
    func startWhatsAppLogin(force: Bool, autoWait: Bool = true) async {
        guard !self.whatsappBusy else { return }     // WhatsApp 操作忙则直接返回
        self.whatsappBusy = true                     // 设置忙状态
        defer { self.whatsappBusy = false }          // 延迟执行，确保忙状态被重置
        var shouldAutoWait = false                   // 是否自动等待标志
        do {
            let params: [String: AnyCodable] = [     // 构建请求参数
                "force": AnyCodable(force),         // 强制登录标志
                "timeoutMs": AnyCodable(30000),     // 超时时间
            ]
            // 发送请求并解码响应
            let result: WhatsAppLoginStartResult = try await GatewayConnection.shared.requestDecoded(
                method: .webLoginStart,              // 请求方法
                params: params,                      // 请求参数
                timeoutMs: 35000)                    // 超时时间
            self.whatsappLoginMessage = result.message       // 更新登录消息
            self.whatsappLoginQrDataUrl = result.qrDataUrl   // 更新二维码数据URL
            self.whatsappLoginConnected = nil                // 清空连接状态
            shouldAutoWait = autoWait && result.qrDataUrl != nil  // 决定是否自动等待
        } catch {
            self.whatsappLoginMessage = error.localizedDescription  // 记录错误信息
            self.whatsappLoginQrDataUrl = nil                       // 清空二维码数据URL
            self.whatsappLoginConnected = nil                       // 清空连接状态
        }
        await self.refresh(probe: true)             // 刷新通道状态
        if shouldAutoWait {
            Task { await self.waitWhatsAppLogin() }  // 自动等待登录完成
        }
    }

    /// 等待 WhatsApp 登录完成
    /// - Parameter timeoutMs: 超时时间（毫秒），默认 120000
    func waitWhatsAppLogin(timeoutMs: Int = 120_000) async {
        guard !self.whatsappBusy else { return }     // WhatsApp 操作忙则直接返回
        self.whatsappBusy = true                     // 设置忙状态
        defer { self.whatsappBusy = false }          // 延迟执行，确保忙状态被重置
        do {
            let params: [String: AnyCodable] = [     // 构建请求参数
                "timeoutMs": AnyCodable(timeoutMs), // 超时时间
            ]
            // 发送请求并解码响应
            let result: WhatsAppLoginWaitResult = try await GatewayConnection.shared.requestDecoded(
                method: .webLoginWait,               // 请求方法
                params: params,                      // 请求参数
                timeoutMs: Double(timeoutMs) + 5000) // 超时时间
            self.whatsappLoginMessage = result.message       // 更新登录消息
            self.whatsappLoginConnected = result.connected   // 更新连接状态
            if result.connected {
                self.whatsappLoginQrDataUrl = nil           // 连接成功则清空二维码
            }
        } catch {
            self.whatsappLoginMessage = error.localizedDescription  // 记录错误信息
        }
        await self.refresh(probe: true)             // 刷新通道状态
    }

    /// 登出 WhatsApp
    func logoutWhatsApp() async {
        guard !self.whatsappBusy else { return }     // WhatsApp 操作忙则直接返回
        self.whatsappBusy = true                     // 设置忙状态
        defer { self.whatsappBusy = false }          // 延迟执行，确保忙状态被重置
        do {
            let params: [String: AnyCodable] = [     // 构建请求参数
                "channel": AnyCodable("whatsapp"), // 通道名称
            ]
            // 发送请求并解码响应
            let result: ChannelLogoutResult = try await GatewayConnection.shared.requestDecoded(
                method: .channelsLogout,             // 请求方法
                params: params,                      // 请求参数
                timeoutMs: 15000)                    // 超时时间
            // 根据结果更新登录消息
            self.whatsappLoginMessage = result.cleared
                ? "已登出并清除凭据。"
                : "未找到 WhatsApp 会话。"
            self.whatsappLoginQrDataUrl = nil           // 清空二维码
        } catch {
            self.whatsappLoginMessage = error.localizedDescription  // 记录错误信息
        }
        await self.refresh(probe: true)             // 刷新通道状态
    }

    /// 登出 Telegram
    func logoutTelegram() async {
        guard !self.telegramBusy else { return }     // Telegram 操作忙则直接返回
        self.telegramBusy = true                     // 设置忙状态
        defer { self.telegramBusy = false }          // 延迟执行，确保忙状态被重置
        do {
            let params: [String: AnyCodable] = [     // 构建请求参数
                "channel": AnyCodable("telegram"), // 通道名称
            ]
            // 发送请求并解码响应
            let result: ChannelLogoutResult = try await GatewayConnection.shared.requestDecoded(
                method: .channelsLogout,             // 请求方法
                params: params,                      // 请求参数
                timeoutMs: 15000)                    // 超时时间
            // 根据结果更新配置状态
            if result.envToken == true {
                self.configStatus = "Telegram 令牌仍通过环境变量设置；配置已清除。"
            } else {
                self.configStatus = result.cleared
                    ? "Telegram 令牌已清除。"
                    : "未配置 Telegram 令牌。"
            }
            await self.loadConfig()                   // 重新加载配置
        } catch {
            self.configStatus = error.localizedDescription  // 记录错误信息
        }
        await self.refresh(probe: true)             // 刷新通道状态
    }
}

/// WhatsApp 登录启动结果
private struct WhatsAppLoginStartResult: Codable {
    let qrDataUrl: String?  // 二维码数据 URL
    let message: String     // 消息
}

/// WhatsApp 登录等待结果
private struct WhatsAppLoginWaitResult: Codable {
    let connected: Bool     // 是否连接
    let message: String     // 消息
}

/// 通道登出结果
private struct ChannelLogoutResult: Codable {
    let channel: String?    // 通道名称
    let accountId: String?  // 账户 ID
    let cleared: Bool       // 是否已清除
    let envToken: Bool?     // 是否为环境变量令牌
}

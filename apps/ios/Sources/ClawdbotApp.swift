import SwiftUI

/// 应用程序入口点
@main
struct MoltbotApp: App {
    /// 应用程序模型，管理应用状态
    @State private var appModel: NodeAppModel
    /// 网关连接控制器，处理网络连接
    @State private var gatewayController: GatewayConnectionController
    /// 场景阶段环境变量，用于监听应用生命周期状态变化
    @Environment(\.scenePhase) private var scenePhase

    /// 初始化方法
    init() {
        // 引导网关设置存储的持久化
        GatewaySettingsStore.bootstrapPersistence()
        // 创建应用程序模型实例
        let appModel = NodeAppModel()
        // 初始化应用程序模型状态
        _appModel = State(initialValue: appModel)
        // 初始化网关连接控制器状态
        _gatewayController = State(initialValue: GatewayConnectionController(appModel: appModel))
    }

    /// 应用程序主体结构
    var body: some Scene {
        WindowGroup {
            // 根画布视图
            RootCanvas()
                // 注入应用程序模型环境
                .environment(self.appModel)
                // 注入语音唤醒环境
                .environment(self.appModel.voiceWake)
                // 注入网关控制器环境
                .environment(self.gatewayController)
                // 处理URL打开事件
                .onOpenURL { url in
                    Task { await self.appModel.handleDeepLink(url: url) }
                }
                // 监听场景阶段变化
                .onChange(of: self.scenePhase) { _, newValue in
                    // 更新应用程序模型的场景阶段
                    self.appModel.setScenePhase(newValue)
                    // 更新网关控制器的场景阶段
                    self.gatewayController.setScenePhase(newValue)
                }
        }
    }
}

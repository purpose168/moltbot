import SwiftUI

/// 小动物状态标签
/// 
/// 用于显示小动物状态的 SwiftUI 视图
struct CritterStatusLabel: View {
    /// 是否暂停
    var isPaused: Bool
    /// 是否睡眠
    var isSleeping: Bool
    /// 是否工作
    var isWorking: Bool
    /// 耳朵增强是否激活
    var earBoostActive: Bool
    /// 眨眼时钟
    var blinkTick: Int
    /// 发送庆祝时钟
    var sendCelebrationTick: Int
    /// 网关状态
    var gatewayStatus: GatewayProcessManager.Status
    /// 动画是否启用
    var animationsEnabled: Bool
    /// 图标状态
    var iconState: IconState

    /// 眨眼程度
    @State var blinkAmount: CGFloat = 0
    /// 下次眨眼时间
    @State var nextBlink = Date().addingTimeInterval(Double.random(in: 3.5...8.5))
    /// 摆动角度
    @State var wiggleAngle: Double = 0
    /// 摆动偏移
    @State var wiggleOffset: CGFloat = 0
    /// 下次摆动时间
    @State var nextWiggle = Date().addingTimeInterval(Double.random(in: 6.5...14))
    /// 腿摆动幅度
    @State var legWiggle: CGFloat = 0
    /// 下次腿摆动时间
    @State var nextLegWiggle = Date().addingTimeInterval(Double.random(in: 5.0...11.0))
    /// 耳朵摆动幅度
    @State var earWiggle: CGFloat = 0
    /// 下次耳朵摆动时间
    @State var nextEarWiggle = Date().addingTimeInterval(Double.random(in: 7.0...14.0))
}

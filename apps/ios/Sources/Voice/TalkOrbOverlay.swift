import SwiftUI

/// 语音交互圆形覆盖视图
/// 显示一个带有脉冲动画效果的圆形UI元素，用于语音交互模式
struct TalkOrbOverlay: View {
    /// 应用模型环境变量，用于获取应用状态和颜色配置
    @Environment(NodeAppModel.self) private var appModel
    /// 脉冲动画状态，控制圆形的缩放和透明度变化
    @State private var pulse: Bool = false

    var body: some View {
        // 获取应用的主题颜色
        let seam = self.appModel.seamColor
        // 获取当前语音模式状态文本，并去除首尾空白字符
        let status = self.appModel.talkMode.statusText.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(spacing: 14) {
            ZStack {
                // 第一层圆形：外层脉冲效果
                Circle()
                    .stroke(seam.opacity(0.26), lineWidth: 2)  // 使用主题颜色，透明度0.26
                    .frame(width: 320, height: 320)            // 设置圆形大小
                    .scaleEffect(self.pulse ? 1.15 : 0.96)     // 根据脉冲状态缩放
                    .opacity(self.pulse ? 0.0 : 1.0)          // 根据脉冲状态改变透明度
                    .animation(.easeOut(duration: 1.3).repeatForever(autoreverses: false), value: self.pulse)  // 应用动画效果

                // 第二层圆形：中层脉冲效果
                Circle()
                    .stroke(seam.opacity(0.18), lineWidth: 2)  // 使用主题颜色，透明度0.18
                    .frame(width: 320, height: 320)            // 设置圆形大小
                    .scaleEffect(self.pulse ? 1.45 : 1.02)     // 根据脉冲状态缩放
                    .opacity(self.pulse ? 0.0 : 0.9)           // 根据脉冲状态改变透明度
                    .animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false).delay(0.2), value: self.pulse)  // 应用动画效果，延迟0.2秒

                // 中心圆形：主视觉元素
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                seam.opacity(0.95),     // 中心：主题颜色，透明度0.95
                                seam.opacity(0.40),     // 中间：主题颜色，透明度0.40
                                Color.black.opacity(0.55),  // 边缘：黑色，透明度0.55
                            ],
                            center: .center,          // 渐变中心
                            startRadius: 1,           // 渐变起始半径
                            endRadius: 112))          // 渐变结束半径
                    .frame(width: 190, height: 190)    // 设置圆形大小
                    .overlay(
                        Circle()
                            .stroke(seam.opacity(0.35), lineWidth: 1))  // 叠加边框效果
                    .shadow(color: seam.opacity(0.32), radius: 26, x: 0, y: 0)  // 主题颜色阴影
                    .shadow(color: Color.black.opacity(0.50), radius: 22, x: 0, y: 10)  // 黑色阴影，营造立体感
            }
            .contentShape(Circle())  // 设置点击区域为圆形
            .onTapGesture {          // 点击手势处理
                self.appModel.talkMode.userTappedOrb()  // 调用用户点击圆形的处理方法
            }

            // 当状态文本不为空且不是"Off"时显示状态标签
            if !status.isEmpty, status != "Off" {
                Text(status)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))  // 字体设置：脚注大小，圆角设计，半粗体
                    .foregroundStyle(Color.white.opacity(0.92))                    // 文本颜色：白色，透明度0.92
                    .padding(.horizontal, 12)                                      // 水平内边距12
                    .padding(.vertical, 8)                                         // 垂直内边距8
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.40))                       // 背景：黑色，透明度0.40
                            .overlay(
                                Capsule().stroke(seam.opacity(0.22), lineWidth: 1)))  // 叠加边框效果
            }
        }
        .padding(28)  // 外层内边距28
        .onAppear {   // 视图出现时的处理
            self.pulse = true  // 启动脉冲动画
        }
        .accessibilityElement(children: .combine)  // 辅助功能：将子元素组合为一个可访问元素
        .accessibilityLabel("语音模式 \(status)")  // 辅助功能标签：语音模式状态
    }
}

import SwiftUI

/// 语音唤醒提示视图
/// 用于显示语音唤醒命令的提示信息
struct VoiceWakeToast: View {
    /// 要显示的命令文本
    var command: String
    /// 是否增强亮度
    var brighten: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // 麦克风图标
            Image(systemName: "mic.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)

            // 命令文本，限制为一行，超出部分显示省略号
            Text(self.command)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(self.brighten ? 0.24 : 0.18), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
        }
        .accessibilityLabel("语音唤醒")
        .accessibilityValue(self.command)
    }
}

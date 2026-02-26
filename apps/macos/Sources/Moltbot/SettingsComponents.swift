import SwiftUI

/// 设置开关行组件
/// 用于显示带有标题、副标题和开关控件的设置项
struct SettingsToggleRow: View {
    let title: String          // 标题文本
    let subtitle: String?      // 副标题文本（可选）
    @Binding var binding: Bool  // 开关状态绑定

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: self.$binding) {
                Text(self.title)
                    .font(.body)
            }
            .toggleStyle(.checkbox)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
